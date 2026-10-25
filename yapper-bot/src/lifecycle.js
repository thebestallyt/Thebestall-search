// Ablauf eines Events: veröffentlichen, starten, erinnern, beenden, Voting, Gewinner
const crypto = require('node:crypto');
const { api } = require('./api');
const store = require('./store');
const videos = require('./videos');
const perms = require('./perms');
const { TYPES } = require('./types');
const { parseWhen } = require('./time');
const { eventPayload, eventButtons, pickerPayload } = require('./render');
const { formatList, formatEntry, sortedEntries, chunkText, fmtDate } = require('./util');

const RESULTS_CACHE = 10 * 60_000;
const tzOf = (ev) => store.guildConfig(ev.guildId).timezone;

async function send(channelId, payload) {
	if (!channelId) return null;
	try {
		return await api.send(channelId, typeof payload === 'string' ? { content: payload } : payload);
	} catch (err) {
		console.warn(`Could not send a message to channel ${channelId}:`, err.message);
		return null;
	}
}

async function sendChunks(channelId, text) {
	for (const c of chunkText(text)) await send(channelId, c);
}

// Event-Nachricht bearbeiten – nur wenn sich wirklich etwas geändert hat
const lastRendered = new Map();
async function updateMessage(ev, force = false) {
	if (!ev.messageId) return;
	try {
		const payload = await eventPayload(ev);
		const key = JSON.stringify(payload);
		if (!force && lastRendered.get(ev.id) === key) return;
		await api.edit(ev.channelId, ev.messageId, payload);
		lastRendered.set(ev.id, key);
	} catch (err) {
		console.warn(`Could not update message of event #${ev.id}:`, err.message);
	}
}

// Start/Ende aus den Angaben berechnen (Dauer relativ zum Start, oder festes Datum)
function resolveTimes(ev, now = Date.now()) {
	const tz = tzOf(ev);
	let startsAt = ev.startsAt;
	if (ev.status === 'draft' || ev.status === 'scheduled') {
		const s = parseWhen(ev.startSpec, now, tz);
		if (s.error) return { error: `Start: ${s.error}` };
		startsAt = s.ms && s.ms > now + 30_000 ? s.ms : now;
	}
	if (!ev.endSpec) return ev.endsAt ? { startsAt, endsAt: ev.endsAt } : { error: `Please set when the event ends: \`/event set ${ev.id} end 7d\`` };
	const e = parseWhen(ev.endSpec, startsAt, tz);
	if (e.error) return { error: `End: ${e.error}` };
	if (e.ms <= startsAt) return { error: 'The end must be after the start.' };
	return { startsAt, endsAt: e.ms };
}

function validateForPublish(ev) {
	if (!ev.title?.trim()) return 'Please give the event a title.';
	if (ev.winnerMode === 'views' && ev.type !== 'views') return 'Winner mode "views" only works for video contests.';
	if (ev.winnerMode === 'votes' && (!ev.voting || ev.voting.mode === 'off')) return `Winner mode "votes" needs voting turned on: \`/event set ${ev.id} voting during\``;
	if (ev.type === 'views' && !ev.fields.some((f) => f.kind === 'channel')) return 'A video contest needs a join question of type `channel` (YouTube/TikTok channel link).';
	const t = resolveTimes(ev);
	return t.error ?? null;
}

function pingContent(ev) {
	if (!ev.pingRoleId) return '';
	return ev.pingRoleId === 'everyone' ? '@everyone' : `<@&${ev.pingRoleId}>`;
}

async function publish(ev, fallbackChannelId) {
	const times = resolveTimes(ev);
	if (times.error) return times.error;
	ev.channelId ??= fallbackChannelId;
	ev.startsAt = times.startsAt;
	ev.endsAt = times.endsAt;
	ev.status = ev.startsAt > Date.now() + 30_000 ? 'scheduled' : 'open';
	try {
		const ping = ev.status === 'open' ? pingContent(ev) : '';
		const msg = await api.send(ev.channelId, { ...(ping ? { content: ping } : {}), ...(await eventPayload(ev)) });
		if (!msg?.id) throw new Error('no message id returned');
		ev.messageId = msg.id;
	} catch (err) {
		ev.status = 'draft';
		ev.startsAt = null;
		ev.endsAt = null;
		return `I can't post in ${await perms.channelName(ev.guildId, ev.channelId)} (${err.message}). Check my permissions there.`;
	}
	store.save();
	return null;
}

async function startEvent(ev) {
	ev.status = 'open';
	store.save();
	await updateMessage(ev);
	const ping = pingContent(ev);
	await send(ev.channelId, { content: `${ping} 🚀 **${ev.title}** has started! Join with the button below or type \`/event join ${ev.id}\`.`.trim(), components: eventButtons(ev) });
}

async function sendReminder(ev, hours) {
	ev.remindersSent.push(hours);
	store.save();
	const left = hours >= 24 && hours % 24 === 0 ? `${hours / 24} day${hours > 24 ? 's' : ''}` : `${hours} hour${hours > 1 ? 's' : ''}`;
	await send(ev.channelId, { content: `⏰ Only **${left}** left for **${ev.title}**! Ends ${fmtDate(ev.endsAt, tzOf(ev))}.`, components: eventButtons(ev) });
}

// ---------- Video-Ranking ----------

const running = new Map();
async function viewResults(ev, force = false) {
	if (!force && ev.results && Date.now() - ev.results.checkedAt < RESULTS_CACHE) return ev.results;
	if (!['open', 'scheduled'].includes(ev.status) && ev.results && !force) return ev.results;
	if (!running.has(ev.id)) {
		running.set(ev.id, videos.checkEvent(ev).then((r) => {
			ev.results = r;
			store.save();
			return r;
		}).finally(() => running.delete(ev.id)));
	}
	return running.get(ev.id);
}

// ---------- Voting ----------

function tallyVotes(ev) {
	const counts = {};
	for (const target of Object.values(ev.votes)) if (ev.entries[target]) counts[target] = (counts[target] ?? 0) + 1;
	return sortedEntries(ev)
		.map(([uid]) => ({ userId: uid, votes: counts[uid] ?? 0 }))
		.sort((a, b) => b.votes - a.votes);
}

// Teilnehmer samt Stimmen entfernen
function removeEntry(ev, uid) {
	delete ev.entries[uid];
	delete ev.votes[uid];
	for (const [voter, target] of Object.entries(ev.votes)) if (target === uid) delete ev.votes[voter];
	if (ev.results) ev.results.ranking = ev.results.ranking.filter((r) => r.userId !== uid);
	if (ev.pick) ev.pick.selected = ev.pick.selected.filter((u) => u !== uid);
}

// ---------- Ende ----------

async function closeEvent(ev) {
	if (!['open', 'scheduled'].includes(ev.status)) return;
	ev.closedAt = Date.now();
	if (ev.voting?.mode === 'after' && Object.keys(ev.entries).length > 1) {
		const v = parseWhen(ev.voting.durationSpec || '1d', Date.now(), tzOf(ev));
		ev.status = 'voting';
		ev.votingEndsAt = v.ms ?? Date.now() + 86_400_000;
		store.save();
		await updateMessage(ev);
		await send(ev.channelId, {
			content: `🗳️ Submissions for **${ev.title}** are closed – **voting is open** until ${fmtDate(ev.votingEndsAt, tzOf(ev))}! Press 🗳️ Vote below.`,
			components: eventButtons(ev),
		});
		return;
	}
	await finalize(ev);
}

const randomPick = (arr, n) => {
	const a = [...arr];
	for (let i = a.length - 1; i > 0; i--) {
		const j = crypto.randomInt(i + 1);
		[a[i], a[j]] = [a[j], a[i]];
	}
	return a.slice(0, n);
};

const resultsChannelOf = (ev) => ev.resultsChannelId ?? store.guildConfig(ev.guildId).resultsChannelId ?? ev.channelId;

async function finalize(ev) {
	ev.status = 'closed';
	ev.closedAt ??= Date.now();
	store.save();
	await updateMessage(ev);

	const entries = sortedEntries(ev);
	const resultsChannel = resultsChannelOf(ev);

	// Rangliste je nach Modus
	let ranking = null; // [{userId, score, text}]
	if (ev.type === 'views' && entries.length) {
		try {
			const r = await viewResults(ev, true);
			ranking = r.ranking.map((x) => ({ userId: x.userId, score: x.best?.views ?? 0, text: x.best ? `${videos.fmt(x.best.views)} views` : 'no video found' }));
		} catch (err) {
			console.warn(`Video check of event #${ev.id} failed:`, err.message);
		}
	}
	if (ev.voting && ev.voting.mode !== 'off') {
		ranking = tallyVotes(ev).map((x) => ({ userId: x.userId, score: x.votes, text: `${x.votes} vote${x.votes === 1 ? '' : 's'}` }));
	}

	await send(resultsChannel, {
		embeds: [{
			title: `🏁 ${ev.title} has ended!`,
			description: entries.length ? `**${entries.length}** participant(s).` : 'Nobody joined this event.',
			color: ev.color ?? TYPES[ev.type].color,
			footer: { text: `Event #${ev.id}` },
		}],
	});
	if (entries.length && ev.type === 'views' && ev.results) {
		await sendChunks(resultsChannel, `📊 **Views ranking**\n\n${videos.formatRanking(ev.results, { showNotes: true, hashtag: ev.views?.hashtag })}`);
	}
	if (entries.length && ranking && ev.voting && ev.voting.mode !== 'off') {
		await sendChunks(resultsChannel, `🗳️ **Votes**\n\n${ranking.map((r, i) => `**${i + 1}.** ${formatEntry(ev, r.userId, ev.entries[r.userId])} – ${r.text}`).join('\n')}`);
	}
	if (entries.length && (ev.showParticipants || resultsChannel !== ev.channelId)) {
		await sendChunks(resultsChannel, `📋 **Participants**\n\n${formatList(ev)}`);
	}

	if (!entries.length || ev.winnerMode === 'none') {
		ev.status = 'finished';
		store.save();
		await updateMessage(ev);
		if (ev.winnerMode === 'none' && entries.length) await send(ev.channelId, `🏁 **${ev.title}** is closed – **${entries.length}** signed up. See you there!`);
		return;
	}

	const n = Math.min(ev.winnerCount, entries.length);
	if (ev.winnerMode === 'random') return setWinners(ev, randomPick(entries.map(([u]) => u), n), null);
	if ((ev.winnerMode === 'votes' || ev.winnerMode === 'views') && ranking) {
		const top = ranking.filter((r) => r.score > 0).slice(0, n).map((r) => r.userId);
		if (top.length) return setWinners(ev, top, null, ranking);
	}

	// Manuell (oder kein eindeutiges Ergebnis): Knöpfe für Staff zum Auswählen
	ev.pick = { order: (ranking ?? entries.map(([u]) => ({ userId: u, text: null }))).map((r) => ({ userId: r.userId, text: r.text ?? null })), selected: [] };
	store.save();
	await send(resultsChannel, pickerPayload(ev, 0));
}

// CSV-Text für den Export
function csvText(ev) {
	const esc = (v) => `"${String(Array.isArray(v) ? v.join(' ') : v ?? '').replace(/"/g, '""')}"`;
	const head = ['user_id', 'username', 'joined_at', ...ev.fields.map((f) => f.label)].map(esc).join(',');
	const lines = sortedEntries(ev).map(([uid, e]) => [uid, e.username, new Date(e.joinedAt).toISOString(), ...ev.fields.map((f) => e.values[f.key])].map(esc).join(','));
	return [head, ...lines].join('\n');
}

async function setWinners(ev, userIds, pickedBy, ranking = null) {
	ev.winners = userIds;
	ev.status = 'finished';
	delete ev.pick;
	store.save();
	await updateMessage(ev);
	const scoreOf = (u) => ranking?.find((r) => r.userId === u)?.text;
	const lines = userIds.map((u, i) => `${userIds.length > 1 ? `**${i + 1}.** ` : ''}@${ev.entries[u]?.username ?? u} – ${formatEntry(ev, u, ev.entries[u])}${scoreOf(u) ? ` (${scoreOf(u)})` : ''}`);
	const how = { random: 'Drawn at random 🎲', votes: 'Most votes 🗳️', views: 'Most views 📊', manual: pickedBy ? `Picked by @${pickedBy}` : '' }[ev.winnerMode] ?? '';
	await send(ev.channelId, {
		content: `${userIds.map((u) => `<@${u}>`).join(' ')} 🎉`,
		embeds: [{
			title: `🏆 ${userIds.length > 1 ? 'Winners' : 'Winner'} of ${ev.title}`,
			description: `Congratulations! 🎉\n\n${lines.join('\n')}${ev.prize ? `\n\n🎁 Prize: ${ev.prize}` : ''}${how ? `\n\n*${how}*` : ''}`.slice(0, 4000),
			color: 0xf1c40f,
			footer: { text: `Event #${ev.id}` },
		}],
	});
}

// Neu auslosen: andere Gewinner als bisher, wenn möglich
async function reroll(ev, howMany) {
	const pool = Object.keys(ev.entries).filter((u) => !ev.winners.includes(u));
	const n = Math.min(howMany ?? ev.winnerCount, pool.length);
	if (!n) return false;
	await setWinners(ev, randomPick(pool, n), null);
	return true;
}

// ---------- Zeitsteuerung ----------

async function tick() {
	const now = Date.now();
	for (const ev of store.allEvents()) {
		try {
			if (ev.status === 'scheduled' && ev.startsAt <= now) await startEvent(ev);
			if (ev.status === 'open') {
				for (const h of ev.reminders ?? []) {
					const at = ev.endsAt - h * 3_600_000;
					if (!ev.remindersSent.includes(h) && now >= at && now < ev.endsAt && at > ev.startsAt) await sendReminder(ev, h);
				}
				if (ev.endsAt <= now) await closeEvent(ev);
			}
			if (ev.status === 'voting' && ev.votingEndsAt <= now) await finalize(ev);
		} catch (err) {
			console.error(`Event #${ev.id}:`, err);
		}
	}
}

// Laufende Event-Nachrichten auffrischen (Restzeit, Teilnehmerzahl) – bearbeitet nur, wenn sich etwas geändert hat
async function refreshMessages(force = false) {
	for (const ev of store.allEvents()) {
		if (['open', 'scheduled', 'voting', 'closed'].includes(ev.status)) await updateMessage(ev, force);
	}
}

module.exports = {
	updateMessage, resolveTimes, validateForPublish, publish, closeEvent, finalize, setWinners, reroll,
	viewResults, tallyVotes, removeEntry, csvText, tick, refreshMessages, send, sendChunks,
};

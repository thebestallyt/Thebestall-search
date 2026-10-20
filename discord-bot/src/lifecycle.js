// Ablauf eines Events: veröffentlichen, starten, erinnern, beenden, Voting, Gewinner
const crypto = require('node:crypto');
const { ActionRowBuilder, AttachmentBuilder, EmbedBuilder, MessageFlags, StringSelectMenuBuilder } = require('discord.js');
const store = require('./store');
const videos = require('./videos');
const { TYPES } = require('./types');
const { parseWhen, ts } = require('./time');
const { eventEmbed, eventButtons } = require('./render');
const { formatList, formatEntry, entryLabel, sortedEntries, chunkText } = require('./util');

let client = null;
const init = (c) => { client = c; };

const QUIET = { flags: MessageFlags.SuppressEmbeds, allowedMentions: { parse: [] } };
const RESULTS_CACHE = 10 * 60_000;

async function fetchChannel(id) {
	try {
		return id ? await client.channels.fetch(id) : null;
	} catch {
		return null;
	}
}

async function updateMessage(ev) {
	if (!ev.messageId) return;
	try {
		const channel = await fetchChannel(ev.channelId);
		const msg = await channel.messages.fetch(ev.messageId);
		await msg.edit({ embeds: [eventEmbed(ev)], components: eventButtons(ev) });
	} catch (err) {
		console.warn(`Could not update message of event #${ev.id}:`, err.message);
	}
}

// Start/Ende aus den Angaben berechnen (Dauer relativ zum Start, oder festes Datum)
function resolveTimes(ev, now = Date.now()) {
	const tz = store.guildConfig(ev.guildId).timezone;
	let startsAt = ev.startsAt;
	if (ev.status === 'draft' || ev.status === 'scheduled') {
		const s = parseWhen(ev.startSpec, now, tz);
		if (s.error) return { error: `Start: ${s.error}` };
		startsAt = s.ms && s.ms > now + 30_000 ? s.ms : now;
	}
	if (!ev.endSpec) return ev.endsAt ? { startsAt, endsAt: ev.endsAt } : { error: 'Please set when the event ends (⏰ Time & limits).' };
	const e = parseWhen(ev.endSpec, startsAt, tz);
	if (e.error) return { error: `End: ${e.error}` };
	if (e.ms <= startsAt) return { error: 'The end must be after the start.' };
	return { startsAt, endsAt: e.ms };
}

function validateForPublish(ev) {
	if (!ev.title?.trim()) return 'Please give the event a title.';
	if (ev.winnerMode === 'views' && ev.type !== 'views') return 'Winner mode "Most views" only works for video contests.';
	if (ev.winnerMode === 'votes' && (!ev.voting || ev.voting.mode === 'off')) return 'Winner mode "Most votes" needs voting turned on (🗳️ Voting).';
	if (ev.type === 'views' && !ev.fields.some((f) => f.kind === 'channel')) return 'A video contest needs a "YouTube/TikTok channel link" question in the join form.';
	const t = resolveTimes(ev);
	return t.error ?? null;
}

async function publish(ev, fallbackChannelId) {
	const times = resolveTimes(ev);
	if (times.error) return times.error;
	ev.channelId ??= fallbackChannelId;
	ev.startsAt = times.startsAt;
	ev.endsAt = times.endsAt;
	ev.status = ev.startsAt > Date.now() + 30_000 ? 'scheduled' : 'open';
	const channel = await fetchChannel(ev.channelId);
	if (!channel) {
		ev.status = 'draft';
		return `I can't access <#${ev.channelId}>.`;
	}
	try {
		const ping = ev.status === 'open' ? pingPayload(ev) : {};
		const msg = await channel.send({ ...ping, embeds: [eventEmbed(ev)], components: eventButtons(ev) });
		ev.messageId = msg.id;
	} catch {
		ev.status = 'draft';
		return `I can't post in <#${ev.channelId}>. Check my permissions (View Channel, Send Messages, Embed Links).`;
	}
	store.save();
	return null;
}

function pingPayload(ev) {
	if (!ev.pingRoleId) return {};
	return ev.pingRoleId === ev.guildId
		? { content: '@everyone', allowedMentions: { parse: ['everyone'] } }
		: { content: `<@&${ev.pingRoleId}>`, allowedMentions: { roles: [ev.pingRoleId] } };
}

async function startEvent(ev) {
	ev.status = 'open';
	store.save();
	await updateMessage(ev);
	const channel = await fetchChannel(ev.channelId);
	await channel?.send({ ...pingPayload(ev), content: `${pingPayload(ev).content ?? ''} 🚀 **${ev.title}** has started! Join here: https://discord.com/channels/${ev.guildId}/${ev.channelId}/${ev.messageId}`.trim() }).catch(() => {});
}

async function sendReminder(ev, hours) {
	ev.remindersSent.push(hours);
	store.save();
	const channel = await fetchChannel(ev.channelId);
	const left = hours >= 24 && hours % 24 === 0 ? `${hours / 24} day${hours > 24 ? 's' : ''}` : `${hours} hour${hours > 1 ? 's' : ''}`;
	await channel?.send({ content: `⏰ Only **${left}** left for **${ev.title}**! Ends ${ts(ev.endsAt)}.`, ...QUIET }).catch(() => {});
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

// ---------- Ende ----------

async function closeEvent(ev) {
	if (!['open', 'scheduled'].includes(ev.status)) return;
	ev.closedAt = Date.now();
	if (ev.voting?.mode === 'after' && Object.keys(ev.entries).length > 1) {
		const v = parseWhen(ev.voting.durationSpec || '1d', Date.now(), store.guildConfig(ev.guildId).timezone);
		ev.status = 'voting';
		ev.votingEndsAt = v.ms ?? Date.now() + 86_400_000;
		store.save();
		await updateMessage(ev);
		const channel = await fetchChannel(ev.channelId);
		await channel?.send({ content: `🗳️ Submissions for **${ev.title}** are closed – **voting is open** until ${ts(ev.votingEndsAt)}! Use the 🗳️ Vote button on the event.`, ...QUIET }).catch(() => {});
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

async function finalize(ev) {
	ev.status = 'closed';
	ev.closedAt ??= Date.now();
	store.save();
	await updateMessage(ev);

	const entries = sortedEntries(ev);
	const resultsChannel = (await fetchChannel(ev.resultsChannelId ?? store.guildConfig(ev.guildId).resultsChannelId)) ?? (await fetchChannel(ev.channelId));
	const eventChannel = await fetchChannel(ev.channelId);

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

	try {
		if (resultsChannel) {
			await resultsChannel.send({
				embeds: [new EmbedBuilder().setColor(ev.color ?? TYPES[ev.type].color).setTitle(`🏁 ${ev.title} has ended!`)
					.setDescription(entries.length ? `**${entries.length}** participant(s).` : 'Nobody joined this event.').setFooter({ text: `Event #${ev.id}` })],
			});
			if (entries.length && ev.type === 'views' && ev.results) {
				for (const c of chunkText(`📊 **Views ranking**\n\n${videos.formatRanking(ev.results, { showNotes: true, hashtag: ev.views?.hashtag })}`)) await resultsChannel.send({ content: c, ...QUIET });
			}
			if (entries.length && ranking && ev.voting && ev.voting.mode !== 'off') {
				const text = ranking.map((r, i) => `**${i + 1}.** ${formatEntry(ev, r.userId, ev.entries[r.userId])} – ${r.text}`).join('\n');
				for (const c of chunkText(`🗳️ **Votes**\n\n${text}`)) await resultsChannel.send({ content: c, ...QUIET });
			}
			if (entries.length && (ev.showParticipants || resultsChannel.id !== ev.channelId)) {
				const chunks = chunkText(`📋 **Participants**\n\n${formatList(ev, { mention: true })}`);
				for (let i = 0; i < chunks.length; i++) {
					await resultsChannel.send({ content: chunks[i], ...QUIET, files: i === chunks.length - 1 ? [listFile(ev)] : [] });
				}
			}
		}
	} catch (err) {
		console.warn(`Could not post results of event #${ev.id}:`, err.message);
	}

	if (!entries.length || ev.winnerMode === 'none') {
		ev.status = 'finished';
		store.save();
		await updateMessage(ev);
		if (ev.winnerMode === 'none' && entries.length) await eventChannel?.send({ content: `🏁 **${ev.title}** is closed – **${entries.length}** signed up. See you there!`, ...QUIET }).catch(() => {});
		return;
	}

	const n = Math.min(ev.winnerCount, entries.length);
	if (ev.winnerMode === 'random') return setWinners(ev, randomPick(entries.map(([u]) => u), n), null);
	if ((ev.winnerMode === 'votes' || ev.winnerMode === 'views') && ranking) {
		const top = ranking.filter((r) => r.score > 0).slice(0, n).map((r) => r.userId);
		if (top.length) return setWinners(ev, top, null, ranking);
	}

	// Manuell (oder kein eindeutiges Ergebnis): Auswahlmenü für Staff
	try {
		const order = ranking ?? entries.map(([u]) => ({ userId: u, text: null }));
		if (order.length <= 25) {
			const select = new StringSelectMenuBuilder().setCustomId(`ev:pickwin:${ev.id}`).setPlaceholder(`👑 Staff: pick ${n > 1 ? `${n} winners` : 'the winner'}`)
				.setMinValues(1).setMaxValues(Math.min(n, order.length))
				.addOptions(order.map((r) => ({ label: entryLabel(ev, r.userId, ev.entries[r.userId]), description: (r.text ?? formatEntry(ev, r.userId, ev.entries[r.userId])).slice(0, 100), value: r.userId })));
			await resultsChannel?.send({ content: 'Staff: choose the winner(s) below (or use `/event winner`).', components: [new ActionRowBuilder().addComponents(select)] });
		} else {
			await resultsChannel?.send(`Staff: use \`/event winner event:${ev.id}\` to pick the winner(s).`);
		}
	} catch (err) {
		console.warn(`Could not post winner picker of event #${ev.id}:`, err.message);
	}
}

function listFile(ev) {
	const text = sortedEntries(ev).map(([uid, e]) => formatEntry(ev, uid, e)).join(',\n') || '(no participants)';
	return new AttachmentBuilder(Buffer.from(text, 'utf8'), { name: `event-${ev.id}-participants.txt` });
}

function csvFile(ev) {
	const esc = (v) => `"${String(Array.isArray(v) ? v.join(' ') : v ?? '').replace(/"/g, '""')}"`;
	const head = ['user_id', 'username', 'joined_at', ...ev.fields.map((f) => f.label)].map(esc).join(',');
	const rows = sortedEntries(ev).map(([uid, e]) => [uid, e.username, new Date(e.joinedAt).toISOString(), ...ev.fields.map((f) => e.values[f.key])].map(esc).join(','));
	return new AttachmentBuilder(Buffer.from([head, ...rows].join('\n'), 'utf8'), { name: `event-${ev.id}.csv` });
}

async function setWinners(ev, userIds, pickedBy, ranking = null) {
	ev.winners = userIds;
	ev.status = 'finished';
	store.save();
	await updateMessage(ev);
	const channel = await fetchChannel(ev.channelId);
	const scoreOf = (u) => ranking?.find((r) => r.userId === u)?.text;
	const lines = userIds.map((u, i) => `${userIds.length > 1 ? `**${i + 1}.** ` : ''}<@${u}> – ${formatEntry(ev, u, ev.entries[u])}${scoreOf(u) ? ` (${scoreOf(u)})` : ''}`);
	const how = { random: 'Drawn at random 🎲', votes: 'Most votes 🗳️', views: 'Most views 📊', manual: pickedBy ? `Picked by <@${pickedBy}>` : '' }[ev.winnerMode] ?? '';
	await channel?.send({
		content: userIds.map((u) => `<@${u}>`).join(' '),
		embeds: [new EmbedBuilder().setColor(0xf1c40f).setTitle(`🏆 ${userIds.length > 1 ? 'Winners' : 'Winner'} of ${ev.title}`)
			.setDescription(`Congratulations! 🎉\n\n${lines.join('\n')}${ev.prize ? `\n\n🎁 Prize: ${ev.prize}` : ''}${how ? `\n\n*${how}*` : ''}`.slice(0, 4000))
			.setFooter({ text: `Event #${ev.id}` })],
		allowedMentions: { users: userIds },
	}).catch((err) => console.warn(`Could not announce winners of event #${ev.id}:`, err.message));
}

// Neu auslosen (Giveaway): andere Gewinner als bisher, wenn möglich
async function reroll(ev, count) {
	const pool = Object.keys(ev.entries).filter((u) => !ev.winners.includes(u));
	const n = Math.min(count ?? ev.winnerCount, pool.length);
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

module.exports = {
	init, updateMessage, resolveTimes, validateForPublish, publish, closeEvent, finalize, setWinners, reroll,
	viewResults, tallyVotes, listFile, csvFile, tick, fetchChannel,
};

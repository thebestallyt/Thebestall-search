// Mitmachen: Fragen nacheinander per Direktnachricht (statt Formular), oder alles auf einmal mit "/event join <id> a | b"
const { api } = require('./api');
const store = require('./store');
const videos = require('./videos');
const perms = require('./perms');
const life = require('./lifecycle');
const { FIELD_KINDS } = require('./types');
const { btn, row, count } = require('./render');
const { normalizeLink, valueText, fmtDate } = require('./util');

const MAX_VIDEOS = 10;
const SESSION_TTL = 20 * 60_000;
const MAX_LEN = { text: 200, long: 1500, link: 400, number: 20, channel: 400, videos: 2000 };

// Laufende Frage-Runden: userId -> { evId, idx, values, existing, channelId, expires, username }
const sessions = new Map();

async function canJoin(ev, uid, isNew) {
	if (ev.status !== 'open') return '🔒 This event is not open.';
	if (ev.requiredRoleId && ev.requiredRoleId !== 'everyone' && !(await perms.hasRole(ev.guildId, uid, ev.requiredRoleId))) {
		return `🔑 You need the ${await perms.roleName(ev.guildId, ev.requiredRoleId)} role to join.`;
	}
	if (isNew && ev.maxParticipants && count(ev) >= ev.maxParticipants) return '😢 Sorry, this event is full.';
	return null;
}

// Eine Antwort prüfen und umwandeln -> { value } oder { error }
function checkAnswer(ev, f, raw) {
	const text = String(raw ?? '').trim();
	if (!text) return f.required ? { error: `Please answer "${f.label}".` } : { value: f.kind === 'videos' ? [] : '' };
	if (text.length > MAX_LEN[f.kind]) return { error: `That answer is too long (max ${MAX_LEN[f.kind]} characters).` };
	if (f.kind === 'text') return { value: text.replace(/\s+/g, ' ') };
	if (f.kind === 'long') return { value: text.replace(/[ \t]+/g, ' ') };
	if (f.kind === 'number') {
		const num = Number(text.replace(',', '.'));
		return Number.isFinite(num) ? { value: String(num) } : { error: `"${f.label}" must be a number.` };
	}
	if (f.kind === 'link') {
		const link = normalizeLink(text);
		return link ? { value: link } : { error: `"${f.label}" must be a valid link.` };
	}
	if (f.kind === 'channel') {
		const link = normalizeLink(text);
		const e = link ? videos.channelLinkError(link) : 'That is not a valid link.';
		if (e) return { error: e };
		const allowed = ev.views?.platforms ?? ['youtube', 'tiktok'];
		if (!allowed.includes(videos.platformOf(link))) return { error: `Only ${allowed.join(' / ')} channels are allowed in this event.` };
		return { value: link };
	}
	if (f.kind === 'videos') {
		const list = [];
		for (const part of text.split(/[\s,]+/).filter(Boolean)) {
			const link = normalizeLink(part);
			const e = link ? videos.videoLinkError(link) : `\`${part}\` is not a valid link.`;
			if (e) return { error: e };
			if (!list.includes(link)) list.push(link);
		}
		if (list.length > MAX_VIDEOS) return { error: `You can add at most ${MAX_VIDEOS} video links.` };
		return { value: list };
	}
	return { value: text };
}

// Vergleichs-Schlüssel für Links: "https://www.youtube.com/@X/" und "youtube.com/@x" sind derselbe Kanal
const sameLinkKey = (link) => String(link ?? '').toLowerCase().replace(/^https?:\/\//, '').replace(/^(www|m)\./, '').replace(/[/?#]+$/, '');

// Prüfungen über mehrere Antworten -> { error, idx } oder null
function crossCheck(ev, uid, values) {
	const channelField = ev.fields.find((f) => f.kind === 'channel');
	const videosField = ev.fields.find((f) => f.kind === 'videos');
	// Videos müssen zur Plattform des Kanals passen
	if (channelField && videosField && values[channelField.key]) {
		const plat = videos.platformOf(values[channelField.key]);
		const wrong = (values[videosField.key] ?? []).find((l) => videos.platformOf(l) !== plat);
		if (wrong) return { error: `\`${wrong}\` is not on the same platform as your channel. Only videos from your channel count.`, idx: ev.fields.indexOf(videosField) };
	}
	// Derselbe Kanal / Link darf nicht doppelt eingetragen werden
	const uniqueField = channelField ?? ev.fields.find((f) => f.kind === 'link');
	if (uniqueField && values[uniqueField.key]) {
		const mine = sameLinkKey(values[uniqueField.key]);
		const taken = Object.entries(ev.entries).some(([u, e]) => u !== uid && sameLinkKey(e.values[uniqueField.key]) === mine);
		if (taken) return { error: `This ${uniqueField.kind === 'channel' ? 'channel' : 'link'} was already entered by someone else.`, idx: ev.fields.indexOf(uniqueField) };
	}
	return null;
}

// Eintrag speichern und Bestätigungstext zurückgeben
async function saveEntry(ev, uid, username, values) {
	const existing = ev.entries[uid];
	const channelField = ev.fields.find((f) => f.kind === 'channel');
	const videosField = ev.fields.find((f) => f.kind === 'videos');
	ev.entries[uid] = {
		values,
		username,
		joinedAt: existing?.joinedAt ?? Date.now(),
		...(channelField && existing?.values[channelField.key] === values[channelField.key] && existing.youtubeChannelId ? { youtubeChannelId: existing.youtubeChannelId } : {}),
	};
	store.save();
	await life.updateMessage(ev);
	const summary = ev.fields.filter((f) => valueText(values[f.key])).map((f) => `**${f.label}:** ${valueText(values[f.key]).slice(0, 200)}`).join('\n');
	const tip = ev.type === 'views' && channelField && videos.platformOf(values[channelField.key]) === 'tiktok' && videosField && !values[videosField.key].length
		? '\n\n⚠️ TikTok videos can\'t be found automatically – join again and paste your video link(s).'
		: ev.type === 'views' && !videos.YOUTUBE_AUTO && videosField && !values[videosField.key].length
			? '\n\n⚠️ Don\'t forget to add your video link(s) – join again to edit your entry.'
			: '';
	const ends = ev.endsAt ? `\n\nEnds ${fmtDate(ev.endsAt, store.guildConfig(ev.guildId).timezone)}.` : '';
	return `${existing ? '✏️ Your entry was updated!' : `✅ You joined **${ev.title}**! Good luck! 🍀`}${summary ? `\n\n${summary}` : ''}${ends}${tip}`;
}

// ---------- Frage-Runde per DM ----------

function questionPayload(ev, s) {
	const f = ev.fields[s.idx];
	const old = s.existing?.values[f.key];
	const lines = [
		`**${ev.title}** – question ${s.idx + 1}/${ev.fields.length}`,
		`**${f.label}**${f.required ? '' : ' (optional)'}`,
	];
	if (f.placeholder) lines.push(`e.g. ${f.placeholder}`);
	if (f.kind === 'videos') lines.push('Paste your video links (one per line).');
	else if (['link', 'channel'].includes(f.kind)) lines.push(`Answer with a link (${FIELD_KINDS[f.kind]}).`);
	else if (f.kind === 'number') lines.push('Answer with a number.');
	if (valueText(old)) lines.push(`Current answer: ${valueText(old).slice(0, 300)}`);
	lines.push('', '✍️ Type your answer below.');
	const buttons = [];
	if (valueText(old)) buttons.push(btn(`ev:dq:${ev.id}:keep`, 'Keep current', 'primary', '↩️'));
	if (!f.required) buttons.push(btn(`ev:dq:${ev.id}:skip`, 'Skip', 'secondary', '⏭️'));
	buttons.push(btn(`ev:dq:${ev.id}:cancel`, 'Cancel', 'danger', '✖️'));
	return { content: lines.join('\n'), components: [row(...buttons)] };
}

// Startet das Mitmachen. Gibt den Text zurück, den der Nutzer sofort sehen soll.
async function startJoin(ev, uid, username) {
	const existing = ev.entries[uid];
	const problem = await canJoin(ev, uid, !existing);
	if (problem) return problem;
	if (!ev.fields.length) {
		if (existing) return `✅ You're already in **${ev.title}**!${ev.allowLeave ? ' Press **Leave** to leave.' : ''}`;
		return saveEntry(ev, uid, username, {});
	}
	if (existing && !ev.allowLeave) return '✅ You already joined. Entries can\'t be changed in this event.';
	let channelId;
	try {
		channelId = await api.openDm(uid);
		const s = { evId: ev.id, idx: 0, values: {}, existing, channelId, username, expires: Date.now() + SESSION_TTL };
		await api.send(channelId, {
			content: `👋 Let's ${existing ? 'edit your entry for' : 'get you into'} **${ev.title}**! I'll ask you ${ev.fields.length === 1 ? '1 question' : `${ev.fields.length} questions`}.\n_If I don't react to your answers, type this in the server instead:_ \`/event join ${ev.id} ${ev.fields.map((f) => f.label.replace(/\|/g, '/')).join(' | ')}\``,
		});
		await api.send(channelId, questionPayload(ev, s));
		sessions.set(uid, s);
	} catch (err) {
		console.warn(`Could not DM ${uid}:`, err.message);
		return `📭 I couldn't send you a DM. Type this in the server instead (answers separated by \`|\`):\n\`/event join ${ev.id} ${ev.fields.map((f) => f.label.replace(/\|/g, '/')).join(' | ')}\``;
	}
	return `📬 Check your DMs – I sent you ${ev.fields.length === 1 ? 'a question' : `${ev.fields.length} questions`}.`;
}

// Nächste Frage stellen oder am Ende speichern
async function advance(ev, uid, s) {
	if (s.idx < ev.fields.length) return api.send(s.channelId, questionPayload(ev, s));
	sessions.delete(uid);
	const problem = await canJoin(ev, uid, !ev.entries[uid]);
	if (problem) return api.send(s.channelId, { content: problem });
	const bad = crossCheck(ev, uid, s.values);
	if (bad) {
		s.idx = bad.idx;
		s.fixing = true; // nach der Korrektur direkt speichern statt alle Fragen nochmal
		sessions.set(uid, s);
		await api.send(s.channelId, { content: `❌ ${bad.error}` });
		return api.send(s.channelId, questionPayload(ev, s));
	}
	return api.send(s.channelId, { content: await saveEntry(ev, uid, s.username, s.values) });
}

// Antwort (Text, "skip", "keep", "cancel") auf die aktuelle Frage
async function answer(uid, raw, action = null) {
	const s = sessions.get(uid);
	if (!s) return false;
	const ev = store.getEvent(s.evId);
	if (!ev || ev.status !== 'open' || Date.now() > s.expires) {
		sessions.delete(uid);
		await api.send(s.channelId, { content: '⌛ This sign-up has expired or the event is closed. Press Join again to start over.' });
		return true;
	}
	const word = action ?? String(raw).trim().toLowerCase();
	if (word === 'cancel') {
		sessions.delete(uid);
		await api.send(s.channelId, { content: `✖️ Cancelled – ${s.existing ? 'your entry stays as it was' : 'you did not join'}.` });
		return true;
	}
	const f = ev.fields[s.idx];
	const old = s.existing?.values[f.key];
	if (word === 'keep' && valueText(old)) {
		s.values[f.key] = old;
	} else if (word === 'skip' && !f.required) {
		s.values[f.key] = f.kind === 'videos' ? [] : '';
	} else if (action) {
		return true; // Knopf passt nicht (mehr) zur aktuellen Frage
	} else {
		const res = checkAnswer(ev, f, raw);
		if (res.error) {
			await api.send(s.channelId, { content: `❌ ${res.error}\nPlease try again.` });
			return true;
		}
		s.values[f.key] = res.value;
	}
	s.idx = s.fixing ? ev.fields.length : s.idx + 1;
	s.expires = Date.now() + SESSION_TTL;
	await advance(ev, uid, s);
	return true;
}

// Alle Antworten auf einmal: "/event join 5 Luxon Studios | https://youtube.com/@luxon"
async function joinInline(ev, uid, username, text) {
	const existing = ev.entries[uid];
	const problem = await canJoin(ev, uid, !existing);
	if (problem) return problem;
	if (existing && !ev.allowLeave) return '✅ You already joined. Entries can\'t be changed in this event.';
	const parts = String(text).split('|').map((p) => p.trim());
	const values = {};
	for (const [n, f] of ev.fields.entries()) {
		const res = checkAnswer(ev, f, parts[n] ?? '');
		if (res.error) return `❌ ${res.error}\nFormat: \`/event join ${ev.id} ${ev.fields.map((x) => x.label.replace(/\|/g, '/')).join(' | ')}\``;
		values[f.key] = res.value;
	}
	const bad = crossCheck(ev, uid, values);
	if (bad) return `❌ ${bad.error}`;
	sessions.delete(uid);
	return saveEntry(ev, uid, username, values);
}

const hasSession = (uid) => sessions.has(uid);
const sessionChannel = (uid) => sessions.get(uid)?.channelId ?? null;

function cleanup() {
	const now = Date.now();
	for (const [uid, s] of sessions) if (now > s.expires) sessions.delete(uid);
}

module.exports = { startJoin, answer, joinInline, hasSession, sessionChannel, cleanup, canJoin, checkAnswer, sessions };

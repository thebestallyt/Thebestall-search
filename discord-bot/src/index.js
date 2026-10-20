// Event-Bot – Texte für Nutzer auf Englisch, Kommentare auf Deutsch
require('dotenv').config();
const {
	ActionRowBuilder,
	Client,
	Events,
	GatewayIntentBits,
	MessageFlags,
	ModalBuilder,
	StringSelectMenuBuilder,
	TextInputBuilder,
	TextInputStyle,
} = require('discord.js');
const store = require('./store');
const videos = require('./videos');
const life = require('./lifecycle');
const { TYPES, FIELD_KINDS, eventFromTemplate } = require('./types');
const { isValidTimeZone, parseWhen, ts } = require('./time');
const { eventEmbed, panel, configPanel, STATUS, count } = require('./render');
const { isStaff, memberRoleIds, normalizeLink, formatList, formatEntry, entryLabel, chunkText, valueText, yes, no } = require('./util');

const TICK = 20_000;
const MAX_VIDEOS = 10;
const EPH = { flags: MessageFlags.Ephemeral };
const NO_PERMISSION = '⛔ Only staff (admins / event managers) can do that.';

const client = new Client({ intents: [GatewayIntentBits.Guilds] });
life.init(client);

// ---------- Hilfen ----------

const reply = (i, content, extra = {}) =>
	i.deferred || i.replied ? i.followUp({ content, ...EPH, ...extra }) : i.reply({ content, ...EPH, ...extra });

const eventOf = (i, id) => {
	const ev = store.getEvent(String(id ?? '').replace(/\D/g, ''));
	return ev && ev.guildId === i.guildId ? ev : null;
};

function input(id, label, { value, placeholder, style = 'short', required = false, max = 200, min } = {}) {
	const t = new TextInputBuilder().setCustomId(id).setLabel(label.slice(0, 45))
		.setStyle(style === 'long' ? TextInputStyle.Paragraph : TextInputStyle.Short).setRequired(required).setMaxLength(max);
	if (min) t.setMinLength(min);
	if (placeholder) t.setPlaceholder(placeholder.slice(0, 100));
	if (value !== undefined && value !== null && String(value) !== '') t.setValue(String(value).slice(0, max));
	return new ActionRowBuilder().addComponents(t);
}
const modal = (id, title, rows) => new ModalBuilder().setCustomId(id).setTitle(title.slice(0, 45)).addComponents(...rows);
const field = (i, id) => {
	try {
		return i.fields.getTextInputValue(id).trim();
	} catch {
		return '';
	}
};

// Setup-Menü nach einer Änderung neu anzeigen (und Live-Event aktualisieren)
async function refreshPanel(i, ev, page = 'main', note = null) {
	store.save();
	if (!['draft'].includes(ev.status)) await life.updateMessage(ev);
	const payload = { ...panel(ev, i.guildId, page), content: note ?? '' };
	if (i.isModalSubmit?.() && !i.isFromMessage()) return i.reply({ ...payload, ...EPH });
	return i.update(payload);
}

// ---------- Slash-Commands ----------

async function handleCommand(i) {
	const sub = i.options.getSubcommand();
	const staff = isStaff(i);
	const publicCmds = ['list', 'participants', 'ranking', 'vote'];
	if (!publicCmds.includes(sub) && !staff) return reply(i, NO_PERMISSION);

	if (sub === 'create') {
		const type = i.options.getString('type');
		const ev = store.createEvent({ ...eventFromTemplate(type), guildId: i.guildId, createdBy: i.user.id, setupChannelId: i.channelId });
		return i.reply({ ...panel(ev, i.guildId), ...EPH });
	}
	if (sub === 'config') return i.reply({ ...configPanel(i.guildId), ...EPH });
	if (sub === 'list') return listEvents(i, staff);

	const ev = eventOf(i, i.options.getString('event'));
	if (!ev || (ev.status === 'draft' && !staff)) return reply(i, '❌ Event not found. Pick one from the list while typing.');

	if (sub === 'edit') {
		if (['finished', 'cancelled'].includes(ev.status)) return reply(i, `❌ **${ev.title}** is already ${ev.status} – use \`/event copy\` to reuse its settings.`);
		return i.reply({ ...panel(ev, i.guildId), ...EPH });
	}
	if (sub === 'copy') {
		const base = eventFromTemplate(ev.type);
		const keep = ['title', 'description', 'prize', 'imageUrl', 'color', 'joinLabel', 'channelId', 'resultsChannelId', 'pingRoleId', 'requiredRoleId',
			'startSpec', 'endSpec', 'maxParticipants', 'winnerCount', 'winnerMode', 'fields', 'listFormat', 'showParticipants', 'allowLeave', 'reminders', 'views', 'voting'];
		for (const k of keep) base[k] = structuredClone(ev[k]);
		if (!base.endSpec) base.endSpec = '7d';
		const copy = store.createEvent({ ...base, guildId: i.guildId, createdBy: i.user.id, setupChannelId: i.channelId });
		return i.reply({ ...panel(copy, i.guildId), content: `📄 Copied from **${ev.title}** (#${ev.id}).`, ...EPH });
	}
	if (sub === 'participants') return showParticipants(i, ev, staff);
	if (sub === 'ranking') return showRanking(i, ev, staff, i.options.getBoolean('refresh') === true);
	if (sub === 'vote') return castVote(i, ev, i.options.getString('entry'));
	if (sub === 'end') {
		if (ev.status === 'voting') {
			await i.deferReply(EPH);
			await life.finalize(ev);
			return i.editReply(`✅ Voting for **${ev.title}** has been closed.`);
		}
		if (!['open', 'scheduled'].includes(ev.status)) return reply(i, `❌ **${ev.title}** is not running.`);
		await i.deferReply(EPH);
		await life.closeEvent(ev);
		return i.editReply(`✅ **${ev.title}** has been ended.`);
	}
	if (sub === 'cancel') {
		if (['finished', 'cancelled'].includes(ev.status)) return reply(i, `❌ **${ev.title}** is already ${ev.status}.`);
		if (ev.status === 'draft') {
			store.deleteEvent(ev.id);
			return reply(i, `🗑️ Draft **${ev.title}** deleted.`);
		}
		ev.status = 'cancelled';
		ev.closedAt = Date.now();
		store.save();
		await life.updateMessage(ev);
		const ch = await life.fetchChannel(ev.channelId);
		await ch?.send({ content: `❌ **${ev.title}** has been cancelled.`, allowedMentions: { parse: [] } }).catch(() => {});
		return reply(i, `✅ **${ev.title}** has been cancelled.`);
	}
	if (sub === 'winner') {
		const users = ['user', 'user2', 'user3'].map((k) => i.options.getUser(k)).filter(Boolean);
		if (['open', 'scheduled', 'draft'].includes(ev.status)) return reply(i, '❌ This event is still running. End it first with `/event end`.');
		if (ev.status === 'cancelled') return reply(i, '❌ This event was cancelled.');
		const missing = users.filter((u) => !ev.entries[u.id]);
		if (missing.length) return reply(i, `❌ ${missing.map((u) => `${u}`).join(', ')} did not join this event.`);
		await i.deferReply(EPH);
		await life.setWinners(ev, [...new Set(users.map((u) => u.id))], i.user.id);
		return i.editReply(`🏆 Winner(s) of **${ev.title}** announced!`);
	}
	if (sub === 'reroll') {
		if (!['closed', 'finished'].includes(ev.status)) return reply(i, '❌ You can only reroll after the event has ended.');
		await i.deferReply(EPH);
		const ok = await life.reroll(ev, i.options.getInteger('count'));
		return i.editReply(ok ? `🎲 New winner(s) drawn for **${ev.title}**!` : '❌ Nobody left to draw.');
	}
	if (sub === 'remove') {
		const user = i.options.getUser('user');
		if (!ev.entries[user.id]) return reply(i, `❌ ${user} is not in **${ev.title}**.`);
		delete ev.entries[user.id];
		delete ev.votes[user.id];
		for (const [voter, target] of Object.entries(ev.votes)) if (target === user.id) delete ev.votes[voter];
		if (ev.results) ev.results.ranking = ev.results.ranking.filter((r) => r.userId !== user.id);
		store.save();
		await life.updateMessage(ev);
		return reply(i, `✅ Removed ${user} from **${ev.title}**.`);
	}
	if (sub === 'export') return i.reply({ content: `📄 **${ev.title}** – ${count(ev)} entries`, files: [life.csvFile(ev), life.listFile(ev)], ...EPH });
}

async function listEvents(i, staff) {
	const evs = store.guildEvents(i.guildId).filter((e) => staff || e.status !== 'draft');
	if (!evs.length) return reply(i, 'There are no events yet.' + (staff ? ' Create one with `/event create`.' : ''));
	const order = ['open', 'voting', 'scheduled', 'draft', 'closed', 'finished', 'cancelled'];
	evs.sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status) || b.id - a.id);
	const lines = evs.slice(0, 30).map((e) => {
		const when = e.status === 'open' && e.endsAt ? ` • ends ${ts(e.endsAt)}` : e.status === 'scheduled' ? ` • starts ${ts(e.startsAt)}` : '';
		const link = e.messageId ? ` • [open](https://discord.com/channels/${e.guildId}/${e.channelId}/${e.messageId})` : '';
		return `**#${e.id}** ${TYPES[e.type].emoji} **${e.title}** – ${STATUS[e.status]} • ${count(e)} joined${when}${link}`;
	});
	return i.reply({ content: lines.join('\n').slice(0, 1990), ...EPH, flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds });
}

async function showParticipants(i, ev, staff) {
	if (!ev.showParticipants && !staff) return reply(i, '🔒 The participant list of this event is private.');
	const n = count(ev);
	const header = `**${ev.title}** – ${n} participant(s)${ev.maxParticipants ? ` / ${ev.maxParticipants}` : ''}`;
	if (!n) return reply(i, `${header}\nNobody has joined yet.`);
	const list = formatList(ev, { mention: true });
	const fits = header.length + list.length < 1900;
	return i.reply({
		content: fits ? `${header}\n\n${list}` : `${header}\nThe list is too long for one message, see the file:`,
		files: fits ? [] : [life.listFile(ev)],
		flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds,
		allowedMentions: { parse: [] },
	});
}

async function showRanking(i, ev, staff, refresh) {
	if (ev.type === 'views') {
		if (!count(ev)) return reply(i, `**${ev.title}** – nobody has joined yet.`);
		await i.deferReply(EPH);
		const results = await life.viewResults(ev, refresh && staff && ev.status === 'open');
		const text = `📊 **${ev.title}** – views ranking (checked ${ts(results.checkedAt)})\n\n${videos.formatRanking(results, { showNotes: staff, hashtag: ev.views?.hashtag })}`;
		const [first, ...rest] = chunkText(text);
		await i.editReply({ content: first, flags: MessageFlags.SuppressEmbeds });
		for (const c of rest) await i.followUp({ content: c, flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds });
		return;
	}
	if (ev.voting && ev.voting.mode !== 'off') {
		if (!staff && ev.status !== 'finished') return reply(i, '🗳️ Votes are secret until the event is finished.');
		const t = life.tallyVotes(ev);
		if (!t.length) return reply(i, 'No entries yet.');
		const text = t.map((r, n) => `**${n + 1}.** ${formatEntry(ev, r.userId, ev.entries[r.userId], { mention: true })} – ${r.votes} vote${r.votes === 1 ? '' : 's'}`).join('\n');
		return i.reply({ content: chunkText(`🗳️ **${ev.title}** – votes\n\n${text}`)[0], flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds, allowedMentions: { parse: [] } });
	}
	return reply(i, 'This event has no ranking (no views or votes).');
}

function votingOpen(ev) {
	return (ev.status === 'open' && ev.voting?.mode === 'during') || ev.status === 'voting';
}

async function castVote(i, ev, targetId) {
	if (!votingOpen(ev)) return reply(i, '🗳️ Voting is not open for this event.');
	if (!ev.entries[targetId]) return reply(i, '❌ That entry does not exist.');
	if (targetId === i.user.id && !ev.voting.allowSelf) return reply(i, '❌ You can\'t vote for your own entry.');
	const before = ev.votes[i.user.id];
	ev.votes[i.user.id] = targetId;
	store.save();
	const label = entryLabel(ev, targetId, ev.entries[targetId]);
	return reply(i, before && before !== targetId ? `🔁 You changed your vote to **${label}**.` : `✅ You voted for **${label}**.`);
}

// ---------- Autocomplete ----------

async function handleAutocomplete(i) {
	const focused = i.options.getFocused(true);
	const q = String(focused.value ?? '').toLowerCase();
	if (focused.name === 'event') {
		const staff = isStaff(i);
		const sub = i.options.getSubcommand();
		const evs = store.guildEvents(i.guildId)
			.filter((e) => staff || e.status !== 'draft')
			.filter((e) => sub !== 'vote' || votingOpen(e))
			.filter((e) => !q || `${e.id} ${e.title}`.toLowerCase().includes(q.replace('#', '')))
			.sort((a, b) => b.id - a.id)
			.slice(0, 25);
		return i.respond(evs.map((e) => ({ name: `#${e.id} ${TYPES[e.type].emoji} ${e.title} – ${e.status}`.slice(0, 100), value: String(e.id) })));
	}
	if (focused.name === 'entry') {
		const ev = eventOf(i, i.options.getString('event'));
		if (!ev) return i.respond([]);
		const opts = Object.entries(ev.entries)
			.filter(([uid]) => ev.voting?.allowSelf || uid !== i.user.id)
			.map(([uid, e]) => ({ name: entryLabel(ev, uid, e), value: uid }))
			.filter((o) => !q || o.name.toLowerCase().includes(q))
			.slice(0, 25);
		return i.respond(opts);
	}
	return i.respond([]);
}

// ---------- Setup-Menü (Knöpfe, Auswahlmenüs, Formulare) ----------

function textModal(ev) {
	return modal(`ev:md_text:${ev.id}`, 'Text & look', [
		input('title', 'Title', { value: ev.title, required: true, max: 100 }),
		input('description', 'Description / rules', { value: ev.description, style: 'long', max: 3000, placeholder: 'What is this event about? Rules?' }),
		input('prize', 'Prize (optional)', { value: ev.prize, max: 200, placeholder: 'e.g. 1000 Robux' }),
		input('image', 'Image URL (optional)', { value: ev.imageUrl, max: 400, placeholder: 'https://… (png/jpg/gif)' }),
		input('color', 'Color (hex, optional)', { value: `#${(ev.color ?? TYPES[ev.type].color).toString(16).padStart(6, '0')}`, max: 7, placeholder: '#ff2e3e' }),
	]);
}

function timeModal(ev) {
	const rows = [];
	if (['draft', 'scheduled'].includes(ev.status)) {
		rows.push(input('start', 'Start (empty = when published)', { value: ev.startSpec, max: 40, placeholder: 'e.g. 2h  or  2026-10-31 18:00' }));
	}
	rows.push(
		input('end', 'End (duration from start, or date)', { value: ev.endSpec, required: true, max: 40, placeholder: 'e.g. 10d  or  2026-11-07 20:00' }),
		input('max', 'Max participants (empty = unlimited)', { value: ev.maxParticipants, max: 6, placeholder: 'e.g. 16' }),
		input('reminders', 'Reminders: hours before end', { value: ev.reminders.join(', '), max: 40, placeholder: 'e.g. 24, 1  (empty = off)' }),
	);
	return modal(`ev:md_time:${ev.id}`, 'Time & limits', rows);
}

function resultsModal(ev) {
	return modal(`ev:md_res:${ev.id}`, 'Winners, list & buttons', [
		input('count', 'Number of winners', { value: ev.winnerCount, required: true, max: 2 }),
		input('format', 'Participant list format', { value: ev.listFormat, required: true, max: 200, placeholder: `{user} plus question keys: ${ev.fields.map((f) => `{${f.key}}`).join(' ')}` }),
		input('join', 'Text on the join button', { value: ev.joinLabel, required: true, max: 80 }),
		input('public', 'Everyone can see participants? (yes/no)', { value: ev.showParticipants ? 'yes' : 'no', required: true, max: 5 }),
		input('leave', 'Allow leaving / editing? (yes/no)', { value: ev.allowLeave ? 'yes' : 'no', required: true, max: 5 }),
	]);
}

function viewsModal(ev) {
	return modal(`ev:md_views:${ev.id}`, 'Video settings', [
		input('hashtag', 'Required hashtag (empty = any video)', { value: ev.views.hashtag, max: 50, placeholder: 'e.g. weakspot' }),
		input('platforms', 'Platforms', { value: ev.views.platforms.join(', '), required: true, max: 30, placeholder: 'youtube, tiktok' }),
		input('onlynew', 'Only videos posted after start? (yes/no)', { value: ev.views.onlyNew ? 'yes' : 'no', required: true, max: 5 }),
	]);
}

function voteModal(ev) {
	return modal(`ev:md_vote:${ev.id}`, 'Voting', [
		input('mode', 'Voting: off / during / after', { value: ev.voting.mode, required: true, max: 10, placeholder: 'during = while open, after = after deadline' }),
		input('duration', 'Voting time after the deadline', { value: ev.voting.durationSpec, max: 20, placeholder: 'e.g. 1d (only for "after")' }),
		input('self', 'Can people vote for themselves? (yes/no)', { value: ev.voting.allowSelf ? 'yes' : 'no', required: true, max: 5 }),
	]);
}

function questionModal(ev, idx) {
	const f = idx === 'add' ? null : ev.fields[Number(idx)];
	const kinds = Object.keys(FIELD_KINDS).filter((k) => ev.type === 'views' || !['channel', 'videos'].includes(k));
	return modal(`ev:md_q:${ev.id}:${idx}`, f ? `Edit question ${Number(idx) + 1}` : 'Add a question', [
		input('label', 'Question (empty = delete this question)', { value: f?.label, max: 45, required: !f, placeholder: 'e.g. Your Roblox username' }),
		input('placeholder', 'Example text shown in the box (optional)', { value: f?.placeholder, max: 100 }),
		input('kind', `Answer type: ${kinds.join(' / ')}`, { value: f?.kind ?? 'text', required: true, max: 10 }),
		input('required', 'Required? (yes/no)', { value: f ? (f.required ? 'yes' : 'no') : 'yes', required: true, max: 5 }),
	]);
}

async function handlePanelModal(i, action, ev, extra) {
	const err = (m) => reply(i, `❌ ${m}`);
	if (action === 'md_text') {
		const color = field(i, 'color').replace('#', '');
		if (color && !/^[0-9a-f]{6}$/i.test(color)) return err('Color must be a hex code like `#ff2e3e`.');
		const img = field(i, 'image');
		const imageUrl = img ? normalizeLink(img) : null;
		if (img && !imageUrl) return err('The image URL is not valid.');
		Object.assign(ev, { title: field(i, 'title'), description: field(i, 'description'), prize: field(i, 'prize') || null, imageUrl, color: color ? parseInt(color, 16) : null });
		return refreshPanel(i, ev);
	}
	if (action === 'md_time') {
		const backup = { startSpec: ev.startSpec, endSpec: ev.endSpec, endsAt: ev.endsAt, startsAt: ev.startsAt };
		const maxText = field(i, 'max');
		const max = maxText ? Number(maxText) : null;
		if (maxText && (!Number.isInteger(max) || max < 1)) return err('Max participants must be a whole number (or empty).');
		const rem = field(i, 'reminders').split(/[\s,;]+/).filter(Boolean).map(Number);
		if (rem.some((h) => !(h > 0 && h <= 24 * 60))) return err('Reminders must be hours like `24, 1`.');
		if (['draft', 'scheduled'].includes(ev.status)) ev.startSpec = field(i, 'start');
		ev.endSpec = field(i, 'end');
		const t = life.resolveTimes(ev);
		if (t.error) {
			Object.assign(ev, backup);
			return err(t.error);
		}
		if (ev.status !== 'draft') {
			if (ev.status === 'scheduled') ev.startsAt = t.startsAt;
			ev.endsAt = t.endsAt;
			if (t.endsAt <= Date.now()) {
				Object.assign(ev, backup);
				return err('The new end is in the past. Use `/event end` to end it now.');
			}
		}
		ev.maxParticipants = max;
		ev.reminders = [...new Set(rem)].sort((a, b) => b - a);
		ev.remindersSent = ev.remindersSent.filter((h) => ev.reminders.includes(h) && Date.now() >= ev.endsAt - h * 3_600_000);
		return refreshPanel(i, ev);
	}
	if (action === 'md_res') {
		const n = Number(field(i, 'count'));
		if (!Number.isInteger(n) || n < 1 || n > 25) return err('Number of winners must be 1–25.');
		const pub = field(i, 'public'), leave = field(i, 'leave');
		if (!(yes(pub) || no(pub)) || !(yes(leave) || no(leave))) return err('Please answer with yes or no.');
		Object.assign(ev, { winnerCount: n, listFormat: field(i, 'format'), joinLabel: field(i, 'join'), showParticipants: yes(pub), allowLeave: yes(leave) });
		return refreshPanel(i, ev, 'winners');
	}
	if (action === 'md_views') {
		const plats = field(i, 'platforms').toLowerCase().split(/[\s,;/]+/).filter(Boolean);
		if (!plats.length || plats.some((p) => !['youtube', 'tiktok'].includes(p))) return err('Platforms must be `youtube`, `tiktok` or both.');
		const on = field(i, 'onlynew');
		if (!(yes(on) || no(on))) return err('Please answer with yes or no.');
		ev.views = { hashtag: field(i, 'hashtag').replace(/^#/, '').replace(/\s+/g, ''), platforms: [...new Set(plats)], onlyNew: yes(on) };
		ev.results = null;
		return refreshPanel(i, ev);
	}
	if (action === 'md_vote') {
		const mode = field(i, 'mode').toLowerCase();
		if (!['off', 'during', 'after'].includes(mode)) return err('Voting must be `off`, `during` or `after`.');
		const dur = field(i, 'duration') || '1d';
		if (mode === 'after' && parseWhen(dur, Date.now(), 'UTC').error) return err('Voting time must be a duration like `1d` or `12h`.');
		const self = field(i, 'self');
		if (!(yes(self) || no(self))) return err('Please answer with yes or no.');
		if (ev.status === 'voting' && mode !== 'after') return err('Voting is already running – you can\'t switch it off now.');
		ev.voting = { mode, durationSpec: dur, allowSelf: yes(self) };
		if (mode === 'off' && ev.winnerMode === 'votes') ev.winnerMode = 'manual';
		if (mode !== 'off' && ev.winnerMode === 'manual') ev.winnerMode = 'votes';
		return refreshPanel(i, ev);
	}
	if (action === 'md_q') {
		const label = field(i, 'label');
		const idx = extra === 'add' ? null : Number(extra);
		if (!label) {
			if (idx !== null) ev.fields.splice(idx, 1);
			return refreshPanel(i, ev, 'form');
		}
		const kind = field(i, 'kind').toLowerCase();
		const kinds = Object.keys(FIELD_KINDS).filter((k) => ev.type === 'views' || !['channel', 'videos'].includes(k));
		if (!kinds.includes(kind)) return err(`Answer type must be one of: ${kinds.join(', ')}.`);
		const req = field(i, 'required');
		if (!(yes(req) || no(req))) return err('Please answer with yes or no.');
		if (idx === null && ev.fields.length >= 5) return err('Discord allows at most 5 questions.');
		const key = idx !== null ? ev.fields[idx].key : uniqueKey(ev, label);
		const f = { key, label, placeholder: field(i, 'placeholder'), kind, required: yes(req) };
		if (idx === null) ev.fields.push(f);
		else ev.fields[idx] = f;
		return refreshPanel(i, ev, 'form');
	}
	if (action === 'md_tz') {
		const tz = field(i, 'tz');
		if (!isValidTimeZone(tz)) return err('Unknown timezone. Examples: `Europe/Berlin`, `America/New_York`, `UTC`.');
		store.guildConfig(i.guildId).timezone = tz;
		store.save();
		return i.isFromMessage() ? i.update(configPanel(i.guildId)) : i.reply({ ...configPanel(i.guildId), ...EPH });
	}
}

// Kurzer Schlüssel für {platzhalter} aus der Frage, z. B. "Roblox username" -> {roblox_username}
function uniqueKey(ev, label) {
	const base = label.toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 20) || 'q';
	const reserved = new Set(['user', 'username', ...ev.fields.map((f) => f.key)]);
	let key = base, n = 2;
	while (reserved.has(key)) key = `${base}${n++}`;
	return key;
}

async function handlePanel(i, action, ev, extra) {
	if (!isStaff(i)) return reply(i, NO_PERMISSION);
	if (['finished', 'cancelled'].includes(ev.status) && action !== 'done') return reply(i, `❌ **${ev.title}** is already ${ev.status}.`);

	if (action === 'pg') return i.update(panel(ev, i.guildId, extra));
	if (action === 'm_text') return i.showModal(textModal(ev));
	if (action === 'm_time') return i.showModal(timeModal(ev));
	if (action === 'm_res') return i.showModal(resultsModal(ev));
	if (action === 'm_views') return i.showModal(viewsModal(ev));
	if (action === 'm_vote') return i.showModal(voteModal(ev));
	if (action === 'q_pick') return i.showModal(questionModal(ev, i.values[0]));
	if (action === 'q_clear') {
		ev.fields = [];
		ev.listFormat = '{user}';
		return refreshPanel(i, ev, 'form');
	}
	if (action === 'set_chan') {
		if (ev.status !== 'draft' && i.values[0] !== ev.channelId) return reply(i, '❌ The event is already posted – its channel can\'t be changed anymore.');
		ev.channelId = i.values[0] ?? null;
		return refreshPanel(i, ev, 'channels');
	}
	if (action === 'set_res') { ev.resultsChannelId = i.values[0] ?? null; return refreshPanel(i, ev, 'channels'); }
	if (action === 'set_ping') { ev.pingRoleId = i.values[0] ?? null; return refreshPanel(i, ev, 'channels'); }
	if (action === 'set_req') { ev.requiredRoleId = i.values[0] ?? null; return refreshPanel(i, ev, 'channels'); }
	if (action === 'set_wmode') {
		const mode = i.values[0];
		if (mode === 'votes' && (!ev.voting || ev.voting.mode === 'off')) {
			if (!ev.voting) ev.voting = { mode: 'during', durationSpec: '1d', allowSelf: false };
			else ev.voting.mode = 'during';
		}
		ev.winnerMode = mode;
		return refreshPanel(i, ev, 'winners', mode === 'votes' ? '🗳️ Voting was turned on (members vote while the event is open). Change it under 🗳️ Voting.' : null);
	}
	if (action === 'preview') {
		const preview = { ...ev, status: ev.status === 'draft' ? 'open' : ev.status, startsAt: ev.startsAt ?? Date.now(), endsAt: ev.endsAt ?? (life.resolveTimes(ev).endsAt ?? null) };
		return i.reply({ content: '👁️ This is how the event will look:', embeds: [eventEmbed(preview)], ...EPH });
	}
	if (action === 'discard') {
		store.deleteEvent(ev.id);
		return i.update({ content: `🗑️ Draft **${ev.title}** deleted.`, embeds: [], components: [] });
	}
	if (action === 'done') return i.update({ content: `✅ Saved **${ev.title}**.`, embeds: [], components: [] });
	if (action === 'publish') {
		const problem = life.validateForPublish(ev);
		if (problem) return reply(i, `❌ ${problem}`);
		await i.deferUpdate();
		const error = await life.publish(ev, ev.setupChannelId ?? i.channelId);
		if (error) return i.followUp({ content: `❌ ${error}`, ...EPH });
		const when = ev.status === 'scheduled' ? `It starts ${ts(ev.startsAt)}` : 'It is open now';
		return i.editReply({ content: `🚀 **${ev.title}** was posted in <#${ev.channelId}>! ${when} and ends ${ts(ev.endsAt)}.`, embeds: [], components: [] });
	}
}

// ---------- Mitmachen ----------

function joinModal(ev, existing) {
	const rows = ev.fields.map((f, n) => {
		const max = { text: 200, long: 1500, link: 400, number: 20, channel: 400, videos: 2000 }[f.kind];
		const style = ['long', 'videos'].includes(f.kind) ? 'long' : 'short';
		const value = existing ? (Array.isArray(existing.values[f.key]) ? existing.values[f.key].join('\n') : existing.values[f.key]) : undefined;
		return input(`f_${n}`, f.label, { value, placeholder: f.placeholder || FIELD_KINDS[f.kind], style, required: f.required, max });
	});
	return modal(`ev:md_join:${ev.id}`, `${existing ? 'Edit' : 'Join'}: ${ev.title}`, rows);
}

function canJoin(i, ev, isNew) {
	if (ev.status !== 'open') return '🔒 This event is not open.';
	if (ev.requiredRoleId && !memberRoleIds(i).includes(ev.requiredRoleId)) return `🔑 You need the <@&${ev.requiredRoleId}> role to join.`;
	if (isNew && ev.maxParticipants && count(ev) >= ev.maxParticipants) return '😢 Sorry, this event is full.';
	return null;
}

async function handleJoinSubmit(i, ev) {
	const existing = ev.entries[i.user.id];
	const problem = canJoin(i, ev, !existing);
	if (problem) return reply(i, problem);
	const err = (m) => reply(i, `❌ ${m}`);
	const values = {};
	const channelField = ev.fields.find((f) => f.kind === 'channel');
	for (const [n, f] of ev.fields.entries()) {
		const raw = field(i, `f_${n}`);
		if (!raw) {
			if (f.required) return err(`Please answer "${f.label}".`);
			values[f.key] = f.kind === 'videos' ? [] : '';
			continue;
		}
		if (f.kind === 'text' || f.kind === 'long') values[f.key] = raw.replace(/[ \t]+/g, ' ');
		if (f.kind === 'number') {
			const num = Number(raw.replace(',', '.'));
			if (!Number.isFinite(num)) return err(`"${f.label}" must be a number.`);
			values[f.key] = String(num);
		}
		if (f.kind === 'link') {
			const link = normalizeLink(raw);
			if (!link) return err(`"${f.label}" must be a valid link.`);
			values[f.key] = link;
		}
		if (f.kind === 'channel') {
			const link = normalizeLink(raw);
			const e = link ? videos.channelLinkError(link) : 'That is not a valid link.';
			if (e) return err(e);
			const allowed = ev.views?.platforms ?? ['youtube', 'tiktok'];
			if (!allowed.includes(videos.platformOf(link))) return err(`Only ${allowed.join(' / ')} channels are allowed in this event.`);
			values[f.key] = link;
		}
		if (f.kind === 'videos') {
			const list = [];
			for (const part of raw.split(/[\s,]+/).filter(Boolean)) {
				const link = normalizeLink(part);
				const e = link ? videos.videoLinkError(link) : `\`${part}\` is not a valid link.`;
				if (e) return err(e);
				if (!list.includes(link)) list.push(link);
			}
			if (list.length > MAX_VIDEOS) return err(`You can add at most ${MAX_VIDEOS} video links.`);
			values[f.key] = list;
		}
	}
	// Videos müssen zur Plattform des Kanals passen
	const videosField = ev.fields.find((f) => f.kind === 'videos');
	if (channelField && videosField && values[channelField.key]) {
		const plat = videos.platformOf(values[channelField.key]);
		const wrong = values[videosField.key].find((l) => videos.platformOf(l) !== plat);
		if (wrong) return err(`\`${wrong}\` is not on the same platform as your channel. Only videos from your channel count.`);
	}
	// Derselbe Kanal / Link darf nicht doppelt eingetragen werden
	const uniqueField = channelField ?? ev.fields.find((f) => f.kind === 'link');
	if (uniqueField && values[uniqueField.key]) {
		const taken = Object.entries(ev.entries).some(([uid, e]) => uid !== i.user.id && String(e.values[uniqueField.key]).toLowerCase() === values[uniqueField.key].toLowerCase());
		if (taken) return err(`This ${uniqueField.kind === 'channel' ? 'channel' : 'link'} was already entered by someone else.`);
	}

	ev.entries[i.user.id] = {
		values,
		username: i.user.username,
		joinedAt: existing?.joinedAt ?? Date.now(),
		...(channelField && existing?.values[channelField.key] === values[channelField.key] && existing.youtubeChannelId ? { youtubeChannelId: existing.youtubeChannelId } : {}),
	};
	store.save();
	const summary = ev.fields.filter((f) => valueText(values[f.key])).map((f) => `**${f.label}:** ${valueText(values[f.key]).slice(0, 200)}`).join('\n');
	const tip = ev.type === 'views' && channelField && videos.platformOf(values[channelField.key]) === 'tiktok' && videosField && !values[videosField.key].length
		? '\n\n⚠️ TikTok videos can\'t be found automatically – click the button again and paste your video link(s).'
		: ev.type === 'views' && !videos.YOUTUBE_AUTO && videosField && !values[videosField.key].length
			? '\n\n⚠️ Don\'t forget to add your video link(s) – click the button again.'
			: '';
	await reply(i, `${existing ? '✏️ Your entry was updated!' : `✅ You joined **${ev.title}**! Good luck! 🍀`}\n\n${summary}${ev.endsAt ? `\n\nEnds ${ts(ev.endsAt)}.` : ''}${tip}`, { flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds });
	return life.updateMessage(ev);
}

async function handlePublic(i, action, ev) {
	if (action === 'join') {
		const existing = ev.entries[i.user.id];
		const problem = canJoin(i, ev, !existing);
		if (problem) return reply(i, problem);
		if (!ev.fields.length) {
			if (existing) return reply(i, `✅ You're already in **${ev.title}**!${ev.allowLeave ? ' Click **Leave** to leave.' : ''}`);
			ev.entries[i.user.id] = { values: {}, username: i.user.username, joinedAt: Date.now() };
			store.save();
			await reply(i, `✅ You joined **${ev.title}**! Good luck! 🍀${ev.endsAt ? ` Ends ${ts(ev.endsAt)}.` : ''}`);
			return life.updateMessage(ev);
		}
		if (existing && !ev.allowLeave) return reply(i, '✅ You already joined. Entries can\'t be changed in this event.');
		return i.showModal(joinModal(ev, existing));
	}
	if (action === 'leave') {
		if (ev.status !== 'open') return reply(i, '🔒 This event is closed.');
		if (!ev.allowLeave) return reply(i, '❌ Leaving is not allowed in this event.');
		if (!ev.entries[i.user.id]) return reply(i, 'You haven\'t joined this event.');
		delete ev.entries[i.user.id];
		delete ev.votes[i.user.id];
		for (const [voter, target] of Object.entries(ev.votes)) if (target === i.user.id) delete ev.votes[voter];
		store.save();
		await reply(i, `👋 You left **${ev.title}**.`);
		return life.updateMessage(ev);
	}
	if (action === 'vote') {
		if (!votingOpen(ev)) return reply(i, '🗳️ Voting is not open.');
		const opts = Object.entries(ev.entries).filter(([uid]) => ev.voting.allowSelf || uid !== i.user.id);
		if (!opts.length) return reply(i, 'There is nothing to vote for yet.');
		if (opts.length > 25) return reply(i, `There are many entries – use \`/event vote event:${ev.id}\` and type a name.`);
		const current = ev.votes[i.user.id];
		const sel = new StringSelectMenuBuilder().setCustomId(`ev:votepick:${ev.id}`).setPlaceholder('Choose your favourite')
			.addOptions(opts.map(([uid, e]) => ({ label: entryLabel(ev, uid, e), description: formatEntry(ev, uid, e).slice(0, 100), value: uid, default: uid === current })));
		return i.reply({ content: `🗳️ Vote for your favourite entry in **${ev.title}**:`, components: [new ActionRowBuilder().addComponents(sel)], ...EPH });
	}
	if (action === 'votepick') {
		const res = await castVoteQuiet(ev, i.user.id, i.values[0]);
		return i.update({ content: res, components: [] });
	}
	if (action === 'lb') return showRanking(i, ev, isStaff(i), false);
	if (action === 'list') return showParticipants(i, ev, isStaff(i));
	if (action === 'pickwin') {
		if (!isStaff(i)) return reply(i, NO_PERMISSION);
		if (ev.status !== 'closed') return reply(i, ev.status === 'finished' ? '❌ The winners were already picked.' : '❌ This event is not waiting for winners.');
		const picked = i.values.filter((u) => ev.entries[u]);
		await i.update({ content: `🏆 Winner(s) picked by ${i.user}: ${picked.map((u) => `<@${u}>`).join(', ')}`, components: [], allowedMentions: { parse: [] } });
		return life.setWinners(ev, picked, i.user.id);
	}
}

async function castVoteQuiet(ev, voterId, targetId) {
	if (!votingOpen(ev)) return '🗳️ Voting is closed.';
	if (!ev.entries[targetId]) return '❌ That entry no longer exists.';
	if (targetId === voterId && !ev.voting.allowSelf) return '❌ You can\'t vote for yourself.';
	ev.votes[voterId] = targetId;
	store.save();
	return `✅ You voted for **${entryLabel(ev, targetId, ev.entries[targetId])}**. You can change your vote any time while voting is open.`;
}

async function handleConfig(i, action) {
	if (!isStaff(i)) return reply(i, NO_PERMISSION);
	const cfg = store.guildConfig(i.guildId);
	if (action === 'cfg_staff') cfg.staffRoleIds = [...i.values];
	if (action === 'cfg_res') cfg.resultsChannelId = i.values[0] ?? null;
	if (action === 'cfg_tz') {
		return i.showModal(modal('ev:md_tz', 'Timezone', [input('tz', 'Timezone (IANA name)', { value: cfg.timezone, required: true, max: 50, placeholder: 'Europe/Berlin, America/New_York, UTC' })]));
	}
	store.save();
	return i.update(configPanel(i.guildId));
}

// ---------- Verteiler ----------

const PANEL = new Set(['pg', 'm_text', 'm_time', 'm_res', 'm_views', 'm_vote', 'q_pick', 'q_clear', 'set_chan', 'set_res', 'set_ping', 'set_req', 'set_wmode', 'preview', 'discard', 'done', 'publish']);
const PANEL_MODALS = new Set(['md_text', 'md_time', 'md_res', 'md_views', 'md_vote', 'md_q']);
// Alte Knöpfe aus der /contest-Version weiter unterstützen
const LEGACY = { join: 'join', leave: 'leave', modal: 'md_join', winner: 'pickwin', lb: 'lb' };

async function handleComponent(i) {
	let [prefix, action, id, extra] = i.customId.split(':');
	if (prefix === 'contest') action = LEGACY[action] ?? action;
	if (action?.startsWith('cfg_')) return handleConfig(i, action);
	if (action === 'md_tz') return isStaff(i) ? handlePanelModal(i, action, null) : reply(i, NO_PERMISSION);
	const ev = eventOf(i, id);
	if (!ev) return reply(i, '❌ This event no longer exists.');
	if (PANEL.has(action)) return handlePanel(i, action, ev, extra);
	if (PANEL_MODALS.has(action)) {
		if (!isStaff(i)) return reply(i, NO_PERMISSION);
		return handlePanelModal(i, action, ev, extra);
	}
	if (action === 'md_join') return handleJoinSubmit(i, ev);
	return handlePublic(i, action, ev);
}

client.on(Events.InteractionCreate, async (i) => {
	try {
		if (!i.inGuild()) return;
		if (i.isAutocomplete()) return await handleAutocomplete(i);
		if (i.isChatInputCommand() && i.commandName === 'event') return await handleCommand(i);
		if ((i.isMessageComponent() || i.isModalSubmit()) && /^(ev|contest):/.test(i.customId)) return await handleComponent(i);
	} catch (err) {
		console.error(err);
		if (i.isRepliable()) reply(i, '⚠️ Something went wrong. Please try again.').catch(() => {});
	}
});

let ticking = false;
async function tick() {
	if (ticking) return;
	ticking = true;
	try {
		await life.tick();
	} finally {
		ticking = false;
	}
}

client.once(Events.ClientReady, async (c) => {
	console.log(`Logged in as ${c.user.tag}`);
	if (!videos.YOUTUBE_AUTO) console.log('No YOUTUBE_API_KEY – YouTube participants have to paste their video links (views are read from the page).');
	// Nachrichten laufender Events auf die aktuellen Knöpfe bringen (z. B. nach einem Update)
	for (const ev of store.allEvents()) {
		if (['open', 'scheduled', 'voting', 'closed'].includes(ev.status)) await life.updateMessage(ev);
	}
	await tick();
	setInterval(tick, TICK);
});

if (require.main === module) {
	if (!process.env.DISCORD_TOKEN) {
		console.error('Please set DISCORD_TOKEN in .env (see .env.example)');
		process.exit(1);
	}
	client.login(process.env.DISCORD_TOKEN);
}

module.exports = { client };

// Textbefehle (/event …) und Knopf-Klicks – Texte für Nutzer auf Englisch, Kommentare auf Deutsch
const { api } = require('./api');
const store = require('./store');
const videos = require('./videos');
const perms = require('./perms');
const life = require('./lifecycle');
const join = require('./join');
const { TYPES, FIELD_KINDS, eventFromTemplate, winnerModesFor } = require('./types');
const { isValidTimeZone, parseWhen } = require('./time');
const { STATUS, eventEmbed, panelPayload, configPayload, votePayload, pickerPayload, votingOpen, count, btn, row, HELP } = require('./render');
const { normalizeLink, formatList, formatEntry, entryLabel, entryNumbers, sortedEntries, chunkText, yes, no, fmtDate, relative, mentionIds } = require('./util');

const NO_PERMISSION = '⛔ Only staff (admins / event managers) can do that.';
const STALE = 10 * 60_000; // ältere Befehle (z. B. nach langer Pause) werden ignoriert
const MAX_QUESTIONS = 10;
const TYPE_ALIASES = { video: 'views', videos: 'views', view: 'views', submit: 'submission', submissions: 'submission', 'sign-up': 'signup', signups: 'signup', tournament: 'signup', giveaways: 'giveaway' };
const KIND_ALIASES = { short: 'text', paragraph: 'long', url: 'link', num: 'number', video: 'videos' };
const isClear = (v) => /^(none|-|clear|remove|reset)$/i.test(String(v ?? '').trim());

const usernameOf = (author) => (typeof author === 'string' ? author : author?.username ?? author?.display_name ?? 'unknown');
const split1 = (s) => {
	const m = String(s ?? '').trim().match(/^(\S+)(?:\s+([\s\S]*))?$/);
	return m ? [m[1], (m[2] ?? '').trim()] : ['', ''];
};
const eventIn = (sid, idText) => {
	const id = String(idText ?? '').replace(/^#/, '');
	if (!/^\d+$/.test(id)) return null;
	const ev = store.getEvent(id);
	return ev && ev.guildId === sid ? ev : null;
};

// Eintrag finden über Nummer (#3), Erwähnung (<@id>) oder Namen
function findEntry(ev, token) {
	const t = String(token ?? '').trim();
	if (!t) return null;
	const num = t.match(/^#?(\d{1,4})$/);
	if (num) return sortedEntries(ev)[Number(num[1]) - 1]?.[0] ?? null;
	const mention = mentionIds(t)[0];
	if (mention) return ev.entries[mention] ? mention : null;
	if (ev.entries[t]) return t;
	const name = t.replace(/^@/, '').toLowerCase();
	const hit = sortedEntries(ev).find(([uid, e]) => e.username?.toLowerCase() === name || entryLabel(ev, uid, e).toLowerCase() === name);
	return hit?.[0] ?? null;
}

// Mehrere Einträge aus "1 3 @user" (Erwähnungen dürfen Leerzeichen-frei aneinander hängen)
function findEntries(ev, text) {
	const tokens = String(text ?? '').replace(/>\s*</g, '> <').split(/[\s,]+/).filter(Boolean);
	const found = [];
	const missing = [];
	for (const tok of tokens) {
		const uid = findEntry(ev, tok);
		if (uid) {
			if (!found.includes(uid)) found.push(uid);
		} else missing.push(tok);
	}
	return { found, missing };
}

async function refreshPanel(ev) {
	if (!ev.panel) return;
	try {
		await api.edit(ev.panel.channelId, ev.panel.messageId, await panelPayload(ev));
	} catch {
		// Übersicht wurde evtl. gelöscht – egal
	}
}

async function afterChange(ev) {
	store.save();
	if (ev.status !== 'draft') await life.updateMessage(ev);
	await refreshPanel(ev);
}

// Übersicht posten und merken, damit sie bei Änderungen mitläuft
async function postPanel(channelId, ev, content = '') {
	const msg = await api.send(channelId, await panelPayload(ev, content));
	if (msg?.id) {
		ev.panel = { channelId, messageId: msg.id };
		store.save();
	}
}

async function dmText(uid, text) {
	const channelId = await api.openDm(uid);
	for (const c of chunkText(text)) await api.send(channelId, { content: c });
}

// ---------- Einstellungen ändern: /event set <id> <setting> <value> ----------

const SETTING_ALIASES = {
	desc: 'description', rules: 'description', name: 'title', img: 'image', picture: 'image', colour: 'color',
	starts: 'start', ends: 'end', duration: 'end', limit: 'max', maxparticipants: 'max', reminder: 'reminders',
	result: 'results', resultschannel: 'results', requiredrole: 'role', winner: 'winners', count: 'winners', winnermode: 'mode',
	listformat: 'format', list: 'format', label: 'button', joinlabel: 'button', joinbutton: 'button', participants: 'public',
	tag: 'hashtag', platform: 'platforms', vote: 'voting', votes: 'voting', votingtime: 'votetime', self: 'selfvote',
};

async function applySetting(ev, rawKey, value) {
	const key = SETTING_ALIASES[rawKey.toLowerCase()] ?? rawKey.toLowerCase();
	const sid = ev.guildId;
	const v = String(value ?? '').trim();
	const yesNo = (target, prop) => {
		if (!(yes(v) || no(v))) return 'Please answer with `yes` or `no`.';
		target[prop] = yes(v);
		return null;
	};

	if (key === 'title') {
		if (!v || isClear(v)) return 'The title can\'t be empty.';
		ev.title = v.replace(/\s+/g, ' ').slice(0, 100);
		return null;
	}
	if (key === 'description') {
		ev.description = isClear(v) ? '' : v.slice(0, 3000);
		return null;
	}
	if (key === 'prize') {
		ev.prize = !v || isClear(v) ? null : v.slice(0, 200);
		return null;
	}
	if (key === 'image') {
		if (!v || isClear(v)) {
			ev.imageUrl = null;
			return null;
		}
		const url = normalizeLink(v);
		if (!url) return 'The image URL is not valid.';
		ev.imageUrl = url;
		return null;
	}
	if (key === 'color') {
		if (!v || isClear(v)) {
			ev.color = null;
			return null;
		}
		const hex = v.replace('#', '');
		if (!/^[0-9a-f]{6}$/i.test(hex)) return 'Color must be a hex code like `#ff2e3e`.';
		ev.color = parseInt(hex, 16);
		return null;
	}
	if (key === 'start' || key === 'end') {
		if (key === 'start' && !['draft', 'scheduled'].includes(ev.status)) return 'The event has already started – its start can\'t be changed.';
		if (key === 'end' && (!v || isClear(v))) return 'The event needs an end, e.g. `10d` or `2026-11-07 20:00`.';
		const backup = { startSpec: ev.startSpec, endSpec: ev.endSpec, endsAt: ev.endsAt, startsAt: ev.startsAt };
		if (key === 'start') ev.startSpec = isClear(v) || /^now$/i.test(v) ? '' : v;
		else ev.endSpec = v;
		const t = life.resolveTimes(ev);
		if (t.error) {
			Object.assign(ev, backup);
			return t.error;
		}
		if (ev.status !== 'draft') {
			if (t.endsAt <= Date.now()) {
				Object.assign(ev, backup);
				return `The new end is in the past. Use \`/event end ${ev.id}\` to end it now.`;
			}
			if (ev.status === 'scheduled') ev.startsAt = t.startsAt;
			ev.endsAt = t.endsAt;
			ev.remindersSent = ev.remindersSent.filter((h) => Date.now() >= ev.endsAt - h * 3_600_000);
		}
		return null;
	}
	if (key === 'max') {
		if (!v || isClear(v) || /^(unlimited|off)$/i.test(v)) {
			ev.maxParticipants = null;
			return null;
		}
		const n = Number(v);
		if (!Number.isInteger(n) || n < 1) return 'Max participants must be a whole number (or `none`).';
		ev.maxParticipants = n;
		return null;
	}
	if (key === 'reminders') {
		const hours = isClear(v) || /^off$/i.test(v) ? [] : v.replace(/h/gi, '').split(/[\s,;]+/).filter(Boolean).map(Number);
		if (hours.some((h) => !(h > 0 && h <= 24 * 60))) return 'Reminders must be hours before the end, like `24, 1` (or `off`).';
		ev.reminders = [...new Set(hours)].sort((a, b) => b - a);
		ev.remindersSent = ev.remindersSent.filter((h) => ev.reminders.includes(h) && ev.endsAt && Date.now() >= ev.endsAt - h * 3_600_000);
		return null;
	}
	if (key === 'channel' || key === 'results') {
		if (key === 'channel' && ev.status !== 'draft') return 'The event is already posted – its channel can\'t be changed anymore.';
		const prop = key === 'channel' ? 'channelId' : 'resultsChannelId';
		if (!v || isClear(v)) {
			ev[prop] = null;
			return null;
		}
		const ch = await perms.resolveChannel(sid, v);
		if (!ch) return `I can't find the channel \`${v}\`. Use #channel-name or the channel ID.`;
		ev[prop] = ch.id;
		return null;
	}
	if (key === 'ping' || key === 'role') {
		const prop = key === 'ping' ? 'pingRoleId' : 'requiredRoleId';
		if (!v || isClear(v)) {
			ev[prop] = null;
			return null;
		}
		const role = await perms.resolveRole(sid, v);
		if (!role) return `I can't find the role \`${v}\`. Use the role name or ID${key === 'ping' ? ' (or `everyone`)' : ''}.`;
		ev[prop] = key === 'role' && role.id === 'everyone' ? null : role.id;
		return null;
	}
	if (key === 'mode') {
		const mode = v.toLowerCase();
		const modes = winnerModesFor(ev.type);
		if (!modes.includes(mode)) return `Winner mode must be one of: ${modes.map((m) => `\`${m}\``).join(', ')}.`;
		if (mode === 'votes' && (!ev.voting || ev.voting.mode === 'off')) {
			ev.voting = { mode: 'during', durationSpec: ev.voting?.durationSpec ?? '1d', allowSelf: ev.voting?.allowSelf ?? false };
		}
		ev.winnerMode = mode;
		return null;
	}
	if (key === 'winners') {
		const n = Number(v);
		if (!Number.isInteger(n) || n < 1 || n > 25) return 'Number of winners must be 1–25.';
		ev.winnerCount = n;
		return null;
	}
	if (key === 'format') {
		if (!v) return `Example: \`/event set ${ev.id} format {user} - ${ev.fields[0] ? `{${ev.fields[0].key}}` : ''}\``;
		ev.listFormat = v.slice(0, 200);
		return null;
	}
	if (key === 'button') {
		if (!v || isClear(v)) return 'The button needs a text, e.g. `Join`.';
		ev.joinLabel = v.slice(0, 80);
		return null;
	}
	if (key === 'public') return yesNo(ev, 'showParticipants');
	if (key === 'leave') return yesNo(ev, 'allowLeave');
	if (['hashtag', 'platforms', 'onlynew'].includes(key)) {
		if (ev.type !== 'views') return 'Video settings only exist in video contests (`/event create views`).';
		if (key === 'hashtag') ev.views.hashtag = !v || isClear(v) ? '' : v.replace(/^#/, '').replace(/\s+/g, '');
		if (key === 'platforms') {
			const plats = v.toLowerCase().split(/[\s,;/]+/).filter(Boolean);
			if (!plats.length || plats.some((p) => !['youtube', 'tiktok'].includes(p))) return 'Platforms must be `youtube`, `tiktok` or both.';
			ev.views.platforms = [...new Set(plats)];
		}
		if (key === 'onlynew') {
			const e = yesNo(ev.views, 'onlyNew');
			if (e) return e;
		}
		ev.results = null;
		return null;
	}
	if (['voting', 'votetime', 'selfvote'].includes(key)) {
		ev.voting ??= { mode: 'off', durationSpec: '1d', allowSelf: false };
		if (key === 'voting') {
			const mode = v.toLowerCase();
			if (!['off', 'during', 'after'].includes(mode)) return 'Voting must be `off`, `during` (while the event is open) or `after` (after the deadline).';
			if (ev.status === 'voting' && mode !== 'after') return 'Voting is already running – you can\'t switch it off now.';
			ev.voting.mode = mode;
			if (mode === 'off' && ev.winnerMode === 'votes') ev.winnerMode = 'manual';
			if (mode !== 'off' && ev.winnerMode === 'manual') ev.winnerMode = 'votes';
			return null;
		}
		if (key === 'votetime') {
			if (parseWhen(v, Date.now(), 'UTC').error || !/^[\d\swdhm]+$/i.test(v)) return 'Voting time must be a duration like `1d` or `12h`.';
			ev.voting.durationSpec = v;
			return null;
		}
		return yesNo(ev.voting, 'allowSelf');
	}
	return `Unknown setting \`${rawKey}\`. See all settings with \`/event show ${ev.id}\`.`;
}

// ---------- Fragen: /event question <id> add|edit|remove|clear ----------

function uniqueKey(ev, label, skipIdx = -1) {
	const base = label.toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 20) || 'q';
	const reserved = new Set(['user', 'username', ...ev.fields.filter((_, i) => i !== skipIdx).map((f) => f.key)]);
	let key = base;
	let n = 2;
	while (reserved.has(key)) key = `${base}${n++}`;
	return key;
}

const allowedKinds = (ev) => Object.keys(FIELD_KINDS).filter((k) => ev.type === 'views' || !['channel', 'videos'].includes(k));

function questionList(ev) {
	if (!ev.fields.length) return `**${ev.title}** has no join questions – one click to join.`;
	return `🧾 **Join questions of ${ev.title}**\n${ev.fields.map((f, i) => `${i + 1}. ${f.label} – ${f.kind}${f.required ? ', required' : ', optional'}${f.placeholder ? ` – e.g. ${f.placeholder}` : ''} → \`{${f.key}}\``).join('\n')}`;
}

function questionCmd(ev, text) {
	const [action, rest] = split1(text);
	const act = action.toLowerCase();
	const usage = `Usage: \`/event question ${ev.id} add Question | type | required | example\`\nTypes: ${allowedKinds(ev).join(', ')} • required: yes/no`;
	if (!act || act === 'list') return { reply: `${questionList(ev)}\n\n${usage}` };
	if (act === 'clear') {
		if (ev.status !== 'draft') return { error: 'Questions can only be removed completely while the event is a draft.' };
		ev.fields = [];
		ev.listFormat = '{user}';
		return { reply: '🧹 All questions removed – people join with one click. (List format set to `{user}`.)' };
	}
	if (act === 'remove' || act === 'delete') {
		const n = Number(rest) - 1;
		if (!ev.fields[n]) return { error: `There is no question ${rest || '?'}.` };
		const [removed] = ev.fields.splice(n, 1);
		return { reply: `🗑️ Removed question "${removed.label}".` };
	}
	if (act !== 'add' && act !== 'edit') return { error: usage };
	let idx = null;
	let body = rest;
	if (act === 'edit') {
		const [num, after] = split1(rest);
		idx = Number(num) - 1;
		if (!ev.fields[idx]) return { error: `There is no question ${num || '?'}.` };
		body = after;
	} else if (ev.fields.length >= MAX_QUESTIONS) {
		return { error: `An event can have at most ${MAX_QUESTIONS} questions.` };
	}
	const old = idx !== null ? ev.fields[idx] : null;
	const [label = '', kindRaw = '', reqRaw = '', ...placeholder] = body.split('|').map((p) => p.trim());
	const kind = KIND_ALIASES[kindRaw.toLowerCase()] ?? (kindRaw.toLowerCase() || old?.kind || 'text');
	if (!allowedKinds(ev).includes(kind)) return { error: `Type must be one of: ${allowedKinds(ev).join(', ')}.` };
	if (reqRaw && !(yes(reqRaw) || no(reqRaw))) return { error: 'Required must be `yes` or `no`.' };
	const finalLabel = (label || old?.label || '').slice(0, 100);
	if (!finalLabel) return { error: usage };
	const f = {
		key: old ? old.key : uniqueKey(ev, finalLabel),
		label: finalLabel,
		placeholder: placeholder.length ? placeholder.join(' | ').slice(0, 100) : old?.placeholder ?? '',
		kind,
		required: reqRaw ? yes(reqRaw) : old?.required ?? true,
	};
	if (idx === null) ev.fields.push(f);
	else ev.fields[idx] = f;
	return { reply: `✅ Question ${idx === null ? ev.fields.length : idx + 1} ${idx === null ? 'added' : 'updated'}: "${f.label}" (${f.kind}, ${f.required ? 'required' : 'optional'}) → use \`{${f.key}}\` in the list format.` };
}

// ---------- Anzeigen ----------

async function listText(sid, staff) {
	const evs = store.guildEvents(sid).filter((e) => staff || e.status !== 'draft');
	if (!evs.length) return `There are no events yet.${staff ? ' Create one with `/event create <type>`.' : ''}`;
	const order = ['open', 'voting', 'scheduled', 'draft', 'closed', 'finished', 'cancelled'];
	evs.sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status) || b.id - a.id);
	return evs.slice(0, 30).map((e) => {
		const when = e.status === 'open' && e.endsAt ? ` • ends ${relative(e.endsAt)}` : e.status === 'scheduled' ? ` • starts ${relative(e.startsAt)}` : '';
		return `**#${e.id}** ${TYPES[e.type].emoji} **${e.title}** – ${STATUS[e.status]} • ${count(e)} joined${when}`;
	}).join('\n');
}

function participantsText(ev) {
	const n = count(ev);
	const header = `👥 **${ev.title}** – ${n} participant(s)${ev.maxParticipants ? ` / ${ev.maxParticipants}` : ''}`;
	return n ? `${header}\n\n${formatList(ev)}` : `${header}\nNobody has joined yet.`;
}

function votesText(ev) {
	const nums = entryNumbers(ev);
	const t = life.tallyVotes(ev);
	if (!t.length) return 'No entries yet.';
	return `🗳️ **${ev.title}** – votes\n\n${t.map((r, n) => `**${n + 1}.** #${nums.get(r.userId)} ${formatEntry(ev, r.userId, ev.entries[r.userId])} – ${r.votes} vote${r.votes === 1 ? '' : 's'}`).join('\n')}`;
}

const rankingText = (ev, results, staff) =>
	`📊 **${ev.title}** – views ranking (checked ${fmtDate(results.checkedAt, store.guildConfig(ev.guildId).timezone)})\n\n${videos.formatRanking(results, { showNotes: staff, hashtag: ev.views?.hashtag })}`;

function castVote(ev, voterId, targetId) {
	if (!votingOpen(ev)) return { error: '🗳️ Voting is not open for this event.' };
	if (!targetId || !ev.entries[targetId]) return { error: '❌ That entry does not exist.' };
	if (targetId === voterId && !ev.voting.allowSelf) return { error: '❌ You can\'t vote for your own entry.' };
	const before = ev.votes[voterId];
	ev.votes[voterId] = targetId;
	store.save();
	const label = entryLabel(ev, targetId, ev.entries[targetId]);
	return { ok: before && before !== targetId ? `🔁 You changed your vote to **${label}**.` : `✅ You voted for **${label}**. You can change your vote while voting is open.` };
}

function leave(ev, uid) {
	if (ev.status !== 'open') return '🔒 This event is closed.';
	if (!ev.allowLeave) return '❌ Leaving is not allowed in this event.';
	if (!ev.entries[uid]) return 'You haven\'t joined this event.';
	life.removeEntry(ev, uid);
	store.save();
	life.updateMessage(ev);
	return `👋 You left **${ev.title}**.`;
}

// ---------- Textbefehle ----------

function parseCommand(d) {
	if (d.command) {
		const args = Array.isArray(d.args) ? d.args.join(' ') : String(d.args ?? '');
		return { name: String(d.command).toLowerCase().replace(/^[/!]/, ''), args: args.trim() };
	}
	const m = String(d.content ?? '').trim().match(/^[/!]([a-z0-9_-]{1,32})(?:\s+([\s\S]*))?$/i);
	return m ? { name: m[1].toLowerCase(), args: (m[2] ?? '').trim() } : null;
}

async function onMessage(d, botId) {
	if (d.author_bot || (botId && d.author_id === botId)) return;
	const uid = d.author_id;
	if (!uid) return;
	// Antwort in einer laufenden Frage-Runde (DM)
	if (join.hasSession(uid) && (!d.server_id || join.sessionChannel(uid) === d.channel_id)) {
		const cmd = parseCommand(d);
		if (!cmd) return join.answer(uid, d.content ?? '');
	}
	if (!d.server_id) return;
	const cmd = parseCommand(d);
	if (!cmd || !['event', 'events'].includes(cmd.name)) return;
	if (d.created_at && Date.now() - Date.parse(d.created_at) > STALE) return;
	const ctx = {
		sid: d.server_id,
		cid: d.channel_id,
		uid,
		username: usernameOf(d.author),
		say: (payload) => api.send(d.channel_id, { ...(typeof payload === 'string' ? { content: payload } : payload), reply_to: d.id }),
	};
	try {
		await runCommand(ctx, cmd.args);
	} catch (err) {
		console.error(err);
		await ctx.say('⚠️ Something went wrong. Please try again.').catch(() => {});
	}
}

async function runCommand(ctx, args) {
	const [subRaw, rest] = split1(args);
	const sub = subRaw.toLowerCase();
	const staffOnly = ['create', 'new', 'show', 'edit', 'set', 'question', 'questions', 'q', 'publish', 'preview', 'copy', 'end', 'cancel', 'winner', 'winners', 'reroll', 'remove', 'kick', 'export', 'config', 'settings'];
	const staff = await perms.isStaff(ctx.sid, ctx.uid);
	if (staffOnly.includes(sub) && !staff) return ctx.say(NO_PERMISSION);
	const sayChunks = async (text) => {
		for (const c of chunkText(text)) await ctx.say(c);
	};

	if (!sub || sub === 'help') return sayChunks(HELP);
	if (sub === 'list') return sayChunks(await listText(ctx.sid, staff));

	if (sub === 'create' || sub === 'new') {
		const t = rest.toLowerCase().split(/\s+/)[0];
		const type = TYPES[t] ? t : TYPE_ALIASES[t];
		if (!type) return ctx.say(`Which kind of event? \`/event create <type>\`\n${Object.entries(TYPES).map(([k, x]) => `\`${k}\` – ${x.emoji} ${x.name}`).join('\n')}`);
		const ev = store.createEvent({ ...eventFromTemplate(type), guildId: ctx.sid, createdBy: ctx.uid, setupChannelId: ctx.cid });
		return postPanel(ctx.cid, ev, `🆕 Draft **#${ev.id}** created. Change anything below, then publish it.`);
	}

	if (sub === 'config' || sub === 'settings') {
		const [what, value] = split1(rest);
		const cfg = store.guildConfig(ctx.sid);
		const w = what.toLowerCase();
		if (w === 'staff') {
			if (isClear(value)) cfg.staffRoleIds = [];
			else {
				const ids = [];
				const tokens = value.includes('<@&') ? mentionIds(value, 'role').map((id) => `<@&${id}>`) : value.split(',').map((s) => s.trim()).filter(Boolean);
				for (const tok of tokens) {
					const role = await perms.resolveRole(ctx.sid, tok);
					if (!role || role.id === 'everyone') return ctx.say(`❌ I can't find the role \`${tok}\`. Separate role names with commas.`);
					ids.push(role.id);
				}
				if (!ids.length) return ctx.say('Usage: `/event config staff @Role, @Role2` (or `none`)');
				cfg.staffRoleIds = [...new Set(ids)].slice(0, 10);
			}
		} else if (w === 'results') {
			if (isClear(value)) cfg.resultsChannelId = null;
			else {
				const ch = await perms.resolveChannel(ctx.sid, value);
				if (!ch) return ctx.say(`❌ I can't find the channel \`${value}\`.`);
				cfg.resultsChannelId = ch.id;
			}
		} else if (w === 'timezone' || w === 'tz') {
			if (!isValidTimeZone(value)) return ctx.say('❌ Unknown timezone. Examples: `Europe/Berlin`, `America/New_York`, `UTC`.');
			cfg.timezone = value;
		} else if (w) {
			return ctx.say('Usage: `/event config staff …` • `/event config results …` • `/event config timezone …`');
		}
		if (w) store.save();
		return ctx.say({ ...(await configPayload(ctx.sid)), content: w ? '✅ Saved.' : '' });
	}

	// Ab hier brauchen alle Befehle eine Event-ID
	const [idText, more] = split1(rest);
	const ev = eventIn(ctx.sid, idText);
	if (!ev || (ev.status === 'draft' && !staff)) {
		return ctx.say(`❌ ${idText ? `Event \`${idText}\` not found.` : 'Which event? Add its number, e.g. `/event ' + sub + ' 3`.'} See \`/event list\`.`);
	}

	if (sub === 'show' || sub === 'edit') return postPanel(ctx.cid, ev);

	if (sub === 'set') {
		if (['finished', 'cancelled'].includes(ev.status)) return ctx.say(`❌ **${ev.title}** is already ${ev.status} – use \`/event copy ${ev.id}\` to reuse its settings.`);
		const [key, value] = split1(more);
		if (!key) return ctx.say(`Usage: \`/event set ${ev.id} <setting> <value>\` – all settings: \`/event show ${ev.id}\``);
		const error = await applySetting(ev, key, value);
		if (error) return ctx.say(`❌ ${error}`);
		await afterChange(ev);
		const note = key.toLowerCase() === 'mode' && ev.winnerMode === 'votes' && ev.voting?.mode === 'during' ? ' Voting is on (members vote while the event is open).' : '';
		return ctx.say(`✅ Saved \`${key.toLowerCase()}\` for **${ev.title}**.${note}${ev.panel ? '' : ` See all settings: \`/event show ${ev.id}\``}`);
	}

	if (['question', 'questions', 'q'].includes(sub)) {
		if (['finished', 'cancelled'].includes(ev.status)) return ctx.say(`❌ **${ev.title}** is already ${ev.status}.`);
		const res = questionCmd(ev, more);
		if (res.error) return ctx.say(`❌ ${res.error}`);
		if (/^(add|edit|remove|delete|clear)$/i.test(split1(more)[0])) await afterChange(ev);
		return ctx.say(res.reply);
	}

	if (sub === 'preview') {
		const preview = { ...ev, status: ev.status === 'draft' ? 'open' : ev.status, startsAt: ev.startsAt ?? Date.now(), endsAt: ev.endsAt ?? (life.resolveTimes(ev).endsAt ?? null) };
		return ctx.say({ content: '👁️ This is how the event will look:', embeds: [await eventEmbed(preview)] });
	}

	if (sub === 'publish') {
		if (ev.status !== 'draft') return ctx.say(`❌ **${ev.title}** is already published.`);
		const problem = life.validateForPublish(ev);
		if (problem) return ctx.say(`❌ ${problem}`);
		const error = await life.publish(ev, ev.setupChannelId ?? ctx.cid);
		if (error) return ctx.say(`❌ ${error}`);
		await refreshPanel(ev);
		return ctx.say(publishedText(ev));
	}

	if (sub === 'copy') {
		const base = eventFromTemplate(ev.type);
		const keep = ['title', 'description', 'prize', 'imageUrl', 'color', 'joinLabel', 'channelId', 'resultsChannelId', 'pingRoleId', 'requiredRoleId',
			'startSpec', 'endSpec', 'maxParticipants', 'winnerCount', 'winnerMode', 'fields', 'listFormat', 'showParticipants', 'allowLeave', 'reminders', 'views', 'voting'];
		for (const k of keep) base[k] = structuredClone(ev[k]);
		if (!base.endSpec) base.endSpec = '7d';
		const copy = store.createEvent({ ...base, guildId: ctx.sid, createdBy: ctx.uid, setupChannelId: ctx.cid });
		return postPanel(ctx.cid, copy, `📄 Copied from **${ev.title}** (#${ev.id}) – this is draft **#${copy.id}**.`);
	}

	if (sub === 'join') {
		const text = ev.fields.length && more ? await join.joinInline(ev, ctx.uid, ctx.username, more) : await join.startJoin(ev, ctx.uid, ctx.username);
		return ctx.say(text);
	}
	if (sub === 'leave') return ctx.say(leave(ev, ctx.uid));

	if (sub === 'participants') {
		if (!ev.showParticipants && !staff) return ctx.say('🔒 The participant list of this event is private.');
		if (!ev.showParticipants) {
			await dmText(ctx.uid, participantsText(ev)).then(() => ctx.say('📬 The list is private – I sent it to your DMs.'), () => ctx.say('❌ I couldn\'t DM you the private list.'));
			return;
		}
		return sayChunks(participantsText(ev));
	}

	if (sub === 'ranking') {
		if (ev.type === 'views') {
			if (!count(ev)) return ctx.say(`**${ev.title}** – nobody has joined yet.`);
			const refresh = staff && /^(refresh|now|new)$/i.test(more) && ev.status === 'open';
			const fresh = ev.results && (Date.now() - ev.results.checkedAt < 10 * 60_000 || !['open', 'scheduled'].includes(ev.status));
			if (refresh || !fresh) await ctx.say('⏳ Checking all videos, one moment…');
			const results = await life.viewResults(ev, refresh);
			return sayChunks(rankingText(ev, results, staff));
		}
		if (ev.voting && ev.voting.mode !== 'off') {
			if (ev.status === 'finished') return sayChunks(votesText(ev));
			if (!staff) return ctx.say('🗳️ Votes are secret until the event is finished.');
			await dmText(ctx.uid, votesText(ev)).then(() => ctx.say('📬 Votes are secret until the end – I sent them to your DMs.'), () => ctx.say('❌ I couldn\'t DM you the votes.'));
			return;
		}
		return ctx.say('This event has no ranking (no views or votes).');
	}

	if (sub === 'vote') {
		if (!more) {
			if (!votingOpen(ev)) return ctx.say('🗳️ Voting is not open for this event.');
			const list = sortedEntries(ev).map(([uid, e], i) => `**#${i + 1}** ${formatEntry(ev, uid, e)}`).join('\n');
			const text = `🗳️ **${ev.title}** – vote with \`/event vote ${ev.id} <number>\` or press the button:\n\n${list}`;
			return ctx.say({ content: chunkText(text)[0], components: [row(btn(`ev:vote:${ev.id}:0`, 'Vote', 'primary', '🗳️'))] });
		}
		const res = castVote(ev, ctx.uid, findEntry(ev, more));
		return ctx.say(res.error ?? res.ok);
	}

	if (sub === 'end') {
		if (ev.status === 'voting') {
			await life.finalize(ev);
			return ctx.say(`✅ Voting for **${ev.title}** has been closed.`);
		}
		if (!['open', 'scheduled'].includes(ev.status)) return ctx.say(`❌ **${ev.title}** is not running.`);
		await life.closeEvent(ev);
		return ctx.say(`✅ **${ev.title}** has been ended.`);
	}

	if (sub === 'cancel') {
		if (['finished', 'cancelled'].includes(ev.status)) return ctx.say(`❌ **${ev.title}** is already ${ev.status}.`);
		if (ev.status === 'draft') {
			store.deleteEvent(ev.id);
			if (ev.panel) await api.edit(ev.panel.channelId, ev.panel.messageId, { content: `🗑️ Draft **${ev.title}** deleted.`, embeds: [], components: [] }).catch(() => {});
			return ctx.say(`🗑️ Draft **${ev.title}** deleted.`);
		}
		ev.status = 'cancelled';
		ev.closedAt = Date.now();
		store.save();
		await life.updateMessage(ev);
		await refreshPanel(ev);
		await life.send(ev.channelId, `❌ **${ev.title}** has been cancelled.`);
		return ctx.say(`✅ **${ev.title}** has been cancelled.`);
	}

	if (sub === 'winner' || sub === 'winners') {
		if (['open', 'scheduled', 'draft'].includes(ev.status)) return ctx.say(`❌ This event is still running. End it first with \`/event end ${ev.id}\`.`);
		if (ev.status === 'cancelled') return ctx.say('❌ This event was cancelled.');
		const { found, missing } = findEntries(ev, more);
		if (missing.length) return ctx.say(`❌ Not found in this event: ${missing.join(', ')}. Use the numbers from \`/event participants ${ev.id}\` or @mentions.`);
		if (!found.length) return ctx.say(`Usage: \`/event winner ${ev.id} <number or @user> …\``);
		await life.setWinners(ev, found.slice(0, 25), ctx.username);
		return ctx.say(`🏆 Winner(s) of **${ev.title}** announced!`);
	}

	if (sub === 'reroll') {
		if (!['closed', 'finished'].includes(ev.status)) return ctx.say('❌ You can only reroll after the event has ended.');
		const n = more ? Number(more) : null;
		if (more && !(Number.isInteger(n) && n >= 1 && n <= 25)) return ctx.say('❌ Count must be 1–25.');
		const ok = await life.reroll(ev, n);
		return ctx.say(ok ? `🎲 New winner(s) drawn for **${ev.title}**!` : '❌ Nobody left to draw.');
	}

	if (sub === 'remove' || sub === 'kick') {
		const target = findEntry(ev, more);
		if (!target) return ctx.say(`❌ \`${more || '?'}\` is not in **${ev.title}**. Use a number from \`/event participants ${ev.id}\` or an @mention.`);
		const name = ev.entries[target].username;
		life.removeEntry(ev, target);
		store.save();
		await life.updateMessage(ev);
		return ctx.say(`✅ Removed @${name} from **${ev.title}**.`);
	}

	if (sub === 'export') {
		const csv = life.csvText(ev);
		const list = sortedEntries(ev).map(([uid, e]) => formatEntry(ev, uid, e)).join(',\n') || '(no participants)';
		try {
			const channelId = await api.openDm(ctx.uid);
			await api.send(channelId, { content: `📄 **${ev.title}** – ${count(ev)} entries` });
			for (const c of chunkText(csv, 1880)) await api.send(channelId, { content: `\`\`\`csv\n${c}\n\`\`\`` });
			for (const c of chunkText(list, 1880)) await api.send(channelId, { content: `\`\`\`\n${c}\n\`\`\`` });
			return ctx.say('📬 I sent you the export (CSV + list) in your DMs.');
		} catch {
			return ctx.say('❌ I couldn\'t DM you the export.');
		}
	}

	return ctx.say(`Unknown command \`${sub}\`. Type \`/event help\`.`);
}

function publishedText(ev) {
	const tz = store.guildConfig(ev.guildId).timezone;
	const when = ev.status === 'scheduled' ? `It starts ${fmtDate(ev.startsAt, tz)}` : 'It is open now';
	return `🚀 **${ev.title}** was posted! ${when} and ends ${fmtDate(ev.endsAt, tz)}.`;
}

// ---------- Knöpfe ----------

async function onInteraction(d) {
	const [prefix, action, id, extra, extra2] = String(d.custom_id ?? '').split(':');
	if (prefix !== 'ev') return;
	if (d.expires_at && Date.parse(d.expires_at) < Date.now()) return;
	const uid = d.user_id;
	const respond = (type, payload = {}) => api.callback(d.id, d.token, type, typeof payload === 'string' ? { content: payload } : payload);
	const eph = (payload) => respond('ephemeral', payload);
	// Nachricht mit dem Knopf ändern; falls das nicht klappt, als neue (nur für dich sichtbare) Antwort
	const update = async (payload) => {
		try {
			await respond('update', payload);
		} catch (err) {
			console.warn('update callback failed, falling back to ephemeral:', err.message);
			await eph(payload);
		}
	};

	try {
		// Frage-Runde in der DM
		if (action === 'dq') {
			await respond('ack').catch(() => {});
			if (['skip', 'keep', 'cancel'].includes(extra)) await join.answer(uid, '', extra);
			return;
		}
		const ev = store.getEvent(id);
		if (!ev || (d.server_id && ev.guildId !== d.server_id)) return eph('❌ This event no longer exists.');
		const sid = ev.guildId;
		const isStaff = () => perms.isStaff(sid, uid);

		if (action === 'join') return eph(await join.startJoin(ev, uid, d.username || 'unknown'));
		if (action === 'leave') return eph(leave(ev, uid));
		if (action === 'vote') {
			if (!votingOpen(ev)) return eph('🗳️ Voting is not open.');
			if (!sortedEntries(ev).some(([u]) => ev.voting.allowSelf || u !== uid)) return eph('There is nothing to vote for yet.');
			return eph(votePayload(ev, uid, 0));
		}
		if (action === 'vpg') {
			if (!votingOpen(ev)) return update({ content: '🗳️ Voting is closed.', components: [] });
			return update(votePayload(ev, uid, extra));
		}
		if (action === 'vp') {
			const res = castVote(ev, uid, extra);
			if (res.error) return eph(res.error);
			return update(votePayload(ev, uid, pageOf(ev, uid, extra), res.ok));
		}
		if (action === 'list') {
			const staff = await isStaff();
			if (!ev.showParticipants && !staff) return eph('🔒 The participant list of this event is private.');
			const chunks = chunkText(participantsText(ev));
			return eph(chunks.length > 1 ? `${chunks[0]}\n…\nFull list: \`/event participants ${ev.id}\`` : chunks[0]);
		}
		if (action === 'lb') {
			if (ev.type !== 'views') return eph('This event has no views ranking.');
			if (!count(ev)) return eph(`**${ev.title}** – nobody has joined yet.`);
			const staff = await isStaff();
			// Kurz warten; dauert die Prüfung länger, läuft sie im Hintergrund weiter
			const check = life.viewResults(ev, false);
			const results = await Promise.race([check, new Promise((r) => setTimeout(() => r(null), 2500))]);
			if (!results) {
				check.catch(() => {});
				return eph('⏳ I\'m checking all videos right now – press 📊 Ranking again in a minute.');
			}
			const chunks = chunkText(rankingText(ev, results, staff));
			return eph(chunks.length > 1 ? `${chunks[0]}\n…\nFull ranking: \`/event ranking ${ev.id}\`` : chunks[0]);
		}

		// Ab hier nur Staff
		if (!(await isStaff())) return eph(NO_PERMISSION);

		if (action === 'preview') {
			const preview = { ...ev, status: ev.status === 'draft' ? 'open' : ev.status, startsAt: ev.startsAt ?? Date.now(), endsAt: ev.endsAt ?? (life.resolveTimes(ev).endsAt ?? null) };
			return eph({ content: '👁️ This is how the event will look:', embeds: [await eventEmbed(preview)] });
		}
		if (action === 'panel') return update(await panelPayload(ev));
		if (action === 'discard') {
			if (ev.status !== 'draft') return eph('❌ Only drafts can be deleted. Use `/event cancel` for running events.');
			store.deleteEvent(ev.id);
			return update({ content: `🗑️ Draft **${ev.title}** deleted.`, embeds: [], components: [] });
		}
		if (action === 'publish') {
			if (ev.status !== 'draft') return eph(`❌ **${ev.title}** is already published.`);
			const problem = life.validateForPublish(ev);
			if (problem) return eph(`❌ ${problem}`);
			const error = await life.publish(ev, ev.setupChannelId ?? d.channel_id);
			if (error) return eph(`❌ ${error}`);
			return update(await panelPayload(ev, publishedText(ev)));
		}
		if (action === 'pick' || action === 'pw') {
			if (ev.status !== 'closed' || !ev.pick) return eph(ev.status === 'finished' ? '❌ The winners were already picked.' : '❌ This event is not waiting for winners.');
			if (action === 'pw' && ev.entries[extra]) {
				const sel = ev.pick.selected;
				const n = Math.min(ev.winnerCount, count(ev));
				if (sel.includes(extra)) ev.pick.selected = sel.filter((u) => u !== extra);
				else if (n === 1) ev.pick.selected = [extra];
				else if (sel.length < n) sel.push(extra);
				else return eph(`You already picked ${n}. Tap a picked entry to remove it first.`);
				store.save();
			}
			return update(pickerPayload(ev, action === 'pw' ? extra2 : extra));
		}
		if (action === 'pwok') {
			if (ev.status !== 'closed' || !ev.pick?.selected.length) return eph(ev.status === 'finished' ? '❌ The winners were already picked.' : '❌ Pick at least one entry first.');
			const picked = ev.pick.selected.filter((u) => ev.entries[u]);
			const names = picked.map((u) => `@${ev.entries[u].username}`).join(', ');
			await update({ content: `🏆 Winner(s) of **${ev.title}** picked by @${d.username || 'staff'}: ${names}`, components: [] });
			return life.setWinners(ev, picked, d.username || 'staff');
		}
		return eph('❌ Unknown button.');
	} catch (err) {
		console.error(err);
		await eph('⚠️ Something went wrong. Please try again.').catch(() => {});
	}
}

// Seite der Voting-Liste, auf der ein Eintrag steht (damit die Liste nach dem Klick dort bleibt)
function pageOf(ev, voterId, targetId) {
	const all = sortedEntries(ev).filter(([u]) => ev.voting?.allowSelf || u !== voterId);
	const i = all.findIndex(([u]) => u === targetId);
	return i < 0 ? 0 : Math.floor(i / 20);
}

module.exports = { onMessage, onInteraction, parseCommand, applySetting, questionCmd, findEntry };

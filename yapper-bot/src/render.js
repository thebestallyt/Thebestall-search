// Nachrichten-Bausteine für Yapin': Event-Nachricht, Einstellungs-Übersicht, Voting- und Gewinner-Knöpfe
const { TYPES, FIELD_KINDS, WINNER_MODES, winnerModesFor } = require('./types');
const { fmtDate, formatEntry, entryLabel, sortedEntries, entryNumbers } = require('./util');
const perms = require('./perms');
const store = require('./store');

const STATUS = {
	draft: '📝 Draft (not published yet)',
	scheduled: '🕒 Scheduled',
	open: '🟢 Open',
	voting: '🗳️ Voting',
	closed: '🔒 Closed – waiting for winners',
	finished: '🏁 Finished',
	cancelled: '❌ Cancelled',
};

const PAGE = 20; // 4 Reihen à 5 Knöpfe, die 5. Reihe ist für Blättern/Bestätigen
const count = (ev) => Object.keys(ev.entries).length;
const tzOf = (ev) => store.guildConfig(ev.guildId).timezone;
const clip = (s, n) => (String(s).length > n ? `${String(s).slice(0, n - 1)}…` : String(s));

function btn(id, label, style = 'secondary', emoji, disabled = false) {
	const b = { type: 'button', style, label: clip(label, 80), custom_id: id };
	if (emoji) b.emoji = emoji;
	if (disabled) b.disabled = true;
	return b;
}
const row = (...buttons) => ({ type: 'row', components: buttons.slice(0, 5) });
const rows = (buttons) => {
	const out = [];
	for (let i = 0; i < buttons.length; i += 5) out.push(row(...buttons.slice(i, i + 5)));
	return out;
};

// Grobe Restzeit, damit die Event-Nachricht nicht jede Minute bearbeitet werden muss
function roughly(ms) {
	const d = ms - Date.now();
	if (d <= 0) return 'now';
	if (d >= 2 * 86_400_000) return `in ${Math.round(d / 86_400_000)} days`;
	if (d >= 2 * 3_600_000) return `in ${Math.round(d / 3_600_000)} hours`;
	return 'in less than 2 hours';
}
const dateLine = (ev, ms) => `${fmtDate(ms, tzOf(ev))} (${roughly(ms)})`;

// Wie man mitmacht – automatisch je nach Typ
function howToJoin(ev) {
	const join = `**${ev.joinLabel}**`;
	const lines = [];
	if (ev.fields.length) lines.push(`Click ${join} – I'll send you ${ev.fields.length === 1 ? 'a question' : `${ev.fields.length} questions`} in your DMs.`);
	else lines.push(`Click ${join} to take part.`);
	if (ev.type === 'views') {
		const tag = ev.views?.hashtag ? `**#${ev.views.hashtag}**` : null;
		const plats = (ev.views?.platforms ?? ['youtube', 'tiktok']).map((p) => (p === 'youtube' ? 'YouTube' : 'TikTok')).join(' / ');
		lines.push(`Upload your video on ${plats}${tag ? ` with ${tag} in the title or description` : ''}${ev.views?.onlyNew !== false ? ' (only videos posted after the start count)' : ''}.`);
		lines.push('Most views wins – check the ranking with the 📊 button.');
	}
	if (ev.voting?.mode === 'during') lines.push('Vote for your favourite entry with the 🗳️ button!');
	if (ev.voting?.mode === 'after') lines.push('After the deadline everyone can vote for the best entry.');
	if (ev.winnerMode === 'random') lines.push(`${ev.winnerCount} winner${ev.winnerCount > 1 ? 's are' : ' is'} drawn at random at the end.`);
	if (ev.allowLeave && ev.fields.length) lines.push(`Click ${join} again to change your entry.`);
	lines.push(`No buttons? Type \`/event join ${ev.id}\`.`);
	return lines.join('\n');
}

async function eventEmbed(ev) {
	const t = TYPES[ev.type];
	const fields = [];
	const n = count(ev);
	fields.push({ name: '👥 Participants', value: ev.maxParticipants ? `${n} / ${ev.maxParticipants}` : String(n), inline: true });
	if (ev.prize) fields.push({ name: '🎁 Prize', value: ev.prize, inline: true });
	if (ev.winnerMode !== 'none') fields.push({ name: '🏆 Winners', value: String(ev.winnerCount), inline: true });
	if (ev.requiredRoleId) fields.push({ name: '🔑 Required role', value: await perms.roleName(ev.guildId, ev.requiredRoleId), inline: true });

	if (ev.status === 'scheduled' && ev.startsAt) fields.push({ name: '🕒 Starts', value: dateLine(ev, ev.startsAt) });
	if (['scheduled', 'open', 'draft'].includes(ev.status) && ev.endsAt) fields.push({ name: '⏰ Ends', value: dateLine(ev, ev.endsAt) });
	if (ev.status === 'voting' && ev.votingEndsAt) fields.push({ name: '🗳️ Voting ends', value: dateLine(ev, ev.votingEndsAt) });
	if (['scheduled', 'open', 'draft'].includes(ev.status)) fields.push({ name: '📝 How to join', value: howToJoin(ev) });
	if (['closed', 'finished', 'cancelled'].includes(ev.status)) {
		fields.push({ name: 'Status', value: STATUS[ev.status] + (ev.closedAt ? ` – ${fmtDate(ev.closedAt, tzOf(ev))}` : '') });
	}
	if (ev.winners.length) {
		const names = ev.winners.map((w) => `@${ev.entries[w]?.username ?? w}`).join(', ');
		fields.push({ name: ev.winners.length > 1 ? '🏆 Winners' : '🏆 Winner', value: clip(names, 1024) });
	}
	const embed = {
		title: clip(`${t.emoji} ${ev.title}`, 256),
		description: clip(ev.description || ' ', 4000),
		color: ev.color ?? t.color,
		fields,
		footer: { text: `Event #${ev.id}` },
	};
	if (ev.imageUrl) embed.image = { url: ev.imageUrl };
	if (ev.startsAt) embed.timestamp = new Date(ev.startsAt).toISOString();
	return embed;
}

const votingOpen = (ev) => (ev.status === 'open' && ev.voting?.mode === 'during') || ev.status === 'voting';

function eventButtons(ev) {
	const buttons = [];
	if (ev.status === 'open') {
		buttons.push(btn(`ev:join:${ev.id}`, ev.joinLabel, 'success', '✅'));
		if (ev.allowLeave) buttons.push(btn(`ev:leave:${ev.id}`, 'Leave'));
	} else if (ev.status === 'scheduled') {
		buttons.push(btn(`ev:join:${ev.id}`, 'Starts soon', 'secondary', '🕒', true));
	} else {
		buttons.push(btn(`ev:closed:${ev.id}`, ev.status === 'cancelled' ? 'Cancelled' : 'Closed', 'secondary', null, true));
	}
	if (votingOpen(ev)) buttons.push(btn(`ev:vote:${ev.id}:0`, 'Vote', 'primary', '🗳️'));
	if (ev.type === 'views' && ['open', 'closed', 'finished'].includes(ev.status)) buttons.push(btn(`ev:lb:${ev.id}`, 'Ranking', 'secondary', '📊'));
	if (ev.showParticipants && ev.status !== 'draft') buttons.push(btn(`ev:list:${ev.id}`, 'Participants', 'secondary', '👥'));
	return [row(...buttons)];
}

const eventPayload = async (ev) => ({ embeds: [await eventEmbed(ev)], components: eventButtons(ev) });

// ---------- Einstellungs-Übersicht (statt Setup-Menü) ----------

async function settingsEmbed(ev) {
	const t = TYPES[ev.type];
	const cfg = store.guildConfig(ev.guildId);
	const tz = cfg.timezone;
	const yn = (b) => (b ? 'yes' : 'no');
	const k = (key) => `\`${key}\``;
	const ch = async (id) => (id ? perms.channelName(ev.guildId, id) : null);
	const role = async (id) => (id ? perms.roleName(ev.guildId, id) : '–');
	const resDefault = cfg.resultsChannelId ? `${await ch(cfg.resultsChannelId)} (server default)` : 'event channel';
	const fields = [
		{
			name: '📝 Text & look',
			value: [
				`${k('title')} ${ev.title}`,
				`${k('description')} ${ev.description ? clip(ev.description.replace(/\n/g, ' '), 90) : '–'}`,
				`${k('prize')} ${ev.prize || '–'}`,
				`${k('image')} ${ev.imageUrl ? 'yes' : '–'} • ${k('color')} #${(ev.color ?? t.color).toString(16).padStart(6, '0')}`,
			].join('\n'),
		},
		{
			name: '⏰ Time & limits',
			value: [
				`${k('start')} ${ev.startsAt ? fmtDate(ev.startsAt, tz) : ev.startSpec || 'when published'}`,
				`${k('end')} ${ev.endsAt ? fmtDate(ev.endsAt, tz) : ev.endSpec || '–'}`,
				`${k('max')} ${ev.maxParticipants ?? 'unlimited'}`,
				`${k('reminders')} ${ev.reminders.length ? `${ev.reminders.map((h) => `${h}h`).join(', ')} before end` : 'off'}`,
				`Timezone: ${tz}`,
			].join('\n'),
			inline: true,
		},
		{
			name: '📢 Channels & roles',
			value: [
				`${k('channel')} ${(await ch(ev.channelId)) ?? 'channel where you typed /event create'}`,
				`${k('results')} ${(await ch(ev.resultsChannelId)) ?? resDefault}`,
				`${k('ping')} ${await role(ev.pingRoleId)}`,
				`${k('role')} ${await role(ev.requiredRoleId)} (needed to join)`,
			].join('\n'),
			inline: true,
		},
		{
			name: `🧾 Join questions – \`/event question ${ev.id} …\``,
			value: ev.fields.length
				? ev.fields.map((f, i) => `${i + 1}. ${f.label} (${f.kind}${f.required ? ', required' : ''}) → \`{${f.key}}\``).join('\n')
				: 'No questions – one click to join',
		},
		{
			name: '🏆 Winners & results',
			value: [
				`${k('mode')} ${ev.winnerMode} – ${WINNER_MODES[ev.winnerMode].label} (options: ${winnerModesFor(ev.type).join(', ')})`,
				`${k('winners')} ${ev.winnerCount}`,
				`${k('format')} \`${ev.listFormat}\``,
				`${k('button')} "${ev.joinLabel}"`,
				`${k('public')} ${yn(ev.showParticipants)} (everyone can see participants) • ${k('leave')} ${yn(ev.allowLeave)} (leave / edit entry)`,
			].join('\n'),
		},
	];
	if (ev.type === 'views') {
		fields.push({
			name: '🎥 Video settings',
			value: `${k('hashtag')} ${ev.views.hashtag ? `#${ev.views.hashtag}` : 'none (all videos count)'}\n${k('platforms')} ${ev.views.platforms.join(', ')}\n${k('onlynew')} ${yn(ev.views.onlyNew)} (only videos posted after the start)`,
		});
	}
	if (ev.voting) {
		fields.push({
			name: '🗳️ Voting',
			value: `${k('voting')} ${ev.voting.mode} (off / during / after)\n${k('votetime')} ${ev.voting.durationSpec} (only for "after")\n${k('selfvote')} ${yn(ev.voting.allowSelf)}`,
		});
	}
	const hint = ev.status === 'draft'
		? `Change a setting: \`/event set ${ev.id} <setting> <value>\` – e.g. \`/event set ${ev.id} end 10d\`\nThen press **🚀 Publish** (or type \`/event publish ${ev.id}\`).`
		: `Changes are applied to the live event right away: \`/event set ${ev.id} <setting> <value>\``;
	return {
		title: clip(`${t.emoji} Setup #${ev.id}: ${ev.title}`, 256),
		description: `**Type:** ${t.name}\n**Status:** ${STATUS[ev.status]}\n\n${hint}`,
		color: ev.color ?? t.color,
		fields: fields.map((f) => ({ ...f, value: clip(f.value, 1024) })),
		footer: { text: 'Clear a setting with "none" • /event help for all commands' },
	};
}

function panelButtons(ev) {
	const b = [btn(`ev:preview:${ev.id}`, 'Preview', 'secondary', '👁️')];
	if (ev.status === 'draft') b.push(btn(`ev:publish:${ev.id}`, 'Publish', 'success', '🚀'), btn(`ev:discard:${ev.id}`, 'Delete draft', 'danger', '🗑️'));
	else b.push(btn(`ev:panel:${ev.id}`, 'Refresh', 'secondary', '🔄'));
	return [row(...b)];
}

const panelPayload = async (ev, content = '') => ({ content, embeds: [await settingsEmbed(ev)], components: panelButtons(ev) });

// ---------- Server-Einstellungen ----------

async function configPayload(sid) {
	const cfg = store.guildConfig(sid);
	const staff = cfg.staffRoleIds.length
		? (await Promise.all(cfg.staffRoleIds.map((r) => perms.roleName(sid, r)))).join(', ')
		: 'not set – the server owner and roles that can manage the server can manage events (plus roles named Owner/Developer/Admin)';
	return {
		embeds: [{
			title: '⚙️ Event bot settings for this server',
			color: 0x5865f2,
			fields: [
				{ name: 'Staff roles – `/event config staff @Role @Role2` (or `none`)', value: staff },
				{ name: 'Default results channel – `/event config results #channel` (or `none`)', value: cfg.resultsChannelId ? await perms.channelName(sid, cfg.resultsChannelId) : 'the event channel' },
				{ name: 'Timezone – `/event config timezone Europe/Berlin`', value: cfg.timezone },
			],
		}],
	};
}

// ---------- Knopf-Listen mit Blättern (Voting, Gewinner wählen) ----------

function pager(items, page) {
	const pages = Math.max(1, Math.ceil(items.length / PAGE));
	const p = Math.min(Math.max(0, Number(page) || 0), pages - 1);
	return { p, pages, slice: items.slice(p * PAGE, (p + 1) * PAGE) };
}

// Voting: ein Knopf pro Eintrag, die aktuelle Stimme ist hervorgehoben
function votePayload(ev, voterId, page = 0, note = '') {
	const nums = entryNumbers(ev);
	const all = sortedEntries(ev).filter(([uid]) => ev.voting?.allowSelf || uid !== voterId);
	const { p, pages, slice } = pager(all, page);
	const current = ev.votes[voterId];
	const buttons = slice.map(([uid, e]) => btn(`ev:vp:${ev.id}:${uid}`, `#${nums.get(uid)} ${entryLabel(ev, uid, e)}`, uid === current ? 'success' : 'secondary', uid === current ? '✅' : null));
	const list = slice.map(([uid, e]) => `**#${nums.get(uid)}** ${formatEntry(ev, uid, e)}`).join('\n');
	const comps = rows(buttons);
	if (pages > 1) comps.push(row(btn(`ev:vpg:${ev.id}:${p - 1}`, 'Back', 'secondary', '◀️', p === 0), btn(`ev:vpg:${ev.id}:${p + 1}`, 'Next', 'secondary', '▶️', p >= pages - 1)));
	const head = note || `🗳️ Vote for your favourite entry in **${ev.title}**${pages > 1 ? ` (page ${p + 1}/${pages})` : ''}:`;
	return { content: clip(`${head}\n\n${list}`, 1990), components: comps };
}

// Gewinner wählen (Staff): Einträge antippen, dann bestätigen
function pickerPayload(ev, page = 0) {
	const order = ev.pick?.order ?? sortedEntries(ev).map(([u]) => ({ userId: u, text: null }));
	const items = order.filter((r) => ev.entries[r.userId]);
	const selected = ev.pick?.selected ?? [];
	const n = Math.min(ev.winnerCount, items.length);
	const { p, pages, slice } = pager(items, page);
	const nums = entryNumbers(ev);
	const buttons = slice.map((r) => {
		const on = selected.includes(r.userId);
		return btn(`ev:pw:${ev.id}:${r.userId}:${p}`, `#${nums.get(r.userId)} ${entryLabel(ev, r.userId, ev.entries[r.userId])}`, on ? 'success' : 'secondary', on ? '👑' : null);
	});
	const list = slice.map((r) => `**#${nums.get(r.userId)}** ${formatEntry(ev, r.userId, ev.entries[r.userId])}${r.text ? ` – ${r.text}` : ''}`).join('\n');
	const nav = [];
	if (pages > 1) nav.push(btn(`ev:pick:${ev.id}:${p - 1}`, 'Back', 'secondary', '◀️', p === 0), btn(`ev:pick:${ev.id}:${p + 1}`, 'Next', 'secondary', '▶️', p >= pages - 1));
	nav.push(btn(`ev:pwok:${ev.id}`, `Confirm ${selected.length}/${n}`, 'success', '🏆', selected.length === 0));
	const head = `👑 **Staff: pick ${n > 1 ? `${n} winners` : 'the winner'} of ${ev.title}** – tap the entries, then **Confirm**.${pages > 1 ? ` (page ${p + 1}/${pages})` : ''}\nOr type \`/event winner ${ev.id} <number> …\``;
	return { content: clip(`${head}\n\n${list}`, 1990), components: [...rows(buttons), row(...nav)] };
}

const HELP = [
	'**📅 Event bot – commands**',
	'',
	'**Everyone**',
	'`/event list` – all events of this server',
	'`/event join <id>` – join an event (same as the Join button)',
	'`/event leave <id>` – leave an event',
	'`/event participants <id>` – who joined',
	'`/event ranking <id>` – views or votes ranking',
	'`/event vote <id> <number>` – vote for an entry (number from the vote list)',
	'',
	'**Staff**',
	'`/event create <type>` – types: `views`, `submission`, `giveaway`, `signup`, `custom`',
	'`/event set <id> <setting> <value>` – change a setting (see `/event show <id>`)',
	'`/event question <id> add Question | type | required | example` – add a join question',
	'`/event question <id> edit <n> Question | type | required | example` • `remove <n>` • `clear`',
	`   types: ${Object.keys(FIELD_KINDS).join(', ')}`,
	'`/event show <id>` – settings overview • `/event preview <id>` • `/event publish <id>`',
	'`/event copy <id>` – copy an event into a new draft',
	'`/event end <id>` – end now • `/event cancel <id>` – cancel (drafts are deleted)',
	'`/event winner <id> <number or @user> …` – pick winner(s) • `/event reroll <id> [count]`',
	'`/event remove <id> <number or @user>` – remove a participant',
	'`/event export <id>` – all entries as CSV (sent to your DMs)',
	'`/event config` – staff roles, results channel, timezone',
].join('\n');

module.exports = { STATUS, eventPayload, eventEmbed, eventButtons, panelPayload, configPayload, votePayload, pickerPayload, votingOpen, count, btn, row, HELP };

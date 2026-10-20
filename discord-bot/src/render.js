// Nachrichten-Bausteine: Event-Nachricht, Setup-Menü, Server-Einstellungen
const {
	ActionRowBuilder,
	ButtonBuilder,
	ButtonStyle,
	ChannelSelectMenuBuilder,
	ChannelType,
	EmbedBuilder,
	RoleSelectMenuBuilder,
	StringSelectMenuBuilder,
} = require('discord.js');
const { TYPES, FIELD_KINDS, WINNER_MODES, winnerModesFor } = require('./types');
const { ts } = require('./time');
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

const count = (ev) => Object.keys(ev.entries).length;
const btn = (id, label, style = ButtonStyle.Secondary, emoji) => {
	const b = new ButtonBuilder().setCustomId(id).setLabel(label).setStyle(style);
	if (emoji) b.setEmoji(emoji);
	return b;
};
const row = (...c) => new ActionRowBuilder().addComponents(...c);

// Wie man mitmacht – automatisch je nach Typ
function howToJoin(ev) {
	const join = `**${ev.joinLabel}**`;
	const lines = [];
	if (ev.fields.length) lines.push(`Click ${join} and fill out the form.`);
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
	return lines.join('\n');
}

function eventEmbed(ev) {
	const t = TYPES[ev.type];
	const embed = new EmbedBuilder()
		.setColor(ev.color ?? t.color)
		.setTitle(`${t.emoji} ${ev.title}`)
		.setDescription(ev.description || '​')
		.setFooter({ text: `Event #${ev.id}` });
	if (ev.imageUrl) embed.setImage(ev.imageUrl);
	if (ev.startsAt) embed.setTimestamp(ev.startsAt);

	const n = count(ev);
	embed.addFields({ name: '👥 Participants', value: ev.maxParticipants ? `${n} / ${ev.maxParticipants}` : String(n), inline: true });
	if (ev.prize) embed.addFields({ name: '🎁 Prize', value: ev.prize, inline: true });
	if (ev.winnerMode !== 'none') embed.addFields({ name: '🏆 Winners', value: String(ev.winnerCount), inline: true });
	if (ev.requiredRoleId) embed.addFields({ name: '🔑 Required role', value: `<@&${ev.requiredRoleId}>`, inline: true });

	if (ev.status === 'scheduled' && ev.startsAt) embed.addFields({ name: '🕒 Starts', value: `${ts(ev.startsAt, 'F')} (${ts(ev.startsAt)})` });
	if (['scheduled', 'open', 'draft'].includes(ev.status) && ev.endsAt) embed.addFields({ name: '⏰ Ends', value: `${ts(ev.endsAt, 'F')} (${ts(ev.endsAt)})` });
	if (ev.status === 'voting' && ev.votingEndsAt) embed.addFields({ name: '🗳️ Voting ends', value: `${ts(ev.votingEndsAt, 'F')} (${ts(ev.votingEndsAt)})` });
	if (['scheduled', 'open', 'draft'].includes(ev.status)) embed.addFields({ name: '📝 How to join', value: howToJoin(ev) });
	if (['closed', 'finished', 'cancelled'].includes(ev.status)) embed.addFields({ name: 'Status', value: STATUS[ev.status] + (ev.closedAt ? ` ${ts(ev.closedAt)}` : '') });
	if (ev.winners.length) {
		embed.addFields({ name: ev.winners.length > 1 ? '🏆 Winners' : '🏆 Winner', value: ev.winners.map((w) => `<@${w}>`).join(', ').slice(0, 1024) });
	}
	return embed;
}

function eventButtons(ev) {
	const buttons = [];
	if (ev.status === 'open') {
		buttons.push(btn(`ev:join:${ev.id}`, ev.joinLabel.slice(0, 80), ButtonStyle.Success, '✅'));
		if (ev.allowLeave) buttons.push(btn(`ev:leave:${ev.id}`, 'Leave'));
	} else if (ev.status === 'scheduled') {
		buttons.push(btn(`ev:join:${ev.id}`, 'Starts soon', ButtonStyle.Secondary, '🕒').setDisabled(true));
	} else {
		buttons.push(btn(`ev:closed:${ev.id}`, ev.status === 'cancelled' ? 'Cancelled' : 'Closed', ButtonStyle.Secondary).setDisabled(true));
	}
	const votingOpen = (ev.status === 'open' && ev.voting?.mode === 'during') || ev.status === 'voting';
	if (votingOpen) buttons.push(btn(`ev:vote:${ev.id}`, 'Vote', ButtonStyle.Primary, '🗳️'));
	if (ev.type === 'views' && ['open', 'closed', 'finished'].includes(ev.status)) buttons.push(btn(`ev:lb:${ev.id}`, 'Ranking', ButtonStyle.Secondary, '📊'));
	if (ev.showParticipants && ev.status !== 'draft') buttons.push(btn(`ev:list:${ev.id}`, 'Participants', ButtonStyle.Secondary, '👥'));
	return [row(...buttons.slice(0, 5))];
}

// ---------- Setup-Menü ----------

function settingsEmbed(ev, guildId) {
	const t = TYPES[ev.type];
	const cfg = store.guildConfig(guildId);
	const yn = (b) => (b ? 'yes' : 'no');
	const e = new EmbedBuilder()
		.setColor(ev.color ?? t.color)
		.setTitle(`${t.emoji} Setup: ${ev.title}`)
		.setDescription(`**Type:** ${t.name}\n**Status:** ${STATUS[ev.status]}${ev.status === 'draft' ? '\nChange anything you like, then press **🚀 Publish**.' : '\nChanges are applied to the live event right away.'}`)
		.addFields(
			{ name: '📝 Text & look', value: `Description: ${ev.description ? `${ev.description.slice(0, 80)}${ev.description.length > 80 ? '…' : ''}` : '–'}\nPrize: ${ev.prize || '–'}\nImage: ${ev.imageUrl ? 'yes' : '–'} • Color: #${(ev.color ?? t.color).toString(16).padStart(6, '0')}`, inline: false },
			{ name: '⏰ Time & limits', value: `Start: ${ev.startsAt ? ts(ev.startsAt, 'f') : ev.startSpec || 'when published'}\nEnd: ${ev.endsAt ? ts(ev.endsAt, 'f') : ev.endSpec || '–'}\nMax participants: ${ev.maxParticipants ?? 'unlimited'}\nReminders: ${ev.reminders.length ? ev.reminders.map((h) => `${h}h`).join(', ') + ' before end' : 'off'}\nTimezone: ${cfg.timezone}`, inline: true },
			{ name: '📢 Channels & roles', value: `Event channel: ${ev.channelId ? `<#${ev.channelId}>` : 'this channel'}\nResults: ${ev.resultsChannelId ? `<#${ev.resultsChannelId}>` : cfg.resultsChannelId ? `<#${cfg.resultsChannelId}> (server default)` : 'event channel'}\nPing: ${ev.pingRoleId ? `<@&${ev.pingRoleId}>` : '–'}\nRequired role: ${ev.requiredRoleId ? `<@&${ev.requiredRoleId}>` : '–'}`, inline: true },
			{ name: '🧾 Join form', value: ev.fields.length ? ev.fields.map((f, i) => `${i + 1}. ${f.label} (${FIELD_KINDS[f.kind]}${f.required ? ', required' : ''}) → \`{${f.key}}\``).join('\n') : 'No questions – one click to join', inline: false },
			{ name: '🏆 Winners & results', value: `Mode: ${WINNER_MODES[ev.winnerMode].label}\nWinners: ${ev.winnerCount}\nList format: \`${ev.listFormat}\`\nJoin button: "${ev.joinLabel}"\nPublic participant list: ${yn(ev.showParticipants)} • Leaving allowed: ${yn(ev.allowLeave)}`, inline: false },
		);
	if (ev.type === 'views') {
		e.addFields({ name: '🎥 Video settings', value: `Hashtag: ${ev.views.hashtag ? `#${ev.views.hashtag}` : 'none (all videos count)'}\nPlatforms: ${ev.views.platforms.join(', ')}\nOnly videos after the start: ${yn(ev.views.onlyNew)}` });
	}
	if (ev.voting) {
		const m = { off: 'off', during: 'while the event is open', after: `after the deadline for ${ev.voting.durationSpec}` }[ev.voting.mode];
		e.addFields({ name: '🗳️ Voting', value: `Voting: ${m}\nVote for own entry: ${yn(ev.voting.allowSelf)}` });
	}
	return e;
}

function settingsComponents(ev, page = 'main') {
	const id = ev.id;
	const back = btn(`ev:pg:${id}:main`, 'Back', ButtonStyle.Secondary, '⬅️');
	if (page === 'channels') {
		const ch = new ChannelSelectMenuBuilder().setCustomId(`ev:set_chan:${id}`).setPlaceholder('📢 Event channel (where the event is posted)')
			.setChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement).setMinValues(0).setMaxValues(1);
		if (ev.channelId) ch.setDefaultChannels(ev.channelId);
		const res = new ChannelSelectMenuBuilder().setCustomId(`ev:set_res:${id}`).setPlaceholder('📊 Results channel (list + winner picker, e.g. staff channel)')
			.setChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement).setMinValues(0).setMaxValues(1);
		if (ev.resultsChannelId) res.setDefaultChannels(ev.resultsChannelId);
		const ping = new RoleSelectMenuBuilder().setCustomId(`ev:set_ping:${id}`).setPlaceholder('🔔 Role to ping when the event starts').setMinValues(0).setMaxValues(1);
		if (ev.pingRoleId) ping.setDefaultRoles(ev.pingRoleId);
		const req = new RoleSelectMenuBuilder().setCustomId(`ev:set_req:${id}`).setPlaceholder('🔑 Role needed to join (optional)').setMinValues(0).setMaxValues(1);
		if (ev.requiredRoleId) req.setDefaultRoles(ev.requiredRoleId);
		return [row(ch), row(res), row(ping), row(req), row(back)];
	}
	if (page === 'form') {
		const opts = ev.fields.map((f, i) => ({ label: `${i + 1}. ${f.label}`.slice(0, 100), description: `${FIELD_KINDS[f.kind]}${f.required ? ' • required' : ''} • {${f.key}}`.slice(0, 100), value: String(i) }));
		if (ev.fields.length < 5) opts.push({ label: '➕ Add a question', description: 'Up to 5 questions (Discord limit)', value: 'add' });
		const sel = new StringSelectMenuBuilder().setCustomId(`ev:q_pick:${id}`).setPlaceholder('Pick a question to edit or add a new one').addOptions(opts);
		const comps = [row(sel)];
		if (ev.fields.length && ev.status === 'draft') comps.push(row(btn(`ev:q_clear:${id}`, 'Remove all questions (one-click join)', ButtonStyle.Danger, '🧹')));
		comps.push(row(back));
		return comps;
	}
	if (page === 'winners') {
		const sel = new StringSelectMenuBuilder().setCustomId(`ev:set_wmode:${id}`).setPlaceholder('How are winners chosen?')
			.addOptions(winnerModesFor(ev.type).map((m) => ({ label: WINNER_MODES[m].label, description: WINNER_MODES[m].description, value: m, default: m === ev.winnerMode })));
		return [row(sel), row(btn(`ev:m_res:${id}`, 'Winners, list & buttons…', ButtonStyle.Primary, '✏️'), back)];
	}
	const typeBtn = ev.type === 'views'
		? btn(`ev:m_views:${id}`, 'Video settings', ButtonStyle.Secondary, '🎥')
		: ev.voting ? btn(`ev:m_vote:${id}`, 'Voting', ButtonStyle.Secondary, '🗳️') : null;
	const r2 = [btn(`ev:pg:${id}:channels`, 'Channels & roles', ButtonStyle.Secondary, '📢'), btn(`ev:pg:${id}:winners`, 'Winners & results', ButtonStyle.Secondary, '🏆')];
	if (typeBtn) r2.push(typeBtn);
	const r3 = [btn(`ev:preview:${id}`, 'Preview', ButtonStyle.Secondary, '👁️')];
	if (ev.status === 'draft') {
		r3.push(btn(`ev:publish:${id}`, 'Publish', ButtonStyle.Success, '🚀'), btn(`ev:discard:${id}`, 'Delete draft', ButtonStyle.Danger, '🗑️'));
	} else {
		r3.push(btn(`ev:done:${id}`, 'Done', ButtonStyle.Success, '✅'));
	}
	return [
		row(btn(`ev:m_text:${id}`, 'Text & look', ButtonStyle.Primary, '📝'), btn(`ev:m_time:${id}`, 'Time & limits', ButtonStyle.Primary, '⏰'), btn(`ev:pg:${id}:form`, 'Join form', ButtonStyle.Primary, '🧾')),
		row(...r2),
		row(...r3),
	];
}

const panel = (ev, guildId, page = 'main') => ({ embeds: [settingsEmbed(ev, guildId)], components: settingsComponents(ev, page) });

// ---------- Server-Einstellungen ----------

function configPanel(guildId) {
	const cfg = store.guildConfig(guildId);
	const embed = new EmbedBuilder()
		.setColor(0x5865f2)
		.setTitle('⚙️ Event bot settings for this server')
		.addFields(
			{ name: 'Staff roles', value: cfg.staffRoleIds.length ? cfg.staffRoleIds.map((r) => `<@&${r}>`).join(', ') : 'not set – server owner, admins and "Manage Server" can manage events (plus roles named Owner/Developer/Admin)' },
			{ name: 'Default results channel', value: cfg.resultsChannelId ? `<#${cfg.resultsChannelId}>` : 'the event channel' },
			{ name: 'Timezone (for dates like 2026-10-31 18:00)', value: cfg.timezone },
		);
	const roles = new RoleSelectMenuBuilder().setCustomId('ev:cfg_staff').setPlaceholder('👮 Staff roles that can manage events').setMinValues(0).setMaxValues(10);
	if (cfg.staffRoleIds.length) roles.setDefaultRoles(...cfg.staffRoleIds);
	const res = new ChannelSelectMenuBuilder().setCustomId('ev:cfg_res').setPlaceholder('📊 Default results channel').setChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement).setMinValues(0).setMaxValues(1);
	if (cfg.resultsChannelId) res.setDefaultChannels(cfg.resultsChannelId);
	return { embeds: [embed], components: [row(roles), row(res), row(btn('ev:cfg_tz', 'Set timezone', ButtonStyle.Secondary, '🌍'))] };
}

module.exports = { STATUS, eventEmbed, eventButtons, panel, configPanel, count };

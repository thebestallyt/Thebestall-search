// Weak Spot CC-Contest-Bot – Texte für Nutzer auf Englisch, Kommentare auf Deutsch
require('dotenv').config();
const {
	ActionRowBuilder,
	AttachmentBuilder,
	ButtonBuilder,
	ButtonStyle,
	Client,
	EmbedBuilder,
	Events,
	GatewayIntentBits,
	MessageFlags,
	ModalBuilder,
	StringSelectMenuBuilder,
	TextInputBuilder,
	TextInputStyle,
} = require('discord.js');
const store = require('./store');
const { isStaff, parseDuration, normalizeLink, sortedEntries, formatList, chunkText, ts } = require('./util');
const videos = require('./videos');

const GAME = 'Weak Spot (Roblox)';
const TAG = `#${videos.HASHTAG}`;
const CHECK_INTERVAL = 30_000; // so oft wird geprüft, ob ein Contest abgelaufen ist
const RESULTS_CACHE = 10 * 60_000; // Ergebnisse der Video-Prüfung 10 Minuten wiederverwenden
const MAX_VIDEOS = 10; // max. eingetragene Video-Links pro Teilnehmer
const COLORS = { open: 0x57f287, closed: 0xfee75c, finished: 0x5865f2 };
const NO_PERMISSION = '⛔ Only **Admins**, **Developers** and **Owners** can do that.';
const EPHEMERAL = { flags: MessageFlags.Ephemeral };
const QUIET = { flags: MessageFlags.SuppressEmbeds, allowedMentions: { parse: [] } };

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

// ---------- Nachrichten-Bausteine ----------

function contestEmbed(contest) {
	const count = Object.keys(contest.entries).length;
	const embed = new EmbedBuilder()
		.setColor(COLORS[contest.status])
		.setTitle(`🎬 ${contest.title}`)
		.setDescription(
			contest.description ||
				`Make a video about **${GAME}** with **${TAG}** and get as many views as you can!\nThe video with the most views wins.`,
		)
		.addFields(
			{ name: '🎮 Game', value: GAME, inline: true },
			{ name: '👥 Participants', value: String(count), inline: true },
		)
		.setFooter({ text: `Contest #${contest.id}` })
		.setTimestamp(contest.startedAt);

	if (contest.prize) embed.addFields({ name: '🎁 Prize', value: contest.prize, inline: true });

	if (contest.status === 'open') {
		embed.addFields(
			{ name: '⏰ Ends', value: `${ts(contest.endsAt, 'F')} (${ts(contest.endsAt)})` },
			{
				name: '📝 How to join',
				value:
					`1. Click **Join Contest** and enter your **channel name** and **YouTube or TikTok channel link**.\n` +
					`2. Upload your Weak Spot video with **${TAG}** in the title or description` +
					`${videos.ONLY_NEW_VIDEOS ? ' (only videos posted after the start count)' : ''}.\n` +
					(videos.YOUTUBE_AUTO
						? `3. YouTube videos are found automatically. **TikTok:** click **Join Contest** again and paste your video link.\n`
						: `3. Click **Join Contest** again and paste your video link(s).\n`) +
					`Check the views with \`/contest leaderboard\`.`,
			},
		);
	} else {
		embed.addFields({ name: '🔒 Status', value: `Closed ${ts(contest.closedAt ?? contest.endsAt)}` });
	}

	if (contest.winnerId) {
		const w = contest.entries[contest.winnerId];
		embed.addFields({
			name: '🏆 Winner',
			value: `<@${contest.winnerId}>${w ? ` – ${w.channelName} - ${w.channelLink}` : ''}`,
		});
	}
	return embed;
}

function contestButtons(contest) {
	if (contest.status !== 'open') {
		return [
			new ActionRowBuilder().addComponents(
				new ButtonBuilder()
					.setCustomId(`contest:closed:${contest.id}`)
					.setLabel(contest.status === 'finished' ? 'Contest finished' : 'Contest closed')
					.setStyle(ButtonStyle.Secondary)
					.setDisabled(true),
			),
		];
	}
	return [
		new ActionRowBuilder().addComponents(
			new ButtonBuilder()
				.setCustomId(`contest:join:${contest.id}`)
				.setLabel('Join Contest')
				.setEmoji('✅')
				.setStyle(ButtonStyle.Success),
			new ButtonBuilder()
				.setCustomId(`contest:leave:${contest.id}`)
				.setLabel('Leave')
				.setStyle(ButtonStyle.Secondary),
		),
	];
}

// Aktualisiert die Contest-Nachricht (Teilnehmerzahl, Status, Gewinner)
async function updateAnnouncement(contest) {
	try {
		const channel = await client.channels.fetch(contest.channelId);
		const message = await channel.messages.fetch(contest.messageId);
		await message.edit({ embeds: [contestEmbed(contest)], components: contestButtons(contest) });
	} catch (err) {
		console.warn(`Could not update message of contest #${contest.id}:`, err.message);
	}
}

// Liste als Text-Datei (praktisch zum Kopieren, auch bei sehr vielen Teilnehmern)
const listFile = (contest) =>
	new AttachmentBuilder(Buffer.from(formatList(contest) || '(no participants)', 'utf8'), {
		name: `contest-${contest.id}-participants.txt`,
	});

// Formular für Titel / Beschreibung / Preis (beim Starten und Bearbeiten)
function detailsModal(customId, heading, contest) {
	const title = new TextInputBuilder()
		.setCustomId('title')
		.setLabel('Title')
		.setPlaceholder('e.g. Weak Spot CC Contest #1')
		.setStyle(TextInputStyle.Short)
		.setMaxLength(100)
		.setRequired(true);
	const description = new TextInputBuilder()
		.setCustomId('description')
		.setLabel('Description / rules')
		.setPlaceholder(`e.g. Make a Weak Spot video with ${TAG}. The video with the most views wins! No botted views.`)
		.setStyle(TextInputStyle.Paragraph)
		.setMaxLength(3000)
		.setRequired(false);
	const prize = new TextInputBuilder()
		.setCustomId('prize')
		.setLabel('Prize (optional)')
		.setPlaceholder('e.g. 1000 Robux')
		.setStyle(TextInputStyle.Short)
		.setMaxLength(200)
		.setRequired(false);
	if (contest) {
		title.setValue(contest.title);
		if (contest.description) description.setValue(contest.description);
		if (contest.prize) prize.setValue(contest.prize);
	}
	return new ModalBuilder()
		.setCustomId(customId)
		.setTitle(heading)
		.addComponents([title, description, prize].map((input) => new ActionRowBuilder().addComponents(input)));
}

function readDetails(interaction) {
	const get = (id) => interaction.fields.getTextInputValue(id).trim() || null;
	return { title: get('title'), description: get('description'), prize: get('prize') };
}

// Sendet langen Text in mehreren Nachrichten (ohne Link-Vorschau)
async function sendChunks(channel, text, lastExtras = {}) {
	const chunks = chunkText(text);
	for (let i = 0; i < chunks.length; i++) {
		await channel.send({ content: chunks[i], ...QUIET, ...(i === chunks.length - 1 ? lastExtras : {}) });
	}
}

// ---------- Video-Prüfung ----------

const running = new Map();

// Prüft YouTube/TikTok (mit Cache, damit API-Kontingent geschont wird)
async function getResults(contest, force = false) {
	if (!force && contest.results && Date.now() - contest.results.checkedAt < RESULTS_CACHE) return contest.results;
	if (!running.has(contest.id)) {
		const job = videos
			.checkContest(contest)
			.then((results) => {
				contest.results = results;
				store.save();
				return results;
			})
			.finally(() => running.delete(contest.id));
		running.set(contest.id, job);
	}
	return running.get(contest.id);
}

// ---------- Contest beenden ----------

async function closeContest(contest) {
	if (contest.status !== 'open') return;
	contest.status = 'closed';
	contest.closedAt = Date.now();
	store.save();
	await updateAnnouncement(contest);

	const entries = sortedEntries(contest);
	let results = null;
	if (entries.length) {
		try {
			results = await getResults(contest, true);
		} catch (err) {
			console.warn(`Video check of contest #${contest.id} failed:`, err.message);
		}
	}

	try {
		const contestChannel = await client.channels.fetch(contest.channelId);
		const resultsChannel = process.env.RESULTS_CHANNEL_ID
			? await client.channels.fetch(process.env.RESULTS_CHANNEL_ID)
			: contestChannel;

		if (resultsChannel.id !== contestChannel.id) {
			await contestChannel.send(
				`🏁 **${contest.title}** has ended! Thanks to all **${entries.length}** participants – the winner will be announced soon.`,
			);
		}

		await resultsChannel.send({
			embeds: [
				new EmbedBuilder()
					.setColor(COLORS.closed)
					.setTitle(`🏁 ${contest.title} has ended!`)
					.setDescription(
						entries.length ? `**${entries.length}** participant(s) joined.` : 'Nobody joined this contest.',
					)
					.setFooter({ text: `Contest #${contest.id}` }),
			],
		});
		if (!entries.length) return;

		if (results) {
			await sendChunks(
				resultsChannel,
				`📊 **Views ranking** (${TAG} videos)\n\n${videos.formatRanking(results, { showNotes: true })}`,
			);
		} else {
			await resultsChannel.send('⚠️ The YouTube/TikTok check failed – please check the views manually.');
		}

		await sendChunks(resultsChannel, `📋 **Participants**\n\n${formatList(contest)}`, { files: [listFile(contest)] });

		// Gewinner-Auswahl, sortiert nach Aufrufen (Discord erlaubt max. 25 Optionen)
		const ranking = results?.ranking ?? entries.map(([userId, e]) => ({ userId, ...e, best: null }));
		if (ranking.length <= 25) {
			const select = new StringSelectMenuBuilder()
				.setCustomId(`contest:winner:${contest.id}`)
				.setPlaceholder('👑 Staff: pick the winner')
				.addOptions(
					ranking.map((r) => ({
						label: r.channelName.slice(0, 100),
						description: (r.best ? `${videos.fmt(r.best.views)} views` : `no ${TAG} video found`).slice(0, 100),
						value: r.userId,
					})),
				);
			await resultsChannel.send({
				content: 'Admins / Developers / Owners: choose the winner below (or use `/contest winner`).',
				components: [new ActionRowBuilder().addComponents(select)],
			});
		} else {
			await resultsChannel.send('Admins / Developers / Owners: use `/contest winner` to pick the winner.');
		}
	} catch (err) {
		console.warn(`Could not post results of contest #${contest.id}:`, err.message);
	}
}

async function checkExpired() {
	for (const contest of store.expiredContests()) {
		await closeContest(contest).catch((err) => console.error(err));
	}
}

// ---------- Gewinner ----------

async function setWinner(contest, userId) {
	contest.winnerId = userId;
	contest.status = 'finished';
	store.save();
	await updateAnnouncement(contest);

	const entry = contest.entries[userId];
	const best = contest.results?.ranking.find((r) => r.userId === userId)?.best;
	try {
		const channel = await client.channels.fetch(contest.channelId);
		await channel.send({
			embeds: [
				new EmbedBuilder()
					.setColor(0xf1c40f)
					.setTitle(`🏆 Winner of ${contest.title}`)
					.setDescription(
						`Congratulations <@${userId}>! 🎉\n\n**${entry.channelName}** - ${entry.channelLink}` +
							(best ? `\n🎥 ${best.url} – **${videos.fmt(best.views)} views**` : '') +
							(contest.prize ? `\n\n🎁 Prize: ${contest.prize}` : ''),
					)
					.setFooter({ text: `Contest #${contest.id}` }),
			],
			content: `<@${userId}>`,
			allowedMentions: { users: [userId] },
		});
	} catch (err) {
		console.warn(`Could not announce winner of contest #${contest.id}:`, err.message);
	}
}

// Prüft, ob ein Gewinner gewählt werden darf; gibt Fehlertext zurück oder null
function winnerError(contest, userId) {
	if (!contest) return '❌ There is no contest to pick a winner for.';
	if (contest.status === 'open') return '❌ This contest is still running. End it first with `/contest end`.';
	if (contest.status === 'finished') return `❌ The winner of **${contest.title}** was already picked.`;
	if (!contest.entries[userId]) return '❌ That user did not join this contest.';
	return null;
}

// ---------- Slash-Commands ----------

async function handleCommand(interaction) {
	const sub = interaction.options.getSubcommand();
	const guildId = interaction.guildId;
	const staff = isStaff(interaction);

	if (!['list', 'leaderboard'].includes(sub) && !staff) {
		return interaction.reply({ content: NO_PERMISSION, ...EPHEMERAL });
	}

	if (sub === 'start') {
		if (store.latestContest(guildId, ['open'])) {
			return interaction.reply({
				content: '❌ There is already a running contest. End it first with `/contest end`.',
				...EPHEMERAL,
			});
		}
		const durationText = interaction.options.getString('duration');
		const duration = parseDuration(durationText);
		if (!duration) {
			return interaction.reply({
				content: `❌ \`${durationText}\` is not a valid duration. Use e.g. \`10d\`, \`12h\`, \`1d12h\`, \`2w\` (1 minute – 365 days).`,
				...EPHEMERAL,
			});
		}
		const channel = interaction.options.getChannel('channel') ?? interaction.channel;
		const role = interaction.options.getRole('ping');
		// Optionen im customId merken, bis das Formular abgeschickt wird
		return interaction.showModal(
			detailsModal(`contest:create:${duration}:${channel.id}:${role?.id ?? 0}`, 'Start a new contest'),
		);
	}

	if (sub === 'edit') {
		const contest = store.latestContest(guildId, ['open', 'closed']);
		if (!contest) return interaction.reply({ content: '❌ There is no contest to edit.', ...EPHEMERAL });
		return interaction.showModal(detailsModal(`contest:edit:${contest.id}`, 'Edit contest', contest));
	}

	if (sub === 'list') {
		const contest =
			store.latestContest(guildId, ['open', 'closed']) ?? store.latestContest(guildId, ['finished']);
		if (!contest) return interaction.reply({ content: 'There is no contest yet.', ...EPHEMERAL });

		const count = Object.keys(contest.entries).length;
		const header = `**${contest.title}** – ${count} participant(s)${contest.status === 'open' ? `, ends ${ts(contest.endsAt)}` : ' (closed)'}`;
		if (!count) return interaction.reply({ content: `${header}\nNobody has joined yet.`, ...EPHEMERAL });

		const list = formatList(contest);
		const fits = header.length + list.length < 1900;
		return interaction.reply({
			content: fits ? `${header}\n\n${list}` : `${header}\nThe list is too long for one message, see the file:`,
			files: fits ? [] : [listFile(contest)],
			flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds,
		});
	}

	if (sub === 'leaderboard') {
		const contest =
			store.latestContest(guildId, ['open', 'closed']) ?? store.latestContest(guildId, ['finished']);
		if (!contest) return interaction.reply({ content: 'There is no contest yet.', ...EPHEMERAL });
		if (!Object.keys(contest.entries).length) {
			return interaction.reply({ content: `**${contest.title}** – nobody has joined yet.`, ...EPHEMERAL });
		}
		await interaction.deferReply(EPHEMERAL);
		// Nach Contest-Ende zählt das Endergebnis; vorher darf Staff neu prüfen lassen
		const force = staff && interaction.options.getBoolean('refresh') === true && contest.status === 'open';
		const results = contest.status === 'open' || !contest.results ? await getResults(contest, force) : contest.results;
		const text =
			`📊 **${contest.title}** – ${TAG} views ranking (checked ${ts(results.checkedAt)})\n\n` +
			videos.formatRanking(results, { showNotes: staff });
		const [first, ...rest] = chunkText(text);
		await interaction.editReply({ content: first, flags: MessageFlags.SuppressEmbeds });
		for (const chunk of rest) {
			await interaction.followUp({ content: chunk, flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds });
		}
		return;
	}

	if (sub === 'end') {
		const contest = store.latestContest(guildId, ['open']);
		if (!contest) return interaction.reply({ content: '❌ There is no running contest.', ...EPHEMERAL });
		await interaction.deferReply(EPHEMERAL);
		await closeContest(contest);
		return interaction.editReply(`✅ **${contest.title}** has been closed.`);
	}

	if (sub === 'winner') {
		const user = interaction.options.getUser('user');
		const contest =
			store.latestContest(guildId, ['closed']) ??
			store.latestContest(guildId, ['open']) ??
			store.latestContest(guildId, ['finished']);
		const error = winnerError(contest, user.id);
		if (error) return interaction.reply({ content: error, ...EPHEMERAL });
		await interaction.deferReply(EPHEMERAL);
		await setWinner(contest, user.id);
		return interaction.editReply(`🏆 ${user} is the winner of **${contest.title}**!`);
	}

	if (sub === 'remove') {
		const user = interaction.options.getUser('user');
		const contest = store.latestContest(guildId, ['open', 'closed']);
		if (!contest?.entries[user.id]) {
			return interaction.reply({ content: '❌ That user is not in the current contest.', ...EPHEMERAL });
		}
		delete contest.entries[user.id];
		if (contest.results) contest.results.ranking = contest.results.ranking.filter((r) => r.userId !== user.id);
		store.save();
		await updateAnnouncement(contest);
		return interaction.reply({ content: `✅ Removed ${user} from **${contest.title}**.`, ...EPHEMERAL });
	}
}

// ---------- Buttons, Formulare, Auswahl ----------

function joinModal(contest, existing) {
	const name = new TextInputBuilder()
		.setCustomId('channelName')
		.setLabel('Channel name')
		.setPlaceholder('e.g. Luxon Studios')
		.setStyle(TextInputStyle.Short)
		.setMinLength(2)
		.setMaxLength(80)
		.setRequired(true);
	const link = new TextInputBuilder()
		.setCustomId('channelLink')
		.setLabel('YouTube or TikTok channel link')
		.setPlaceholder('e.g. https://www.youtube.com/@LuxonStudios')
		.setStyle(TextInputStyle.Short)
		.setMaxLength(300)
		.setRequired(true);
	const videoLinks = new TextInputBuilder()
		.setCustomId('videos')
		.setLabel(`Your ${TAG} video links (one per line)`)
		.setPlaceholder(
			videos.YOUTUBE_AUTO
				? 'TikTok: required! YouTube: optional, your videos are found automatically.'
				: 'Required – paste the links of your videos here.',
		)
		.setStyle(TextInputStyle.Paragraph)
		.setMaxLength(2000)
		.setRequired(false);
	if (existing) {
		name.setValue(existing.channelName);
		link.setValue(existing.channelLink);
		if (existing.videos?.length) videoLinks.setValue(existing.videos.join('\n'));
	}
	return new ModalBuilder()
		.setCustomId(`contest:modal:${contest.id}`)
		.setTitle(`Join: ${contest.title}`.slice(0, 45))
		.addComponents([name, link, videoLinks].map((input) => new ActionRowBuilder().addComponents(input)));
}

async function handleJoinSubmit(interaction, contest) {
	const userId = interaction.user.id;
	const reject = (content) => interaction.reply({ content: `❌ ${content}`, ...EPHEMERAL });

	const channelName = interaction.fields.getTextInputValue('channelName').trim().replace(/\s+/g, ' ');
	const channelLink = normalizeLink(interaction.fields.getTextInputValue('channelLink'));
	if (channelName.length < 2) return reject('Please enter your channel name.');
	if (!channelLink) return reject('That is not a valid link. Example: `https://www.youtube.com/@LuxonStudios`');
	const linkError = videos.channelLinkError(channelLink);
	if (linkError) return reject(linkError);

	const videoLinks = [];
	for (const raw of interaction.fields.getTextInputValue('videos').split(/[\s,]+/).filter(Boolean)) {
		const link = normalizeLink(raw);
		const error = link ? videos.videoLinkError(link) : `\`${raw}\` is not a valid link.`;
		if (error) return reject(error);
		if (videos.platformOf(link) !== videos.platformOf(channelLink)) {
			return reject(`\`${link}\` is not on the same platform as your channel. Only videos from your channel count.`);
		}
		if (!videoLinks.includes(link)) videoLinks.push(link);
	}
	if (videoLinks.length > MAX_VIDEOS) return reject(`You can add at most ${MAX_VIDEOS} video links.`);

	const takenBy = Object.entries(contest.entries).find(
		([otherId, e]) => otherId !== userId && e.channelLink.toLowerCase() === channelLink.toLowerCase(),
	);
	if (takenBy) return reject('This channel link was already entered by someone else.');

	const existing = contest.entries[userId];
	contest.entries[userId] = {
		channelName,
		channelLink,
		videos: videoLinks,
		username: interaction.user.username,
		joinedAt: existing?.joinedAt ?? Date.now(),
		// aufgelöste YouTube-Kanal-ID behalten, solange der Link gleich bleibt
		...(existing?.channelLink === channelLink && existing.youtubeChannelId
			? { youtubeChannelId: existing.youtubeChannelId }
			: {}),
	};
	store.save();

	const needsLinks = videos.platformOf(channelLink) === 'tiktok' || !videos.YOUTUBE_AUTO;
	const linkHint =
		needsLinks && !videoLinks.length
			? `\n\n⚠️ Don't forget your video: click **Join Contest** again and paste your ${TAG} video link(s).`
			: '';
	await interaction.reply({
		content:
			(existing
				? `✏️ Your entry was updated:\n**${channelName}** - ${channelLink}`
				: `✅ You joined **${contest.title}**! Good luck! 🍀\n**${channelName}** - ${channelLink}\n\nThe contest ends ${ts(contest.endsAt)}. Don't forget **${TAG}** in your video!`) +
			(videoLinks.length ? `\n🎥 ${videoLinks.length} video link(s) saved.` : '') +
			linkHint,
		flags: MessageFlags.Ephemeral | MessageFlags.SuppressEmbeds,
	});
	return updateAnnouncement(contest);
}

async function handleCreateSubmit(interaction, [duration, channelId, roleId]) {
	if (!isStaff(interaction)) return interaction.reply({ content: NO_PERMISSION, ...EPHEMERAL });
	const guildId = interaction.guildId;
	if (store.latestContest(guildId, ['open'])) {
		return interaction.reply({ content: '❌ There is already a running contest.', ...EPHEMERAL });
	}
	await interaction.deferReply(EPHEMERAL);

	const now = Date.now();
	const contest = store.createContest({
		guildId,
		channelId,
		messageId: null,
		...readDetails(interaction),
		createdBy: interaction.user.id,
		startedAt: now,
		endsAt: now + Number(duration),
	});

	let mention = {};
	if (roleId !== '0') {
		mention =
			roleId === guildId
				? { content: '@everyone', allowedMentions: { parse: ['everyone'] } }
				: { content: `<@&${roleId}>`, allowedMentions: { roles: [roleId] } };
	}

	try {
		const channel = await client.channels.fetch(channelId);
		const message = await channel.send({
			...mention,
			embeds: [contestEmbed(contest)],
			components: contestButtons(contest),
		});
		contest.messageId = message.id;
		store.save();
	} catch (err) {
		store.deleteContest(contest.id);
		return interaction.editReply(
			`❌ I can't post in <#${channelId}>. Check my permissions (View Channel, Send Messages, Embed Links).`,
		);
	}
	return interaction.editReply(`✅ Contest **${contest.title}** started in <#${channelId}>! It ends ${ts(contest.endsAt)}.`);
}

async function handleComponent(interaction) {
	const [, action, ...args] = interaction.customId.split(':');
	if (action === 'create') return handleCreateSubmit(interaction, args);

	const contest = store.getContest(args[0]);
	if (!contest) return interaction.reply({ content: '❌ This contest no longer exists.', ...EPHEMERAL });

	const userId = interaction.user.id;
	const notOpen = { content: '🔒 This contest is closed. You can no longer join or leave.', ...EPHEMERAL };

	if (action === 'join') {
		if (contest.status !== 'open') return interaction.reply(notOpen);
		return interaction.showModal(joinModal(contest, contest.entries[userId]));
	}

	if (action === 'leave') {
		if (contest.status !== 'open') return interaction.reply(notOpen);
		if (!contest.entries[userId]) return interaction.reply({ content: "You haven't joined this contest.", ...EPHEMERAL });
		delete contest.entries[userId];
		store.save();
		await interaction.reply({ content: `👋 You left **${contest.title}**.`, ...EPHEMERAL });
		return updateAnnouncement(contest);
	}

	if (action === 'modal') {
		if (contest.status !== 'open') return interaction.reply(notOpen);
		return handleJoinSubmit(interaction, contest);
	}

	if (action === 'edit') {
		if (!isStaff(interaction)) return interaction.reply({ content: NO_PERMISSION, ...EPHEMERAL });
		Object.assign(contest, readDetails(interaction));
		store.save();
		await interaction.reply({ content: `✅ **${contest.title}** was updated.`, ...EPHEMERAL });
		return updateAnnouncement(contest);
	}

	if (action === 'winner') {
		if (!isStaff(interaction)) return interaction.reply({ content: NO_PERMISSION, ...EPHEMERAL });
		const winnerId = interaction.values[0];
		const error = winnerError(contest, winnerId);
		if (error) return interaction.reply({ content: error, ...EPHEMERAL });
		await interaction.update({
			content: `🏆 Winner picked by ${interaction.user}: <@${winnerId}>`,
			components: [],
			allowedMentions: { parse: [] },
		});
		return setWinner(contest, winnerId);
	}
}

// ---------- Start ----------

client.on(Events.InteractionCreate, async (interaction) => {
	try {
		if (interaction.isChatInputCommand() && interaction.commandName === 'contest') {
			await handleCommand(interaction);
		} else if (
			(interaction.isButton() || interaction.isModalSubmit() || interaction.isStringSelectMenu()) &&
			interaction.customId.startsWith('contest:')
		) {
			await handleComponent(interaction);
		}
	} catch (err) {
		console.error(err);
		const reply = { content: '⚠️ Something went wrong. Please try again.', ...EPHEMERAL };
		if (interaction.isRepliable()) {
			(interaction.deferred || interaction.replied ? interaction.followUp(reply) : interaction.reply(reply)).catch(
				() => {},
			);
		}
	}
});

client.once(Events.ClientReady, async (c) => {
	console.log(`Logged in as ${c.user.tag}`);
	if (!videos.YOUTUBE_AUTO) {
		console.log('No YOUTUBE_API_KEY – YouTube participants have to paste their video links (views are read from the page).');
	}
	await checkExpired();
	setInterval(checkExpired, CHECK_INTERVAL);
});

if (!process.env.DISCORD_TOKEN) {
	console.error('Please set DISCORD_TOKEN in .env (see .env.example)');
	process.exit(1);
}
client.login(process.env.DISCORD_TOKEN);

// Für Tests
module.exports = { client };

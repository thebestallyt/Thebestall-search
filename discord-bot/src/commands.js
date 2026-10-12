// Definition der Slash-Commands (/contest ...)
const { SlashCommandBuilder, ChannelType } = require('discord.js');

const STAFF = '(Admins / Developers / Owners only)';

const contest = new SlashCommandBuilder()
	.setName('contest')
	.setDescription('CC view contests for Weak Spot')
	.setDMPermission(false)
	.addSubcommand((sub) =>
		sub
			.setName('start')
			.setDescription(`Start a new contest – opens a form for title, description and prize ${STAFF}`)
			.addStringOption((o) =>
				o
					.setName('duration')
					.setDescription('How long the contest runs, e.g. 10d, 12h, 1d12h, 2w')
					.setRequired(true)
					.setMaxLength(20),
			)
			.addChannelOption((o) =>
				o
					.setName('channel')
					.setDescription('Channel to post the contest in (default: this channel)')
					.addChannelTypes(ChannelType.GuildText, ChannelType.GuildAnnouncement),
			)
			.addRoleOption((o) => o.setName('ping').setDescription('Role to ping when the contest starts')),
	)
	.addSubcommand((sub) =>
		sub.setName('edit').setDescription(`Edit title, description and prize of the current contest ${STAFF}`),
	)
	.addSubcommand((sub) => sub.setName('list').setDescription('Show everyone who joined the current contest'))
	.addSubcommand((sub) =>
		sub
			.setName('leaderboard')
			.setDescription('Check YouTube & TikTok: whose #weakspot video has the most views?')
			.addBooleanOption((o) =>
				o.setName('refresh').setDescription(`Check again now instead of using the last result ${STAFF}`),
			),
	)
	.addSubcommand((sub) => sub.setName('end').setDescription(`End the current contest now ${STAFF}`))
	.addSubcommand((sub) =>
		sub
			.setName('winner')
			.setDescription(`Pick the winner of the last contest ${STAFF}`)
			.addUserOption((o) => o.setName('user').setDescription('The winner (must have joined)').setRequired(true)),
	)
	.addSubcommand((sub) =>
		sub
			.setName('remove')
			.setDescription(`Remove someone from the current contest ${STAFF}`)
			.addUserOption((o) => o.setName('user').setDescription('Participant to remove').setRequired(true)),
	);

module.exports = [contest];

// Definition der Slash-Commands (/event ...)
const { SlashCommandBuilder } = require('discord.js');
const { TYPES } = require('./types');

const STAFF = '(Staff only)';
const eventOpt = (o, required = true) =>
	o.setName('event').setDescription('Which event (start typing to search)').setRequired(required).setAutocomplete(true);

const event = new SlashCommandBuilder()
	.setName('event')
	.setDescription('Create and run events, contests, giveaways and sign-ups')
	.setDMPermission(false)
	.addSubcommand((s) =>
		s.setName('create').setDescription(`Create a new event – opens a setup menu ${STAFF}`)
			.addStringOption((o) => o.setName('type').setDescription('What kind of event?').setRequired(true)
				.addChoices(...Object.entries(TYPES).map(([value, t]) => ({ name: `${t.emoji} ${t.name}`.slice(0, 100), value })))),
	)
	.addSubcommand((s) => s.setName('edit').setDescription(`Open the setup menu of an event ${STAFF}`).addStringOption((o) => eventOpt(o)))
	.addSubcommand((s) => s.setName('copy').setDescription(`Copy an event's settings into a new draft ${STAFF}`).addStringOption((o) => eventOpt(o)))
	.addSubcommand((s) => s.setName('list').setDescription('Show all events of this server'))
	.addSubcommand((s) => s.setName('participants').setDescription('Show who joined an event').addStringOption((o) => eventOpt(o)))
	.addSubcommand((s) =>
		s.setName('ranking').setDescription('Views or votes ranking of an event').addStringOption((o) => eventOpt(o))
			.addBooleanOption((o) => o.setName('refresh').setDescription(`Check videos again now ${STAFF}`)),
	)
	.addSubcommand((s) =>
		s.setName('vote').setDescription('Vote for an entry').addStringOption((o) => eventOpt(o))
			.addStringOption((o) => o.setName('entry').setDescription('The entry you vote for').setRequired(true).setAutocomplete(true)),
	)
	.addSubcommand((s) => s.setName('end').setDescription(`End an event now ${STAFF}`).addStringOption((o) => eventOpt(o)))
	.addSubcommand((s) => s.setName('cancel').setDescription(`Cancel an event without winners ${STAFF}`).addStringOption((o) => eventOpt(o)))
	.addSubcommand((s) =>
		s.setName('winner').setDescription(`Pick the winner(s) yourself ${STAFF}`).addStringOption((o) => eventOpt(o))
			.addUserOption((o) => o.setName('user').setDescription('Winner').setRequired(true))
			.addUserOption((o) => o.setName('user2').setDescription('2nd winner (optional)'))
			.addUserOption((o) => o.setName('user3').setDescription('3rd winner (optional)')),
	)
	.addSubcommand((s) =>
		s.setName('reroll').setDescription(`Draw new random winner(s) ${STAFF}`).addStringOption((o) => eventOpt(o))
			.addIntegerOption((o) => o.setName('count').setDescription('How many new winners').setMinValue(1).setMaxValue(25)),
	)
	.addSubcommand((s) =>
		s.setName('remove').setDescription(`Remove someone from an event ${STAFF}`).addStringOption((o) => eventOpt(o))
			.addUserOption((o) => o.setName('user').setDescription('Participant to remove').setRequired(true)),
	)
	.addSubcommand((s) => s.setName('export').setDescription(`Download all entries as a spreadsheet (CSV) ${STAFF}`).addStringOption((o) => eventOpt(o)))
	.addSubcommand((s) => s.setName('config').setDescription(`Server settings: staff roles, timezone, results channel ${STAFF}`));

module.exports = [event];

// Registriert die Slash-Commands bei Discord: npm run deploy
require('dotenv').config();
const { REST, Routes } = require('discord.js');
const commands = require('./commands');

const { DISCORD_TOKEN, CLIENT_ID, GUILD_ID } = process.env;
if (!DISCORD_TOKEN || !CLIENT_ID) {
	console.error('Please set DISCORD_TOKEN and CLIENT_ID in .env');
	process.exit(1);
}

const rest = new REST().setToken(DISCORD_TOKEN);
const body = commands.map((c) => c.toJSON());
const route = GUILD_ID ? Routes.applicationGuildCommands(CLIENT_ID, GUILD_ID) : Routes.applicationCommands(CLIENT_ID);

rest
	.put(route, { body })
	.then(() => console.log(`Registered ${body.length} command(s) ${GUILD_ID ? `in guild ${GUILD_ID}` : 'globally'}.`))
	.catch((err) => {
		console.error(err);
		process.exit(1);
	});

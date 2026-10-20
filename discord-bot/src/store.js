// JSON-Datenbank für Events und Server-Einstellungen (data/events.json)
const fs = require('node:fs');
const path = require('node:path');
const { eventFromTemplate } = require('./types');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DATA_FILE = path.join(DATA_DIR, 'events.json');
const OLD_FILE = path.join(DATA_DIR, 'contests.json');

let data = { nextId: 1, events: [], guilds: {} };

function save() {
	fs.mkdirSync(DATA_DIR, { recursive: true });
	// Erst in eine Temp-Datei schreiben, dann umbenennen -> keine kaputte Datei bei Absturz
	const tmp = `${DATA_FILE}.tmp`;
	fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
	fs.renameSync(tmp, DATA_FILE);
}

// Alte /contest-Daten (contests.json) ins neue Event-Format übernehmen
function migrateOld() {
	const old = JSON.parse(fs.readFileSync(OLD_FILE, 'utf8'));
	for (const c of old.contests ?? []) {
		const ev = eventFromTemplate('views');
		Object.assign(ev, {
			id: c.id,
			guildId: c.guildId,
			status: c.status,
			title: c.title,
			description: c.description,
			prize: c.prize,
			channelId: c.channelId,
			messageId: c.messageId,
			createdBy: c.createdBy,
			createdAt: c.startedAt,
			startsAt: c.startedAt,
			endsAt: c.endsAt,
			closedAt: c.closedAt,
			endSpec: '',
			winners: c.winnerId ? [c.winnerId] : [],
			results: c.results ?? null,
		});
		for (const [uid, e] of Object.entries(c.entries ?? {})) {
			ev.entries[uid] = {
				values: { name: e.channelName, link: e.channelLink, videos: e.videos ?? [] },
				username: e.username,
				joinedAt: e.joinedAt,
				youtubeChannelId: e.youtubeChannelId,
			};
		}
		data.events.push(ev);
	}
	data.nextId = Math.max(data.nextId, old.nextId ?? 1);
	fs.renameSync(OLD_FILE, `${OLD_FILE}.migrated`);
	save();
	console.log(`Migrated ${old.contests?.length ?? 0} old contest(s) to the new event format.`);
}

function load() {
	try {
		data = { nextId: 1, events: [], guilds: {}, ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) };
	} catch (err) {
		if (err.code !== 'ENOENT') throw err;
	}
	if (fs.existsSync(OLD_FILE)) migrateOld();
}

function createEvent(fields) {
	const ev = { id: data.nextId++, createdAt: Date.now(), ...fields };
	data.events.push(ev);
	save();
	return ev;
}

function deleteEvent(id) {
	data.events = data.events.filter((e) => e.id !== Number(id));
	save();
}

const getEvent = (id) => data.events.find((e) => e.id === Number(id)) ?? null;
const guildEvents = (guildId) => data.events.filter((e) => e.guildId === guildId);
const allEvents = () => data.events;

const GUILD_DEFAULTS = { staffRoleIds: [], timezone: process.env.TIMEZONE || 'Europe/Berlin', resultsChannelId: process.env.RESULTS_CHANNEL_ID || null };
function guildConfig(guildId) {
	data.guilds[guildId] = { ...GUILD_DEFAULTS, ...(data.guilds[guildId] ?? {}) };
	return data.guilds[guildId];
}

load();

module.exports = { save, createEvent, deleteEvent, getEvent, guildEvents, allEvents, guildConfig };

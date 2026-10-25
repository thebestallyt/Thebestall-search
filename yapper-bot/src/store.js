// JSON-Datenbank für Events und Server-Einstellungen (data/events.json) + Event-Zeiger (data/cursor.json)
const fs = require('node:fs');
const path = require('node:path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DATA_FILE = path.join(DATA_DIR, 'events.json');
const CURSOR_FILE = path.join(DATA_DIR, 'cursor.json');

let data = { nextId: 1, events: [], guilds: {} };

// Erst in eine Temp-Datei schreiben, dann umbenennen -> keine kaputte Datei bei Absturz
function writeJson(file, value) {
	fs.mkdirSync(DATA_DIR, { recursive: true });
	const tmp = `${file}.tmp`;
	fs.writeFileSync(tmp, JSON.stringify(value, null, 2));
	fs.renameSync(tmp, file);
}

const save = () => writeJson(DATA_FILE, data);

function load() {
	try {
		data = { nextId: 1, events: [], guilds: {}, ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) };
	} catch (err) {
		if (err.code !== 'ENOENT') throw err;
	}
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

// Zuletzt verarbeitetes Yapin'-Ereignis, damit nach einem Neustart nichts doppelt oder verloren geht.
// Eigene kleine Datei, die höchstens alle 2 s geschrieben wird (jede Chat-Nachricht ist ein Ereignis).
let cursor = null;
let cursorTimer = null;
try {
	cursor = JSON.parse(fs.readFileSync(CURSOR_FILE, 'utf8')).lastEventId ?? null;
} catch {
	cursor = null;
}
const getLastEventId = () => cursor;
function setLastEventId(id) {
	if (id === null || id === undefined || (cursor !== null && Number(id) <= Number(cursor))) return;
	cursor = id;
	cursorTimer ??= setTimeout(flushCursor, 2000);
}
function flushCursor() {
	clearTimeout(cursorTimer);
	cursorTimer = null;
	if (cursor !== null) writeJson(CURSOR_FILE, { lastEventId: cursor });
}

load();

module.exports = { save, createEvent, deleteEvent, getEvent, guildEvents, allEvents, guildConfig, getLastEventId, setLastEventId, flushCursor };

// Event-Bot für Yapin' – Texte für Nutzer auf Englisch, Kommentare auf Deutsch
const path = require('node:path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { api, ApiError } = require('./api');
const store = require('./store');
const videos = require('./videos');
const life = require('./lifecycle');
const join = require('./join');
const { onMessage, onInteraction } = require('./handlers');

const TICK = 20_000;
const REFRESH = 5 * 60_000;
const COMMANDS = [{ name: 'event', description: 'Events, contests, giveaways & sign-ups – type /event help' }];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let botId = null;

// Pro Nutzer der Reihe nach abarbeiten (wichtig für die Antworten in der DM), verschiedene Nutzer parallel
const queues = new Map();
function enqueue(key, fn) {
	const next = (queues.get(key) ?? Promise.resolve()).then(fn).catch((err) => console.error(err));
	queues.set(key, next);
	next.finally(() => {
		if (queues.get(key) === next) queues.delete(key);
	});
}

function dispatch(e) {
	const d = e.data ?? {};
	if (e.type === 'message') enqueue(d.author_id ?? 'x', () => onMessage(d, botId));
	else if (e.type === 'interaction') enqueue(d.user_id ?? 'x', () => onInteraction(d));
}

async function poll() {
	let after = store.getLastEventId();
	// Erster Start: alte Ereignisse (bis zu 1 Tag) überspringen, damit keine alten Befehle ausgeführt werden
	if (after === null) {
		const first = await api.events(undefined, 0);
		after = first.last ?? first.events?.at(-1)?.id ?? 0;
		store.setLastEventId(after);
	}
	let failures = 0;
	for (;;) {
		try {
			const page = await api.events(after, 25);
			failures = 0;
			for (const e of page.events ?? []) {
				if (after !== null && Number(e.id) <= Number(after)) continue;
				after = e.id;
				dispatch(e);
			}
			if (page.last != null && Number(page.last) > Number(after)) after = page.last;
			store.setLastEventId(after);
		} catch (err) {
			if (err instanceof ApiError && err.status === 401) {
				console.error('❌ The bot token was rejected (401). Check YAPPER_BOT_TOKEN in .env.');
				process.exit(1);
			}
			failures++;
			const wait = Math.min(30_000, 1000 * 2 ** failures);
			console.warn(`Event stream error (${err.message}) – retrying in ${Math.round(wait / 1000)}s`);
			await sleep(wait);
		}
	}
}

let ticking = false;
async function tick() {
	if (ticking) return;
	ticking = true;
	try {
		join.cleanup();
		await life.tick();
	} finally {
		ticking = false;
	}
}

async function main() {
	if (!process.env.YAPPER_BOT_TOKEN) {
		console.error('Please set YAPPER_BOT_TOKEN in .env (see .env.example)');
		process.exit(1);
	}
	const me = await api.me().catch((err) => {
		console.error(`❌ Could not log in: ${err.message}. Check YAPPER_BOT_TOKEN in .env.`);
		process.exit(1);
	});
	botId = me?.id ?? me?.user?.id ?? me?.bot?.id ?? null;
	console.log(`Logged in as ${me?.username ?? me?.bot_name ?? me?.bot?.username ?? 'bot'}`);
	await api.setCommands(COMMANDS).catch((err) => console.warn('Could not register the /event command:', err.message));
	if (!videos.YOUTUBE_AUTO) console.log('No YOUTUBE_API_KEY – YouTube participants have to paste their video links (views are read from the page).');

	// Nachrichten laufender Events auf den aktuellen Stand bringen (z. B. nach einem Update)
	await life.refreshMessages(true);
	await tick();
	setInterval(tick, TICK);
	setInterval(() => life.refreshMessages(false).catch((err) => console.warn(err.message)), REFRESH);
	await poll();
}

for (const sig of ['SIGINT', 'SIGTERM']) {
	process.on(sig, () => {
		store.flushCursor();
		process.exit(0);
	});
}

if (require.main === module) main();

module.exports = { main, dispatch, tick };

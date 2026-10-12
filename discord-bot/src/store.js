// Einfache JSON-Datenbank für Contests (data/contests.json)
const fs = require('node:fs');
const path = require('node:path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DATA_FILE = path.join(DATA_DIR, 'contests.json');

let data = { nextId: 1, contests: [] };

function load() {
	try {
		data = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
	} catch (err) {
		if (err.code !== 'ENOENT') throw err;
	}
}

function save() {
	fs.mkdirSync(DATA_DIR, { recursive: true });
	// Erst in eine Temp-Datei schreiben, dann umbenennen -> keine kaputte Datei bei Absturz
	const tmp = `${DATA_FILE}.tmp`;
	fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
	fs.renameSync(tmp, DATA_FILE);
}

function createContest(fields) {
	const contest = {
		id: data.nextId++,
		status: 'open', // open -> closed -> finished
		entries: {},
		winnerId: null,
		closedAt: null,
		...fields,
	};
	data.contests.push(contest);
	save();
	return contest;
}

function deleteContest(id) {
	data.contests = data.contests.filter((c) => c.id !== Number(id));
	save();
}

function getContest(id) {
	return data.contests.find((c) => c.id === Number(id)) ?? null;
}

// Neuester Contest einer Guild mit einem der Status
function latestContest(guildId, statuses) {
	for (let i = data.contests.length - 1; i >= 0; i--) {
		const c = data.contests[i];
		if (c.guildId === guildId && statuses.includes(c.status)) return c;
	}
	return null;
}

function expiredContests(now = Date.now()) {
	return data.contests.filter((c) => c.status === 'open' && c.endsAt <= now);
}

load();

module.exports = { save, createContest, deleteContest, getContest, latestContest, expiredContests };

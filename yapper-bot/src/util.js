// Hilfsfunktionen: Links, Listen-Format, Datum, Erwähnungen
const normalizeLink = (input) => {
	let text = String(input ?? '').trim().replace(/^<|>$/g, '');
	if (!text) return null;
	if (!/^https?:\/\//i.test(text)) text = `https://${text}`;
	try {
		const url = new URL(text);
		if (!url.hostname.includes('.')) return null;
		return url.toString();
	} catch {
		return null;
	}
};

const sortedEntries = (event) => Object.entries(event.entries).sort((a, b) => a[1].joinedAt - b[1].joinedAt);
const valueText = (v) => (Array.isArray(v) ? v.join(', ') : String(v ?? ''));

// Eine Zeile der Teilnehmerliste nach dem Format des Events, z. B. "{name} - {link}"
function formatEntry(event, userId, entry, { mention = false } = {}) {
	const line = event.listFormat.replace(/\{(\w+)\}/g, (m, key) => {
		if (key === 'user') return mention ? `<@${userId}>` : `@${entry.username}`;
		if (key === 'username') return entry.username;
		if (key in entry.values) return valueText(entry.values[key]);
		return m;
	});
	return line.trim() || `@${entry.username}`;
}

// Nummer jedes Eintrags (Reihenfolge des Beitritts) – für Voting, Gewinner und Entfernen
const entryNumbers = (event) => new Map(sortedEntries(event).map(([uid], i) => [uid, i + 1]));

const formatList = (event, opts) => sortedEntries(event).map(([uid, e]) => formatEntry(event, uid, e, opts)).join(',\n');

function entryLabel(event, userId, entry) {
	const f = event.fields.find((x) => ['text', 'number'].includes(x.kind) && entry.values[x.key]);
	return (f ? `${entry.values[f.key]}` : `@${entry.username}`).slice(0, 60);
}

function chunkText(text, max = 1900) {
	const chunks = [];
	let current = '';
	for (const line of text.split('\n')) {
		if (current && current.length + line.length + 1 > max) {
			chunks.push(current);
			current = '';
		}
		current += (current ? '\n' : '') + line.slice(0, max);
	}
	if (current) chunks.push(current);
	return chunks;
}

const yes = (s) => /^(y|yes|ja|j|true|1|on)$/i.test(String(s ?? '').trim());
const no = (s) => /^(n|no|nein|false|0|off)$/i.test(String(s ?? '').trim());

// Datum in der Zeitzone des Servers, z. B. "Sat, Oct 31, 18:00 (Europe/Berlin)"
function fmtDate(ms, timeZone) {
	const s = new Intl.DateTimeFormat('en-GB', { timeZone, weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(ms));
	return `${s} (${timeZone})`;
}

// "in 3 days", "in 5 hours", "2 hours ago"
function relative(ms, now = Date.now()) {
	const diff = ms - now;
	const abs = Math.abs(diff);
	const units = [['day', 86_400_000], ['hour', 3_600_000], ['minute', 60_000]];
	for (const [name, size] of units) {
		if (abs >= size || name === 'minute') {
			const n = Math.max(1, Math.round(abs / size));
			const t = `${n} ${name}${n === 1 ? '' : 's'}`;
			return diff >= 0 ? `in ${t}` : `${t} ago`;
		}
	}
	return '';
}

const when = (ms, tz) => `${fmtDate(ms, tz)} – ${relative(ms)}`;

// IDs aus Erwähnungen wie <@123>, <#123>, <@&123> oder reinen IDs
const mentionIds = (text, kind = 'user') => {
	const re = { user: /<@!?([\w-]+)>/g, channel: /<#([\w-]+)>/g, role: /<@&([\w-]+)>/g }[kind];
	return [...String(text ?? '').matchAll(re)].map((m) => m[1]);
};

module.exports = { normalizeLink, sortedEntries, entryNumbers, valueText, formatEntry, formatList, entryLabel, chunkText, yes, no, fmtDate, relative, when, mentionIds };

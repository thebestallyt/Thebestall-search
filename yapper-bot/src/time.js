// Zeitangaben: Dauer ("10d", "1d12h") oder Datum ("2026-10-31 18:00", "31.10.2026 18:00") in der Zeitzone des Servers
const UNITS = { w: 7 * 86_400_000, d: 86_400_000, h: 3_600_000, m: 60_000 };
const MAX_SPAN = 366 * UNITS.d;

function parseDuration(input) {
	const text = String(input ?? '').toLowerCase().replace(/\s+/g, '');
	if (!/^(\d+[wdhm])+$/.test(text)) return null;
	let ms = 0;
	for (const [, num, unit] of text.matchAll(/(\d+)([wdhm])/g)) ms += Number(num) * UNITS[unit];
	return ms >= UNITS.m && ms <= MAX_SPAN ? ms : null;
}

// Versatz der Zeitzone (ms) zu einem UTC-Zeitpunkt
function tzOffset(utcMs, timeZone) {
	const parts = Object.fromEntries(
		new Intl.DateTimeFormat('en-US', {
			timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
		}).formatToParts(new Date(utcMs)).map((p) => [p.type, p.value]),
	);
	const asUtc = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
	return asUtc - Math.floor(utcMs / 1000) * 1000;
}

function zonedToUtc(y, mo, d, h, mi, timeZone) {
	const guess = Date.UTC(y, mo - 1, d, h, mi);
	let result = guess - tzOffset(guess, timeZone);
	result = guess - tzOffset(result, timeZone); // Sommer-/Winterzeit korrekt
	return result;
}

function isValidTimeZone(tz) {
	try {
		new Intl.DateTimeFormat('en-US', { timeZone: tz });
		return true;
	} catch {
		return false;
	}
}

// Gibt { ms } (absoluter Zeitpunkt) oder { error } zurück; leer -> { ms: null }
function parseWhen(spec, baseMs, timeZone) {
	const text = String(spec ?? '').trim();
	if (!text) return { ms: null };
	const dur = parseDuration(text);
	if (dur) return { ms: baseMs + dur };
	let m = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?$/);
	let parts = m && [+m[1], +m[2], +m[3], +(m[4] ?? 0), +(m[5] ?? 0)];
	if (!m) {
		m = text.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$/);
		parts = m && [+m[3], +m[2], +m[1], +(m[4] ?? 0), +(m[5] ?? 0)];
	}
	if (!parts) return { error: `\`${text}\` is not a valid time. Use a duration like \`10d\`, \`12h\`, \`1d12h\` or a date like \`2026-10-31 18:00\`.` };
	const [y, mo, d, h, mi] = parts;
	if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return { error: `\`${text}\` is not a valid date.` };
	return { ms: zonedToUtc(y, mo, d, h, mi, timeZone) };
}

const ts = (ms, style = 'R') => `<t:${Math.floor(ms / 1000)}:${style}>`;

module.exports = { parseDuration, parseWhen, isValidTimeZone, ts, UNITS };

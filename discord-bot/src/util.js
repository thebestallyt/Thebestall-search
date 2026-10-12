// Hilfsfunktionen: Rechte, Dauer, Listen-Formatierung
const { PermissionFlagsBits } = require('discord.js');

const csv = (value) =>
	(value ?? '')
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean);

const STAFF_ROLE_NAMES = csv(process.env.STAFF_ROLE_NAMES || 'Owner,Developer,Admin').map((s) => s.toLowerCase());
const STAFF_ROLE_IDS = csv(process.env.STAFF_ROLE_IDS);

// Admin-Recht, Server-Besitzer oder eine der Staff-Rollen (Owner / Developer / Admin)
function isStaff(interaction) {
	if (!interaction.inGuild()) return false;
	if (interaction.guild?.ownerId === interaction.user.id) return true;
	if (interaction.memberPermissions?.has(PermissionFlagsBits.Administrator)) return true;

	const roles = interaction.member?.roles;
	const roleIds = Array.isArray(roles) ? roles : [...(roles?.cache?.keys() ?? [])];
	return roleIds.some((id) => {
		if (STAFF_ROLE_IDS.includes(id)) return true;
		const name = interaction.guild?.roles.cache.get(id)?.name?.toLowerCase();
		return name !== undefined && STAFF_ROLE_NAMES.includes(name);
	});
}

const UNITS = { w: 7 * 86_400_000, d: 86_400_000, h: 3_600_000, m: 60_000 };
const MAX_DURATION = 365 * UNITS.d;

// "10d", "1d12h", "30m", "2w" -> Millisekunden (null wenn ungültig)
function parseDuration(input) {
	const text = input.toLowerCase().replace(/\s+/g, '');
	if (!/^(\d+[wdhm])+$/.test(text)) return null;
	let ms = 0;
	for (const [, num, unit] of text.matchAll(/(\d+)([wdhm])/g)) ms += Number(num) * UNITS[unit];
	return ms >= UNITS.m && ms <= MAX_DURATION ? ms : null;
}

function normalizeLink(input) {
	let text = input.trim();
	if (!/^https?:\/\//i.test(text)) text = `https://${text}`;
	try {
		const url = new URL(text);
		if (!url.hostname.includes('.')) return null;
		return url.toString();
	} catch {
		return null;
	}
}

const sortedEntries = (contest) => Object.entries(contest.entries).sort((a, b) => a[1].joinedAt - b[1].joinedAt);

// "Luxon Studios - https://...," pro Zeile (letzte Zeile ohne Komma)
function formatList(contest) {
	const lines = sortedEntries(contest).map(([, e]) => `${e.channelName} - ${e.channelLink}`);
	return lines.join(',\n');
}

// Teilt einen Text in Stücke <= max Zeichen (an Zeilenumbrüchen)
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

const ts = (ms, style = 'R') => `<t:${Math.floor(ms / 1000)}:${style}>`;

module.exports = { isStaff, parseDuration, normalizeLink, sortedEntries, formatList, chunkText, ts };

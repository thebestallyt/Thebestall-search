// Hilfsfunktionen: Rechte, Links, Listen-Formatierung
const { PermissionFlagsBits } = require('discord.js');
const store = require('./store');

const csv = (value) =>
	(value ?? '')
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean);

// Fallback aus der .env, falls im Server noch keine Staff-Rollen eingestellt sind
const ENV_ROLE_NAMES = csv(process.env.STAFF_ROLE_NAMES || 'Owner,Developer,Admin').map((s) => s.toLowerCase());
const ENV_ROLE_IDS = csv(process.env.STAFF_ROLE_IDS);

// Server-Besitzer, Administrator-Recht, "Server verwalten" oder eine Staff-Rolle
function isStaff(interaction) {
	if (!interaction.inGuild()) return false;
	if (interaction.guild?.ownerId === interaction.user.id) return true;
	if (interaction.memberPermissions?.has(PermissionFlagsBits.Administrator)) return true;
	if (interaction.memberPermissions?.has(PermissionFlagsBits.ManageGuild)) return true;

	const cfg = store.guildConfig(interaction.guildId);
	const roles = interaction.member?.roles;
	const roleIds = Array.isArray(roles) ? roles : [...(roles?.cache?.keys() ?? [])];
	return roleIds.some((id) => {
		if (cfg.staffRoleIds.includes(id) || ENV_ROLE_IDS.includes(id)) return true;
		if (cfg.staffRoleIds.length) return false;
		const name = interaction.guild?.roles.cache.get(id)?.name?.toLowerCase();
		return name !== undefined && ENV_ROLE_NAMES.includes(name);
	});
}

function memberRoleIds(interaction) {
	const roles = interaction.member?.roles;
	return Array.isArray(roles) ? roles : [...(roles?.cache?.keys() ?? [])];
}

function normalizeLink(input) {
	let text = String(input ?? '').trim();
	if (!text) return null;
	if (!/^https?:\/\//i.test(text)) text = `https://${text}`;
	try {
		const url = new URL(text);
		if (!url.hostname.includes('.')) return null;
		return url.toString();
	} catch {
		return null;
	}
}

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

function formatList(event, opts) {
	return sortedEntries(event)
		.map(([uid, e]) => formatEntry(event, uid, e, opts))
		.join(',\n');
}

// Kurzer Name für Auswahlmenüs: erstes Textfeld oder Benutzername
function entryLabel(event, userId, entry) {
	const f = event.fields.find((x) => ['text', 'number'].includes(x.kind) && entry.values[x.key]);
	return (f ? `${entry.values[f.key]} (@${entry.username})` : `@${entry.username}`).slice(0, 100);
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

const yes = (s) => /^(y|yes|ja|j|true|1|on)$/i.test(String(s ?? '').trim());
const no = (s) => /^(n|no|nein|false|0|off)$/i.test(String(s ?? '').trim());

module.exports = { isStaff, memberRoleIds, normalizeLink, sortedEntries, formatEntry, formatList, entryLabel, chunkText, valueText, yes, no };

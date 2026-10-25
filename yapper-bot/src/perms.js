// Rechte: Wer ist Staff? Hat jemand eine Rolle? (mit kurzem Zwischenspeicher, um die API zu schonen)
const { api } = require('./api');
const store = require('./store');

const csv = (v) => (v ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const ENV_ROLE_NAMES = csv(process.env.STAFF_ROLE_NAMES || 'Owner,Developer,Admin').map((s) => s.toLowerCase());
const ENV_ROLE_IDS = csv(process.env.STAFF_ROLE_IDS);

const cache = new Map();
async function cached(key, ttl, load) {
	const hit = cache.get(key);
	if (hit && Date.now() - hit.at < ttl) return hit.value;
	const value = await load();
	cache.set(key, { at: Date.now(), value });
	return value;
}

const serverInfo = (sid) => cached(`server:${sid}`, 300_000, () => api.server(sid));
const serverRoles = (sid) => cached(`roles:${sid}`, 300_000, () => api.roles(sid));
const serverChannels = (sid) => cached(`channels:${sid}`, 120_000, () => api.channels(sid));
const memberRoles = (sid, uid) => cached(`member:${sid}:${uid}`, 60_000, async () => (await api.member(sid, uid))?.roles ?? []);

async function hasRole(sid, uid, roleId) {
	try {
		return (await memberRoles(sid, uid)).includes(roleId);
	} catch {
		return false;
	}
}

// Server-Besitzer, Rollen mit "Server verwalten", gewählte Staff-Rollen (oder Rollennamen aus der .env)
async function isStaff(sid, uid) {
	if (!sid || !uid) return false;
	try {
		const server = await serverInfo(sid);
		if (server?.owner_id === uid) return true;
		const [roles, mine] = await Promise.all([serverRoles(sid), memberRoles(sid, uid)]);
		const cfg = store.guildConfig(sid);
		return mine.some((rid) => {
			if (cfg.staffRoleIds.includes(rid) || ENV_ROLE_IDS.includes(rid)) return true;
			const role = roles.find((r) => r.id === rid);
			if (!role) return false;
			if (role.manage_server || role.perms?.manage_server || role.perms?.administrator) return true;
			return !cfg.staffRoleIds.length && ENV_ROLE_NAMES.includes(String(role.name).toLowerCase());
		});
	} catch (err) {
		console.warn('Staff check failed:', err.message);
		return false;
	}
}

// Kanal aus "<#id>", einer ID oder einem Namen ("#events" / "events")
async function resolveChannel(sid, text) {
	const raw = String(text ?? '').trim();
	const id = raw.match(/<#([\w-]+)>/)?.[1];
	const list = await serverChannels(sid).catch(() => []);
	if (id) return list.find((c) => c.id === id) ?? { id, name: id };
	const name = raw.replace(/^#/, '').toLowerCase();
	return list.find((c) => c.id === raw) ?? list.find((c) => String(c.name).toLowerCase() === name) ?? null;
}

// Rolle aus "<@&id>", einer ID oder einem Namen ("@VIP" / "VIP"); "everyone" erlaubt
async function resolveRole(sid, text) {
	const raw = String(text ?? '').trim();
	if (/^@?everyone$/i.test(raw)) return { id: 'everyone', name: 'everyone' };
	const id = raw.match(/<@&([\w-]+)>/)?.[1];
	const roles = await serverRoles(sid).catch(() => []);
	if (id) return roles.find((r) => r.id === id) ?? { id, name: id };
	const name = raw.replace(/^@/, '').toLowerCase();
	return roles.find((r) => r.id === raw) ?? roles.find((r) => String(r.name).toLowerCase() === name) ?? null;
}

const roleName = async (sid, rid) => {
	if (rid === 'everyone') return '@everyone';
	const r = (await serverRoles(sid).catch(() => [])).find((x) => x.id === rid);
	return r ? `@${r.name}` : rid;
};
const channelName = async (sid, cid) => {
	const c = (await serverChannels(sid).catch(() => [])).find((x) => x.id === cid);
	return c ? `#${c.name}` : `<#${cid}>`;
};

const clearCache = () => cache.clear();

module.exports = { isStaff, hasRole, resolveChannel, resolveRole, roleName, channelName, serverChannels, clearCache };

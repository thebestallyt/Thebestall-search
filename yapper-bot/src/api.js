// Verbindung zur Yapin'/Yapper Bot API (REST + Events per Long-Polling)
const BASE = (process.env.YAPPER_API_URL || 'https://www.yapper.website/api/bot/v1').replace(/\/$/, '');
const TOKEN = process.env.YAPPER_BOT_TOKEN;

class ApiError extends Error {
	constructor(status, message, body) {
		super(`${status} ${message}`);
		this.status = status;
		this.body = body;
	}
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const seg = (v) => encodeURIComponent(String(v));

async function request(method, path, { query, body, timeout = 40_000, retries = 3 } = {}) {
	let url = BASE + path;
	if (query) {
		const qs = new URLSearchParams(Object.entries(query).filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => [k, String(v)]));
		if ([...qs].length) url += `?${qs}`;
	}
	for (let attempt = 0; ; attempt++) {
		let res;
		try {
			res = await fetch(url, {
				method,
				headers: { Authorization: `Bot ${TOKEN}`, 'User-Agent': 'yapin-event-bot/1.0', ...(body ? { 'Content-Type': 'application/json' } : {}) },
				body: body ? JSON.stringify(body) : undefined,
				signal: AbortSignal.timeout(timeout),
			});
		} catch (err) {
			if (attempt < retries) { await sleep(1000 * (attempt + 1)); continue; }
			throw new ApiError(0, `network error: ${err.message}`);
		}
		// Rate-Limit / Wartung: warten und nochmal
		if ((res.status === 429 || res.status === 503) && attempt < retries) {
			const wait = Number(res.headers.get('retry-after'));
			await sleep(Number.isFinite(wait) && wait > 0 ? Math.min(wait, 30) * 1000 : 2000 * (attempt + 1));
			continue;
		}
		const text = await res.text();
		let data = null;
		try {
			data = text ? JSON.parse(text) : {};
		} catch {
			data = { raw: text };
		}
		if (!res.ok) throw new ApiError(res.status, data?.error?.message ?? data?.message ?? data?.error ?? res.statusText, data);
		return data;
	}
}

const api = {
	me: () => request('GET', '/me'),
	setCommands: (commands) => request('PUT', '/commands', { body: { commands } }),
	events: (after, wait = 25) => request('GET', '/events', { query: { after, wait }, timeout: (wait + 15) * 1000, retries: 1 }),
	server: async (id) => (await request('GET', `/servers/${seg(id)}`)).server ?? null,
	roles: async (id) => (await request('GET', `/servers/${seg(id)}/roles`)).roles ?? [],
	member: async (sid, uid) => (await request('GET', `/servers/${seg(sid)}/members/${seg(uid)}`)).member ?? null,
	channels: async (sid) => (await request('GET', `/servers/${seg(sid)}/channels`, { query: { type: 'text' } })).channels ?? [],
	channel: async (cid) => (await request('GET', `/channels/${seg(cid)}`)).channel ?? null,
	send: async (cid, payload) => (await request('POST', `/channels/${seg(cid)}/messages`, { body: payload })).message,
	edit: async (cid, mid, payload) => (await request('PATCH', `/channels/${seg(cid)}/messages/${seg(mid)}`, { body: payload })).message,
	callback: (iid, token, type, payload = {}) => request('POST', `/interactions/${seg(iid)}/${seg(token)}/callback`, { body: { type, ...payload }, retries: 1 }),
	openDm: async (uid) => (await request('POST', `/users/${seg(uid)}/dm`)).channel_id,
	user: async (uid) => (await request('GET', `/users/${seg(uid)}`)).user ?? null,
};

module.exports = { api, ApiError, request };

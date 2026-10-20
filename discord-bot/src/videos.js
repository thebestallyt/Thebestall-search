// Prüft die Videos der Teilnehmer auf YouTube und TikTok (#weakspot, Aufrufe)
const YT_KEY = process.env.YOUTUBE_API_KEY;
const UA =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

// ---------- Links erkennen ----------

function platformOf(link) {
	try {
		const host = new URL(link).hostname.replace(/^(www|m|music)\./, '');
		if (host === 'youtube.com' || host === 'youtu.be') return 'youtube';
		if (host === 'tiktok.com' || host.endsWith('.tiktok.com')) return 'tiktok';
	} catch {}
	return null;
}

// YouTube-Kanal-Link -> { handle } | { id } | { username } | { custom } | null
function parseYouTubeChannel(link) {
	const url = new URL(link);
	if (url.hostname === 'youtu.be') return null;
	const [first, second] = url.pathname.split('/').filter(Boolean);
	if (first?.startsWith('@')) return { handle: decodeURIComponent(first) };
	if (first === 'channel' && /^UC[\w-]{22}$/.test(second ?? '')) return { id: second };
	if (first === 'user' && second) return { username: second };
	if (first === 'c' && second) return { custom: decodeURIComponent(second) };
	return null;
}

function parseYouTubeVideoId(link) {
	const url = new URL(link);
	if (url.hostname === 'youtu.be') return url.pathname.slice(1).split('/')[0] || null;
	if (url.searchParams.get('v')) return url.searchParams.get('v');
	const m = url.pathname.match(/^\/(shorts|live|embed)\/([\w-]{11})/);
	return m ? m[2] : null;
}

function parseTikTokHandle(link) {
	const m = new URL(link).pathname.match(/^\/@([\w.]+)/);
	return m ? m[1].toLowerCase() : null;
}

function isTikTokVideoLink(link) {
	const url = new URL(link);
	return (
		/\/video\/\d+/.test(url.pathname) ||
		/^(vm|vt)\.tiktok\.com$/.test(url.hostname) ||
		/^\/t\/\w+/.test(url.pathname)
	);
}

// Prüft einen Kanal-Link; gibt Fehlertext zurück oder null
function channelLinkError(link) {
	const platform = platformOf(link);
	if (!platform) return 'Only **YouTube** and **TikTok** channels are allowed.';
	if (platform === 'youtube' && !parseYouTubeChannel(link)) {
		return 'Please use your YouTube **channel** link, e.g. `https://www.youtube.com/@LuxonStudios`.';
	}
	if (platform === 'tiktok' && !parseTikTokHandle(link)) {
		return 'Please use your TikTok **profile** link, e.g. `https://www.tiktok.com/@luxonstudios`.';
	}
	return null;
}

// Prüft einen Video-Link; gibt Fehlertext zurück oder null
function videoLinkError(link) {
	const platform = platformOf(link);
	if (platform === 'youtube' && parseYouTubeVideoId(link)) return null;
	if (platform === 'tiktok' && isTikTokVideoLink(link)) return null;
	return `\`${link}\` is not a YouTube or TikTok video link.`;
}

// Leerer Hashtag = jedes Video zählt
function hasHashtag(text = '', tags = [], hashtag = '') {
	const tag = String(hashtag).replace(/^#/, '').toLowerCase();
	if (!tag) return true;
	const esc = tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const re = new RegExp(`#${esc}(?![\\p{L}\\p{N}_])`, 'iu');
	return re.test(text) || tags.some((t) => t.replace(/^#/, '').toLowerCase() === tag);
}

// ---------- YouTube (Data API v3) ----------

async function youtube(endpoint, params) {
	const url = new URL(`https://www.googleapis.com/youtube/v3/${endpoint}`);
	for (const [k, v] of Object.entries({ ...params, key: YT_KEY })) url.searchParams.set(k, v);
	const res = await fetch(url, { signal: AbortSignal.timeout(15_000) });
	const json = await res.json();
	if (!res.ok) throw new Error(`YouTube API: ${json.error?.message ?? res.status}`);
	return json;
}

async function resolveYouTubeChannelId(link) {
	const ref = parseYouTubeChannel(link);
	if (!ref) return null;
	if (ref.id) return ref.id;
	if (ref.handle || ref.username) {
		const json = await youtube('channels', {
			part: 'id',
			...(ref.handle ? { forHandle: ref.handle } : { forUsername: ref.username }),
		});
		if (json.items?.[0]) return json.items[0].id;
	}
	// Fallback für alte /c/-Links (Suche kostet mehr API-Kontingent)
	const json = await youtube('search', {
		part: 'snippet',
		type: 'channel',
		maxResults: 1,
		q: ref.custom ?? ref.handle ?? ref.username,
	});
	return json.items?.[0]?.snippet?.channelId ?? null;
}

// Video-IDs der neuesten Uploads eines Kanals (seit `since`)
async function youtubeUploads(channelId, since, onlyNew = true) {
	const playlistId = `UU${channelId.slice(2)}`;
	const ids = [];
	let pageToken;
	for (let page = 0; page < 4; page++) {
		const json = await youtube('playlistItems', {
			part: 'contentDetails',
			playlistId,
			maxResults: 50,
			...(pageToken ? { pageToken } : {}),
		});
		let reachedOld = false;
		for (const item of json.items ?? []) {
			const published = Date.parse(item.contentDetails.videoPublishedAt ?? 0);
			if (onlyNew && published < since) {
				reachedOld = true;
				continue;
			}
			ids.push(item.contentDetails.videoId);
		}
		pageToken = json.nextPageToken;
		if (!pageToken || reachedOld) break;
	}
	return ids;
}

async function youtubeVideos(ids) {
	const videos = [];
	for (let i = 0; i < ids.length; i += 50) {
		const json = await youtube('videos', { part: 'snippet,statistics', id: ids.slice(i, i + 50).join(',') });
		for (const v of json.items ?? []) {
			videos.push({
				platform: 'youtube',
				id: v.id,
				url: `https://youtu.be/${v.id}`,
				title: v.snippet.title,
				views: Number(v.statistics.viewCount ?? 0),
				publishedAt: Date.parse(v.snippet.publishedAt),
				channelId: v.snippet.channelId,
				hashText: `${v.snippet.title}\n${v.snippet.description}`,
				hashTags: v.snippet.tags ?? [],
			});
		}
	}
	return videos;
}

// ---------- TikTok (öffentliche Video-Seite) ----------

function readJsonScript(html, id) {
	const m = html.match(new RegExp(`<script[^>]*id="${id}"[^>]*>([\\s\\S]*?)</script>`));
	if (!m) return null;
	try {
		return JSON.parse(m[1]);
	} catch {
		return null;
	}
}

// Liest die Video-Daten aus dem HTML einer TikTok-Videoseite
function parseTikTokPage(html) {
	const universal = readJsonScript(html, '__UNIVERSAL_DATA_FOR_REHYDRATION__');
	let item = universal?.__DEFAULT_SCOPE__?.['webapp.video-detail']?.itemInfo?.itemStruct;
	if (!item) {
		const sigi = readJsonScript(html, 'SIGI_STATE');
		item = sigi?.ItemModule ? Object.values(sigi.ItemModule)[0] : null;
	}
	if (!item?.id) return null;

	const author = (typeof item.author === 'string' ? item.author : item.author?.uniqueId ?? '').toLowerCase();
	const tags = [
		...(item.textExtra ?? []).map((t) => t.hashtagName ?? ''),
		...(item.challenges ?? []).map((c) => c.title ?? ''),
	].filter(Boolean);
	return {
		platform: 'tiktok',
		id: String(item.id),
		url: `https://www.tiktok.com/@${author}/video/${item.id}`,
		title: (item.desc ?? '').slice(0, 100),
		views: Number(item.statsV2?.playCount ?? item.stats?.playCount ?? 0),
		publishedAt: Number(item.createTime) * 1000,
		author,
		hashText: item.desc ?? '',
		hashTags: tags,
	};
}

async function tiktokVideo(link) {
	const res = await fetch(link, {
		headers: { 'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9' },
		redirect: 'follow',
		signal: AbortSignal.timeout(15_000),
	});
	if (!res.ok) throw new Error(`TikTok answered ${res.status}`);
	const video = parseTikTokPage(await res.text());
	if (!video) throw new Error('TikTok did not return the video data (maybe blocked or private)');
	return video;
}

// ---------- YouTube ohne API-Key (öffentliche Seiten) ----------

// Schneidet ein JSON-Objekt nach `marker` aus dem HTML (zählt Klammern, beachtet Strings)
function extractJsonAfter(html, marker) {
	const at = html.indexOf(marker);
	if (at === -1) return null;
	const start = html.indexOf('{', at + marker.length);
	if (start === -1) return null;
	let depth = 0;
	let inString = false;
	for (let i = start; i < html.length; i++) {
		const ch = html[i];
		if (inString) {
			if (ch === '\\') i++;
			else if (ch === '"') inString = false;
		} else if (ch === '"') inString = true;
		else if (ch === '{') depth++;
		else if (ch === '}' && --depth === 0) {
			try {
				return JSON.parse(html.slice(start, i + 1));
			} catch {
				return null;
			}
		}
	}
	return null;
}

async function fetchYouTubePage(url) {
	const res = await fetch(url, {
		// Cookies überspringen die EU-Zustimmungsseite
		headers: { 'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9', Cookie: 'SOCS=CAI; CONSENT=YES+1' },
		redirect: 'follow',
		signal: AbortSignal.timeout(15_000),
	});
	if (!res.ok) throw new Error(`YouTube answered ${res.status}`);
	return res.text();
}

// Liest die Video-Daten aus dem HTML einer YouTube-Videoseite
function parseYouTubePage(html) {
	const player = extractJsonAfter(html, 'ytInitialPlayerResponse');
	const details = player?.videoDetails;
	if (!details?.videoId) return null;
	const micro = player.microformat?.playerMicroformatRenderer ?? {};
	return {
		platform: 'youtube',
		id: details.videoId,
		url: `https://youtu.be/${details.videoId}`,
		title: details.title ?? '',
		views: Number(details.viewCount ?? micro.viewCount ?? 0),
		publishedAt: Date.parse(micro.publishDate ?? micro.uploadDate ?? ''),
		channelId: details.channelId,
		hashText: `${details.title ?? ''}\n${details.shortDescription ?? ''}`,
		hashTags: details.keywords ?? [],
	};
}

// Kanal-ID aus der Kanalseite lesen (für Links wie youtube.com/@name)
function parseYouTubeChannelPage(html) {
	const m =
		html.match(/"externalId":"(UC[\w-]{22})"/) ??
		html.match(/<link rel="canonical" href="https:\/\/www\.youtube\.com\/channel\/(UC[\w-]{22})"/) ??
		html.match(/<meta itemprop="identifier" content="(UC[\w-]{22})"/);
	return m ? m[1] : null;
}

async function youtubeVideoFromPage(link) {
	const id = parseYouTubeVideoId(link);
	const video = parseYouTubePage(await fetchYouTubePage(`https://www.youtube.com/watch?v=${id}`));
	if (!video) throw new Error('YouTube did not return the video data (maybe private or blocked)');
	return video;
}

async function youtubeChannelIdFromPage(link) {
	const ref = parseYouTubeChannel(link);
	if (ref?.id) return ref.id;
	return parseYouTubeChannelPage(await fetchYouTubePage(`https://www.youtube.com${new URL(link).pathname}`));
}

// ---------- Contest prüfen ----------

const fmt = (n) => n.toLocaleString('en-US');

// Prüft alle Teilnehmer eines Video-Events und gibt die Rangliste zurück (meiste Aufrufe zuerst)
async function checkEvent(event) {
	const opts = event.views ?? {};
	const hashtag = opts.hashtag ?? '';
	const onlyNew = opts.onlyNew !== false;
	const allowed = opts.platforms?.length ? opts.platforms : ['youtube', 'tiktok'];
	const keyOf = (kind) => event.fields.find((f) => f.kind === kind)?.key;
	const channelKey = keyOf('channel');
	const videosKey = keyOf('videos');
	const nameKey = keyOf('text');
	const since = event.startsAt ?? event.createdAt;

	const ranking = [];
	for (const [userId, entry] of Object.entries(event.entries)) {
		const channelLink = channelKey ? entry.values[channelKey] : null;
		const videoLinks = videosKey ? [].concat(entry.values[videosKey] ?? []) : [];
		const platform = channelLink ? platformOf(channelLink) : null;
		const notes = [];
		const found = new Map();
		const add = (v) => found.set(`${v.platform}:${v.id}`, v);

		try {
			if (!platform) {
				notes.push('no YouTube/TikTok channel link');
			} else if (!allowed.includes(platform)) {
				notes.push(`${platform} is not allowed in this event`);
			} else if (platform === 'youtube' && !YT_KEY) {
				// Ohne API-Key: nur eingetragene Video-Links, Aufrufe von der Videoseite
				const links = videoLinks.filter((l) => platformOf(l) === 'youtube');
				if (!links.length) notes.push('no YouTube video link submitted');
				if (links.length) {
					entry.youtubeChannelId ??= await youtubeChannelIdFromPage(channelLink);
					if (!entry.youtubeChannelId) throw new Error('YouTube channel not found');
				}
				for (const link of links) {
					try {
						const v = await youtubeVideoFromPage(link);
						if (v.channelId !== entry.youtubeChannelId) notes.push(`${v.url} is not from this channel`);
						else add(v);
					} catch (err) {
						notes.push(`could not read ${link}: ${err.message}`);
					}
				}
			} else if (platform === 'youtube') {
				entry.youtubeChannelId ??= await resolveYouTubeChannelId(channelLink);
				if (!entry.youtubeChannelId) throw new Error('YouTube channel not found');
				// Uploads automatisch + selbst eingetragene Videos
				const ids = new Set(await youtubeUploads(entry.youtubeChannelId, since, onlyNew));
				for (const link of videoLinks) {
					if (platformOf(link) === 'youtube') ids.add(parseYouTubeVideoId(link));
					else notes.push('TikTok video ignored (channel is YouTube)');
				}
				for (const v of await youtubeVideos([...ids])) {
					if (v.channelId !== entry.youtubeChannelId) notes.push(`${v.url} is not from this channel`);
					else add(v);
				}
			} else if (platform === 'tiktok') {
				const handle = parseTikTokHandle(channelLink);
				const links = videoLinks.filter((l) => platformOf(l) === 'tiktok');
				if (!links.length) notes.push('no TikTok video link submitted');
				for (const link of links) {
					try {
						const v = await tiktokVideo(link);
						if (v.author !== handle) notes.push(`${v.url} is not from @${handle}`);
						else add(v);
					} catch (err) {
						notes.push(`could not read ${link}: ${err.message}`);
					}
				}
			}
		} catch (err) {
			notes.push(err.message);
		}

		const valid = [...found.values()].filter(
			(v) => hasHashtag(v.hashText, v.hashTags, hashtag) && (!onlyNew || v.publishedAt >= since),
		);
		valid.sort((a, b) => b.views - a.views);
		ranking.push({
			userId,
			channelName: (nameKey && entry.values[nameKey]) || `@${entry.username}`,
			channelLink,
			best: valid[0] ?? null,
			videoCount: valid.length,
			notes,
		});
	}
	ranking.sort((a, b) => (b.best?.views ?? -1) - (a.best?.views ?? -1));
	return { checkedAt: Date.now(), ranking };
}

// Rangliste als Text: "🥇 Luxon Studios - 120,345 views - https://..."
function formatRanking(results, { showNotes = false, hashtag = '' } = {}) {
	const what = hashtag ? `#${hashtag.replace(/^#/, '')} video` : 'video';
	const medals = ['🥇', '🥈', '🥉'];
	let place = 0;
	return results.ranking
		.map((r) => {
			if (!r.best) {
				const why = showNotes && r.notes.length ? ` (${r.notes.join('; ')})` : '';
				return `➖ ${r.channelName} - no ${what} found${why}`;
			}
			const rank = medals[place] ?? `**${place + 1}.**`;
			place++;
			const more = r.videoCount > 1 ? ` (best of ${r.videoCount} videos)` : '';
			return `${rank} ${r.channelName} - **${fmt(r.best.views)} views** - ${r.best.url}${more}`;
		})
		.join('\n');
}

module.exports = {
	YOUTUBE_AUTO: Boolean(YT_KEY),
	parseYouTubePage,
	parseYouTubeChannelPage,
	platformOf,
	channelLinkError,
	videoLinkError,
	hasHashtag,
	parseTikTokPage,
	parseYouTubeVideoId,
	checkEvent,
	formatRanking,
	fmt,
};

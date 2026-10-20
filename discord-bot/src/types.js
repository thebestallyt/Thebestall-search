// Event-Typen mit ihren Standard-Einstellungen (Vorlagen)
const DEFAULT_HASHTAG = (process.env.HASHTAG ?? 'weakspot').replace(/^#/, '');

// Feldarten für das Beitritts-Formular
const FIELD_KINDS = {
	text: 'Short text',
	long: 'Long text',
	link: 'Link (URL)',
	number: 'Number',
	channel: 'YouTube/TikTok channel link',
	videos: 'Video links (one per line)',
};

const WINNER_MODES = {
	none: { label: 'No winners', description: 'Just collect sign-ups' },
	manual: { label: 'Staff picks the winner(s)', description: 'A menu to choose winners appears at the end' },
	random: { label: 'Random draw', description: 'The bot draws the winners automatically' },
	votes: { label: 'Most votes', description: 'Members vote, most votes wins' },
	views: { label: 'Most views', description: 'Most video views wins (video contests only)' },
};

const TYPES = {
	views: {
		name: 'Video views contest',
		emoji: '🎥',
		color: 0xff2e3e,
		defaults: {
			title: 'Video Contest',
			description: 'Make a video and get as many views as you can – the video with the most views wins!',
			fields: [
				{ key: 'name', label: 'Channel name', placeholder: 'e.g. Luxon Studios', kind: 'text', required: true },
				{ key: 'link', label: 'YouTube or TikTok channel link', placeholder: 'https://www.youtube.com/@YourChannel', kind: 'channel', required: true },
				{ key: 'videos', label: 'Your video links (one per line)', placeholder: 'TikTok: required! YouTube: optional', kind: 'videos', required: false },
			],
			winnerMode: 'manual',
			listFormat: '{name} - {link}',
			joinLabel: 'Join Contest',
			views: { hashtag: DEFAULT_HASHTAG, platforms: ['youtube', 'tiktok'], onlyNew: true },
		},
	},
	submission: {
		name: 'Submission contest (builds, art, clips…)',
		emoji: '🎨',
		color: 0xb04dff,
		defaults: {
			title: 'Build Contest',
			description: 'Show us your best work! Submit your entry before the deadline.',
			fields: [
				{ key: 'entry', label: 'Your submission (link)', placeholder: 'Link to your image, video or game', kind: 'link', required: true },
				{ key: 'notes', label: 'Anything to add? (optional)', placeholder: 'Describe your entry', kind: 'long', required: false },
			],
			winnerMode: 'manual',
			listFormat: '{user} - {entry}',
			joinLabel: 'Submit Entry',
			voting: { mode: 'off', durationSpec: '1d', allowSelf: false },
		},
	},
	giveaway: {
		name: 'Giveaway',
		emoji: '🎁',
		color: 0x35d14a,
		defaults: {
			title: 'Giveaway',
			description: 'Click the button to enter – winners are drawn at random!',
			fields: [],
			winnerMode: 'random',
			listFormat: '{user}',
			joinLabel: 'Enter Giveaway',
			showParticipants: false,
		},
	},
	signup: {
		name: 'Sign-up (tournament, meetup…)',
		emoji: '📋',
		color: 0x2f8cff,
		defaults: {
			title: 'Tournament Sign-up',
			description: 'Sign up now – spots are limited!',
			fields: [{ key: 'ign', label: 'Roblox username', placeholder: 'Your in-game name', kind: 'text', required: true }],
			winnerMode: 'none',
			listFormat: '{user} - {ign}',
			joinLabel: 'Sign Up',
			maxParticipants: 16,
		},
	},
	custom: {
		name: 'Custom event',
		emoji: '⚙️',
		color: 0xffd21f,
		defaults: {
			title: 'Event',
			description: 'Join the event!',
			fields: [{ key: 'answer', label: 'Your answer', placeholder: '', kind: 'text', required: true }],
			winnerMode: 'manual',
			listFormat: '{user} - {answer}',
			joinLabel: 'Join',
		},
	},
};

// Neues Event aus einer Vorlage (alle Einstellungen vorbelegt)
function eventFromTemplate(type) {
	const t = TYPES[type];
	const d = structuredClone(t.defaults);
	return {
		type,
		status: 'draft',
		title: d.title,
		description: d.description,
		prize: null,
		imageUrl: null,
		color: t.color,
		joinLabel: d.joinLabel,
		channelId: null,
		messageId: null,
		resultsChannelId: null,
		pingRoleId: null,
		requiredRoleId: null,
		startSpec: '',
		endSpec: '7d',
		startsAt: null,
		endsAt: null,
		maxParticipants: d.maxParticipants ?? null,
		winnerCount: 1,
		winnerMode: d.winnerMode,
		fields: d.fields,
		listFormat: d.listFormat,
		showParticipants: d.showParticipants ?? true,
		allowLeave: true,
		reminders: [24],
		remindersSent: [],
		views: d.views ?? null,
		voting: d.voting ?? null,
		votingEndsAt: null,
		entries: {},
		votes: {},
		winners: [],
		results: null,
	};
}

const winnerModesFor = (type) =>
	Object.keys(WINNER_MODES).filter((m) => (m === 'views' ? type === 'views' : true));

module.exports = { TYPES, FIELD_KINDS, WINNER_MODES, eventFromTemplate, winnerModesFor, DEFAULT_HASHTAG };

import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { Database } from '../src/database/database';
import { VoteEventDb, VoteEventRow, voteEligibilityMessage } from '../src/database/vote-event.db';

type QueryFn = typeof Database.query;

const originalQuery = Database.query;

afterEach(() => {
	Database.query = originalQuery;
});

function baseEvent(overrides: Partial<VoteEventRow> = {}): VoteEventRow {
	return {
		id: 1,
		name: 'Party',
		owner_id: 1,
		is_public: false,
		vote_policy: 'EVERYONE',
		latitude: null,
		longitude: null,
		radius_meters: null,
		starts_at: null,
		ends_at: null,
		version: 0,
		...overrides,
	};
}

test('create inserts a row and returns the new id', async () => {
	Database.query = (async (sql: string) => {
		if (sql.includes('INSERT INTO vote_events')) return { insertId: 7 } as any;
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	const id = await VoteEventDb.create(1, 'Party');
	assert.equal(id, 7);
});

test('getAccessible returns public events, the owner\'s own events, and events the user is invited to', async () => {
	Database.query = (async (_sql: string, ...args: any[]) => {
		const [userId] = args;
		const events = [
			baseEvent({ id: 1, is_public: true, owner_id: 99 }),
			baseEvent({ id: 2, is_public: false, owner_id: userId }),
			baseEvent({ id: 3, is_public: false, owner_id: 99 }),
		];
		return events.filter(event => event.is_public || event.owner_id === userId || event.id === 2);
	}) as QueryFn;

	const events = await VoteEventDb.getAccessible(5);
	assert.deepEqual(events.map(event => event.id), [1, 2]);
});

test('search returns accessible events whose name matches the query', async () => {
	Database.query = (async (_sql: string, ...args: any[]) => {
		const [userId, , likeQuery] = args;
		const pattern = String(likeQuery).replace(/%/g, '');
		const events = [
			baseEvent({ id: 1, name: 'Beach Party', is_public: true, owner_id: 99 }),
			baseEvent({ id: 2, name: 'Office Party', is_public: false, owner_id: userId }),
			baseEvent({ id: 3, name: 'Beach Cleanup', is_public: false, owner_id: 99 }),
		];
		return events.filter(event =>
			(event.is_public || event.owner_id === userId) && event.name.includes(pattern),
		);
	}) as QueryFn;

	const events = await VoteEventDb.search(5, 'Party');
	assert.deepEqual(events.map(event => event.id), [1, 2]);
});

test('getById returns null when no row matches', async () => {
	Database.query = (async () => []) as QueryFn;
	assert.equal(await VoteEventDb.getById(404), null);
});

test('canView allows public events, the owner, and invited users, and denies everyone else', async () => {
	const events = [baseEvent({ id: 1, is_public: true }), baseEvent({ id: 2, is_public: false, owner_id: 1 })];
	const invites = [{ event_id: 2, user_id: 5 }];

	Database.query = (async (_sql: string, ...args: any[]) => {
		const [eventId, ownerCheckUserId, inviteCheckUserId] = args;
		const event = events.find(e => e.id === eventId);
		if (!event) return [];
		const canView = event.is_public || event.owner_id === ownerCheckUserId ||
			invites.some(invite => invite.event_id === eventId && invite.user_id === inviteCheckUserId);
		return canView ? [{ found: 1 }] : [];
	}) as QueryFn;

	assert.equal(await VoteEventDb.canView(1, 99), true);
	assert.equal(await VoteEventDb.canView(2, 1), true);
	assert.equal(await VoteEventDb.canView(2, 5), true);
	assert.equal(await VoteEventDb.canView(2, 6), false);
});

test('canVote: EVERYONE policy allows any user who can view the event', async () => {
	Database.query = (async () => [{ found: 1 }]) as QueryFn;
	const event = baseEvent({ vote_policy: 'EVERYONE', owner_id: 1 });
	assert.equal(await VoteEventDb.canVote(event, 5), true);
});

test('canVote: owner can always vote regardless of policy', async () => {
	Database.query = (async () => [{ found: 1 }]) as QueryFn;
	const event = baseEvent({ vote_policy: 'INVITED', owner_id: 1 });
	assert.equal(await VoteEventDb.canVote(event, 1), true);
});

test('canVote: INVITED policy requires an invite row', async () => {
	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT 1 found') && sql.includes('FROM vote_events e')) return [{ found: 1 }];
		if (sql.includes('SELECT 1 found FROM vote_event_invites')) {
			const [, userId] = args;
			return userId === 5 ? [{ found: 1 }] : [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	const event = baseEvent({ vote_policy: 'INVITED', owner_id: 1 });
	assert.equal(await VoteEventDb.canVote(event, 5), true);
	assert.equal(await VoteEventDb.canVote(event, 6), false);
});

test('canVote: LOCATION_TIME policy requires being within the time window and geofence radius', async () => {
	Database.query = (async () => [{ found: 1 }]) as QueryFn;

	const now = Date.now();
	const event = baseEvent({
		vote_policy: 'LOCATION_TIME',
		owner_id: 1,
		latitude: 48.8566,
		longitude: 2.3522,
		radius_meters: 1000,
		starts_at: new Date(now - 60_000).toISOString(),
		ends_at: new Date(now + 60_000).toISOString(),
	});

	// Inside the time window and close to the event location: allowed.
	assert.equal(
		await VoteEventDb.canVote(event, 5, { latitude: 48.8566, longitude: 2.3522 }),
		true,
	);

	// Far outside the geofence radius: denied.
	assert.equal(
		await VoteEventDb.canVote(event, 5, { latitude: 40.0, longitude: 2.3522 }),
		false,
	);

	// Missing location: denied.
	assert.equal(await VoteEventDb.canVote(event, 5, {}), false);

	// Outside the time window: denied.
	const expiredEvent = baseEvent({
		vote_policy: 'LOCATION_TIME',
		owner_id: 1,
		latitude: 48.8566,
		longitude: 2.3522,
		radius_meters: 1000,
		starts_at: new Date(now - 120_000).toISOString(),
		ends_at: new Date(now - 60_000).toISOString(),
	});
	assert.equal(
		await VoteEventDb.canVote(expiredEvent, 5, { latitude: 48.8566, longitude: 2.3522 }),
		false,
	);
});

test('canVote returns false when the event cannot be viewed at all', async () => {
	Database.query = (async () => []) as QueryFn;
	const event = baseEvent({ vote_policy: 'EVERYONE' });
	assert.equal(await VoteEventDb.canVote(event, 5), false);
});

test('getVoteEligibility returns a specific reason for each ineligible branch', async () => {
	// NOT_VIEWABLE: the event cannot be viewed at all.
	Database.query = (async () => []) as QueryFn;
	let event = baseEvent({ vote_policy: 'EVERYONE' });
	assert.deepEqual(await VoteEventDb.getVoteEligibility(event, 5), {
		eligible: false,
		reason: 'NOT_VIEWABLE',
	});

	// NOT_INVITED: viewable (public), INVITED policy, no invite row.
	Database.query = (async (sql: string) => {
		if (sql.includes('SELECT 1 found') && sql.includes('FROM vote_events e')) return [{ found: 1 }];
		if (sql.includes('SELECT 1 found FROM vote_event_invites')) return [];
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;
	event = baseEvent({ vote_policy: 'INVITED', owner_id: 1 });
	assert.deepEqual(await VoteEventDb.getVoteEligibility(event, 5), {
		eligible: false,
		reason: 'NOT_INVITED',
	});

	// WINDOW_NOT_CONFIGURED: LOCATION_TIME event with no starts_at/ends_at.
	Database.query = (async () => [{ found: 1 }]) as QueryFn;
	event = baseEvent({ vote_policy: 'LOCATION_TIME', owner_id: 1 });
	assert.deepEqual(await VoteEventDb.getVoteEligibility(event, 5), {
		eligible: false,
		reason: 'WINDOW_NOT_CONFIGURED',
	});

	// OUTSIDE_TIME_WINDOW: window configured but now is outside of it.
	const now = Date.now();
	event = baseEvent({
		vote_policy: 'LOCATION_TIME',
		owner_id: 1,
		latitude: 48.8566,
		longitude: 2.3522,
		radius_meters: 1000,
		starts_at: new Date(now - 120_000).toISOString(),
		ends_at: new Date(now - 60_000).toISOString(),
	});
	assert.deepEqual(
		await VoteEventDb.getVoteEligibility(event, 5, { latitude: 48.8566, longitude: 2.3522 }),
		{ eligible: false, reason: 'OUTSIDE_TIME_WINDOW' },
	);

	// LOCATION_NOT_CONFIGURED: in the time window, but the event has no coordinates.
	event = baseEvent({
		vote_policy: 'LOCATION_TIME',
		owner_id: 1,
		starts_at: new Date(now - 60_000).toISOString(),
		ends_at: new Date(now + 60_000).toISOString(),
	});
	assert.deepEqual(
		await VoteEventDb.getVoteEligibility(event, 5, { latitude: 48.8566, longitude: 2.3522 }),
		{ eligible: false, reason: 'LOCATION_NOT_CONFIGURED' },
	);

	// LOCATION_UNAVAILABLE: event is configured, but the caller supplied no location.
	event = baseEvent({
		vote_policy: 'LOCATION_TIME',
		owner_id: 1,
		latitude: 48.8566,
		longitude: 2.3522,
		radius_meters: 1000,
		starts_at: new Date(now - 60_000).toISOString(),
		ends_at: new Date(now + 60_000).toISOString(),
	});
	assert.deepEqual(await VoteEventDb.getVoteEligibility(event, 5, {}), {
		eligible: false,
		reason: 'LOCATION_UNAVAILABLE',
	});

	// OUTSIDE_RADIUS: caller supplied a location, but far outside the geofence.
	assert.deepEqual(
		await VoteEventDb.getVoteEligibility(event, 5, { latitude: 40.0, longitude: 2.3522 }),
		{ eligible: false, reason: 'OUTSIDE_RADIUS' },
	);

	// Eligible: inside the window and geofence.
	assert.deepEqual(
		await VoteEventDb.getVoteEligibility(event, 5, { latitude: 48.8566, longitude: 2.3522 }),
		{ eligible: true, reason: null },
	);
});

test('voteEligibilityMessage maps each reason to a precise sentence, and null to an eligible message', () => {
	assert.equal(voteEligibilityMessage(null), 'you are eligible');
	assert.equal(voteEligibilityMessage('NOT_VIEWABLE'), "you don't have access to this event");
	assert.equal(voteEligibilityMessage('NOT_INVITED'), "you haven't been invited to vote on this event");
	assert.equal(voteEligibilityMessage('WINDOW_NOT_CONFIGURED'), "this event's voting window isn't configured yet");
	assert.equal(voteEligibilityMessage('OUTSIDE_TIME_WINDOW'), 'the voting window for this event is not currently open');
	assert.equal(voteEligibilityMessage('LOCATION_NOT_CONFIGURED'), "this event's location isn't configured");
	assert.equal(voteEligibilityMessage('LOCATION_UNAVAILABLE'), 'your location could not be determined');
	assert.equal(voteEligibilityMessage('OUTSIDE_RADIUS'), "you're too far from the event's location");
});

test('invite is owner-only and bumps the event version', async () => {
	const invites: Array<{ event_id: number; user_id: number }> = [];
	let version = 0;

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT * FROM vote_events')) {
			const [eventId] = args;
			return eventId === 1 ? [baseEvent({ id: 1, owner_id: 1, version })] : [];
		}
		if (sql.includes('INSERT IGNORE INTO vote_event_invites')) {
			const [eventId, userId] = args;
			invites.push({ event_id: eventId, user_id: userId });
			return [];
		}
		if (sql.includes('UPDATE vote_events SET version')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	assert.equal(await VoteEventDb.invite(1, 2, 5), false);
	assert.deepEqual(invites, []);

	assert.equal(await VoteEventDb.invite(1, 1, 5), true);
	assert.deepEqual(invites, [{ event_id: 1, user_id: 5 }]);
	assert.equal(version, 1);
});

test('removeInvite is owner-only, deletes the invite and the user\'s vote, and bumps version', async () => {
	const invites: Array<{ event_id: number; user_id: number }> = [{ event_id: 1, user_id: 5 }];
	const votes: Array<{ event_id: number; user_id: number }> = [{ event_id: 1, user_id: 5 }];
	let version = 0;

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT * FROM vote_events')) {
			const [eventId] = args;
			return eventId === 1 ? [baseEvent({ id: 1, owner_id: 1, version })] : [];
		}
		if (sql.includes('DELETE FROM vote_event_invites')) {
			const [eventId, userId] = args;
			const index = invites.findIndex(i => i.event_id === eventId && i.user_id === userId);
			if (index >= 0) invites.splice(index, 1);
			return [];
		}
		if (sql.includes('DELETE FROM vote_event_votes')) {
			const [eventId, userId] = args;
			const index = votes.findIndex(v => v.event_id === eventId && v.user_id === userId);
			if (index >= 0) votes.splice(index, 1);
			return [];
		}
		if (sql.includes('UPDATE vote_events SET version')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	assert.equal(await VoteEventDb.removeInvite(1, 2, 5), false);
	assert.deepEqual(invites, [{ event_id: 1, user_id: 5 }]);
	assert.deepEqual(votes, [{ event_id: 1, user_id: 5 }]);

	assert.equal(await VoteEventDb.removeInvite(1, 1, 5), true);
	assert.deepEqual(invites, []);
	assert.deepEqual(votes, []);
	assert.equal(version, 1);
});

test('remove is owner-only and deletes the vote_events row (cascades handle child rows)', async () => {
	let deletedEventIds: number[] = [];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT * FROM vote_events')) {
			const [eventId] = args;
			return eventId === 1 ? [baseEvent({ id: 1, owner_id: 1 })] : [];
		}
		if (sql.includes('DELETE FROM vote_events')) {
			const [eventId] = args;
			deletedEventIds.push(eventId);
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	assert.equal(await VoteEventDb.remove(1, 2), false);
	assert.deepEqual(deletedEventIds, []);

	assert.equal(await VoteEventDb.remove(1, 1), true);
	assert.deepEqual(deletedEventIds, [1]);

	assert.equal(await VoteEventDb.remove(404, 1), false);
	assert.deepEqual(deletedEventIds, [1]);
});

test('getInviteMembers / getVoterMembers resolve display info, and getMembers branches on vote_policy', async () => {
	Database.query = (async (sql: string) => {
		if (sql.includes('FROM vote_event_invites i')) {
			return [{ id: 5, email: 'voter@example.com', display_name: 'Voter' }];
		}
		if (sql.includes('FROM vote_event_votes v')) {
			return [{ id: 6, email: 'anyone@example.com', display_name: 'Anyone' }];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	assert.deepEqual(await VoteEventDb.getInviteMembers(1), [
		{ id: 5, email: 'voter@example.com', display_name: 'Voter' },
	]);
	assert.deepEqual(await VoteEventDb.getVoterMembers(1), [
		{ id: 6, email: 'anyone@example.com', display_name: 'Anyone' },
	]);

	const invited = baseEvent({ id: 1, vote_policy: 'INVITED' });
	assert.deepEqual(await VoteEventDb.getMembers(invited), [
		{ id: 5, email: 'voter@example.com', display_name: 'Voter' },
	]);

	// Public EVERYONE events have no invite mechanism, so members are the
	// read-only voter list.
	const everyone = baseEvent({ id: 1, vote_policy: 'EVERYONE', is_public: true });
	assert.deepEqual(await VoteEventDb.getMembers(everyone), [
		{ id: 6, email: 'anyone@example.com', display_name: 'Anyone' },
	]);

	// Private events gate access via invites regardless of vote policy, so the
	// owner must still be able to manage invitees even with an EVERYONE or
	// LOCATION_TIME policy.
	const privateEveryone = baseEvent({ id: 1, vote_policy: 'EVERYONE', is_public: false });
	assert.deepEqual(await VoteEventDb.getMembers(privateEveryone), [
		{ id: 5, email: 'voter@example.com', display_name: 'Voter' },
	]);

	const privateLocationTime = baseEvent({ id: 1, vote_policy: 'LOCATION_TIME', is_public: false });
	assert.deepEqual(await VoteEventDb.getMembers(privateLocationTime), [
		{ id: 5, email: 'voter@example.com', display_name: 'Voter' },
	]);
});

test('suggest throws when the user is not eligible to suggest tracks', async () => {
	Database.query = (async (sql: string) => {
		if (sql.includes('SELECT * FROM vote_events')) return [baseEvent({ vote_policy: 'INVITED', owner_id: 1 })];
		if (sql.includes('SELECT 1 found') && sql.includes('FROM vote_events e')) return [{ found: 1 }];
		if (sql.includes('SELECT 1 found FROM vote_event_invites')) return [];
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	await assert.rejects(() => VoteEventDb.suggest(1, 5, 10), /Not eligible to suggest/);
});

test('suggest inserts the track and bumps version when the user is eligible', async () => {
	const suggestions: Array<{ event_id: number; music_id: number; suggested_by: number }> = [];
	let version = 0;

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT * FROM vote_events')) return [baseEvent({ id: 1, vote_policy: 'EVERYONE', owner_id: 1, version })];
		if (sql.includes('SELECT 1 found') && sql.includes('FROM vote_events e')) return [{ found: 1 }];
		if (sql.includes('INSERT IGNORE INTO vote_event_tracks')) {
			const [eventId, musicId, suggestedBy] = args;
			suggestions.push({ event_id: eventId, music_id: musicId, suggested_by: suggestedBy });
			return [];
		}
		if (sql.includes('UPDATE vote_events SET version')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	await VoteEventDb.suggest(1, 5, 10);
	assert.deepEqual(suggestions, [{ event_id: 1, music_id: 10, suggested_by: 5 }]);
	assert.equal(version, 1);
});

test('vote throws when the track is not part of the event, toggles a vote on, then toggles it off, and supports voting for multiple tracks', async () => {
	let tracks: Array<{ event_id: number; music_id: number }> = [
		{ event_id: 1, music_id: 10 },
		{ event_id: 1, music_id: 20 },
	];
	const votes: Array<{ event_id: number; user_id: number; music_id: number }> = [];
	let version = 0;

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT * FROM vote_events')) return [baseEvent({ id: 1, vote_policy: 'EVERYONE', owner_id: 1, version })];
		if (sql.includes('SELECT 1 found') && sql.includes('FROM vote_events e')) return [{ found: 1 }];
		if (sql.includes('SELECT id FROM vote_events WHERE id = ? FOR UPDATE')) return [];
		if (sql.includes('SELECT 1 found FROM vote_event_tracks')) {
			const [eventId, musicId] = args;
			return tracks.some(t => t.event_id === eventId && t.music_id === musicId) ? [{ found: 1 }] : [];
		}
		if (sql.includes('SELECT 1 found FROM vote_event_votes')) {
			const [eventId, userId, musicId] = args;
			return votes.some(v => v.event_id === eventId && v.user_id === userId && v.music_id === musicId) ? [{ found: 1 }] : [];
		}
		if (sql.includes('INSERT INTO vote_event_votes')) {
			const [eventId, userId, musicId] = args;
			votes.push({ event_id: eventId, user_id: userId, music_id: musicId });
			return [];
		}
		if (sql.includes('DELETE FROM vote_event_votes')) {
			const [eventId, userId, musicId] = args;
			const index = votes.findIndex(v => v.event_id === eventId && v.user_id === userId && v.music_id === musicId);
			if (index >= 0) votes.splice(index, 1);
			return [];
		}
		if (sql.includes('UPDATE vote_events SET version')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	await assert.rejects(() => VoteEventDb.vote(1, 5, 404), /Track is not in this voting event/);

	// Voting for a track the user has not yet backed adds a vote row.
	await VoteEventDb.vote(1, 5, 10);
	assert.deepEqual(votes, [{ event_id: 1, user_id: 5, music_id: 10 }]);
	assert.equal(version, 1);

	// Voting for a second track does not remove the first vote: a user can
	// back several tracks at once.
	await VoteEventDb.vote(1, 5, 20);
	assert.deepEqual(votes, [
		{ event_id: 1, user_id: 5, music_id: 10 },
		{ event_id: 1, user_id: 5, music_id: 20 },
	]);
	assert.equal(version, 2);

	// Voting again for a track the user already backed toggles the vote off.
	await VoteEventDb.vote(1, 5, 10);
	assert.deepEqual(votes, [{ event_id: 1, user_id: 5, music_id: 20 }]);
	assert.equal(version, 3);
});

test('getTracks / getUserVotes / getInviteIds return their respective rows', async () => {
	Database.query = (async (sql: string) => {
		if (sql.includes('FROM vote_event_tracks t')) {
			return [{ music_id: 1, title: 'Song', artist_name: 'Artist', duration: 100, suggested_by: 2, vote_count: 3 }];
		}
		if (sql.includes('SELECT music_id FROM vote_event_votes')) return [{ music_id: 1 }, { music_id: 2 }];
		if (sql.includes('SELECT user_id FROM vote_event_invites')) return [{ user_id: 2 }, { user_id: 3 }];
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	assert.equal((await VoteEventDb.getTracks(1))[0].vote_count, 3);
	assert.deepEqual(await VoteEventDb.getUserVotes(1, 5), [1, 2]);
	assert.deepEqual(await VoteEventDb.getInviteIds(1), [2, 3]);
});

test('getUserVotes returns an empty array when the user has not voted', async () => {
	Database.query = (async () => []) as QueryFn;
	assert.deepEqual(await VoteEventDb.getUserVotes(1, 5), []);
});

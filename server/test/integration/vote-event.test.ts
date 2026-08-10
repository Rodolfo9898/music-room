import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../../src/database/database';
import { AccountDb } from '../../src/database/account.db';
import { AccountService } from '../../src/api/accounts/account.service';
import { VoteEventDb } from '../../src/database/vote-event.db';
import { GeocodingService } from '../../src/utils/geocoding.service';
import { createConfirmedUser, gql, startTestServer, TestServer, uniqueEmail } from './helpers';

let server: TestServer;
let ownerId: number;
let voterId: number;
let outsiderId: number;
let eventId: number;
let musicIds: number[];
let createEventToken: string;
let createEventAccountId: number;
let createdViaMutationEventId: number | undefined;
const originalResolveLocation = GeocodingService.resolveLocation;

before(async () => {
	server = await startTestServer();
	ownerId = Number(await AccountDb.insert(uniqueEmail('vote-owner'), 'owner', AccountService.hashPassword('Password-42!')));
	voterId = Number(await AccountDb.insert(uniqueEmail('vote-voter'), 'voter', AccountService.hashPassword('Password-42!')));
	outsiderId = Number(await AccountDb.insert(uniqueEmail('vote-outsider'), 'outsider', AccountService.hashPassword('Password-42!')));
	const musics = await Database.query<{ id: number }>('SELECT id FROM musics ORDER BY id LIMIT 2');
	musicIds = musics.map(row => Number(row.id));
	assert.equal(musicIds.length, 2, 'the seed must provide two tracks');
	const creator = await createConfirmedUser(server.baseUrl, uniqueEmail('vote-create'), 'Password-42!');
	createEventToken = creator.token;
	createEventAccountId = creator.accountId;
});

after(async () => {
	GeocodingService.resolveLocation = originalResolveLocation;
	if (eventId) await Database.query('DELETE FROM vote_events WHERE id = ?', eventId);
	if (createdViaMutationEventId) await Database.query('DELETE FROM vote_events WHERE id = ?', createdViaMutationEventId);
	if (ownerId && voterId && outsiderId) {
		await Database.query('DELETE FROM users WHERE id IN (?, ?, ?)', ownerId, voterId, outsiderId);
	}
	if (createEventAccountId) {
		await fetch(`${server.baseUrl}/accounts/me`, {
			method: 'DELETE',
			headers: { 'Access-Token': createEventToken },
		}).catch(() => {});
	}
	await server.close();
});

test('private invited vote event enforces discovery and participation', async () => {
	eventId = await VoteEventDb.create(ownerId, 'Integration vote', false, 'INVITED');
	assert.equal(await VoteEventDb.canView(eventId, outsiderId), false);
	assert.equal(await VoteEventDb.invite(eventId, ownerId, voterId), true);
	assert.equal(await VoteEventDb.canView(eventId, voterId), true);
	const event = await VoteEventDb.getById(eventId);
	assert.ok(event);
	assert.equal(await VoteEventDb.canVote(event!, outsiderId), false);
	assert.equal(await VoteEventDb.canVote(event!, voterId), true);
});

test('device control can be delegated only to an accepted friend and revoked', async () => {
	await AccountDb.registerDevice(ownerId, 'integration-device', 'Test player', 'android', '1.0.0');
	const device = (await AccountDb.listDevices(ownerId))[0];
	assert.equal(await AccountDb.grantDeviceControl(ownerId, device.id, voterId), false);
	await AccountDb.requestFriend(ownerId, voterId);
	assert.equal(await AccountDb.acceptFriend(voterId, ownerId), true);
	assert.equal(await AccountDb.grantDeviceControl(ownerId, device.id, voterId), true);
	assert.equal(await AccountDb.canControlOwnerDevice(ownerId, 'integration-device', voterId), true);
	await AccountDb.revokeDeviceControl(ownerId, device.id, voterId);
	assert.equal(await AccountDb.canControlOwnerDevice(ownerId, 'integration-device', voterId), false);
});

test('a user can vote for multiple tracks at once and toggle a vote off', async () => {
	await VoteEventDb.suggest(eventId, ownerId, musicIds[0]);
	await VoteEventDb.suggest(eventId, ownerId, musicIds[1]);
	await Promise.all([
		VoteEventDb.vote(eventId, voterId, musicIds[0]),
		VoteEventDb.vote(eventId, voterId, musicIds[1]),
	]);
	const rows = await Database.query<{ count: number }>(
		'SELECT COUNT(*) count FROM vote_event_votes WHERE event_id = ? AND user_id = ?',
		eventId,
		voterId,
	);
	assert.equal(Number(rows[0].count), 2, 'voting for two tracks keeps both votes');
	assert.deepEqual((await VoteEventDb.getUserVotes(eventId, voterId)).sort(), [...musicIds].sort());
	let totalVotes = (await VoteEventDb.getTracks(eventId)).reduce((sum, track) => sum + Number(track.vote_count), 0);
	assert.equal(totalVotes, 2);

	// Voting again for a track the user already backed toggles it off.
	await VoteEventDb.vote(eventId, voterId, musicIds[0]);
	assert.deepEqual(await VoteEventDb.getUserVotes(eventId, voterId), [musicIds[1]]);
	totalVotes = (await VoteEventDb.getTracks(eventId)).reduce((sum, track) => sum + Number(track.vote_count), 0);
	assert.equal(totalVotes, 1);
});

test('removing an invited member also removes their vote and revokes access', async () => {
	assert.deepEqual(await VoteEventDb.getUserVotes(eventId, voterId), [musicIds[1]], 'the voter must have an existing vote before removal');

	assert.equal(await VoteEventDb.removeInvite(eventId, outsiderId, voterId), false, 'only the owner can remove members');
	assert.equal(await VoteEventDb.removeInvite(eventId, ownerId, voterId), true);

	assert.equal(await VoteEventDb.canView(eventId, voterId), false, 'a removed member loses view access again');
	assert.deepEqual(await VoteEventDb.getUserVotes(eventId, voterId), [], 'the removed member\'s votes must be cleared');
	const totalVotes = (await VoteEventDb.getTracks(eventId)).reduce((sum, track) => sum + Number(track.vote_count), 0);
	assert.equal(totalVotes, 0, 'the removed member\'s votes must no longer count toward the ranking');
});

test('createVoteEvent with LOCATION_TIME resolves the typed location server-side via geocoding', async () => {
	GeocodingService.resolveLocation = (async (query: string) => {
		assert.equal(query, 'Eiffel Tower, Paris');
		return { latitude: 48.8584, longitude: 2.2945 };
	}) as typeof GeocodingService.resolveLocation;

	const now = new Date();
	const startsAt = now.toISOString();
	const endsAt = new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString();
	const data = await gql<{ createVoteEvent: { id: number; latitude: number; longitude: number } }>(
		server.baseUrl,
		`mutation { createVoteEvent(name: "Geocoded event", votePolicy: LOCATION_TIME, location: "Eiffel Tower, Paris", radiusMeters: 250, startsAt: "${startsAt}", endsAt: "${endsAt}") { id latitude longitude } }`,
		createEventToken,
	);
	createdViaMutationEventId = data.createVoteEvent.id;
	assert.equal(Number(data.createVoteEvent.latitude), 48.8584);
	assert.equal(Number(data.createVoteEvent.longitude), 2.2945);
});

test('createVoteEvent with LOCATION_TIME surfaces a clear error when the location cannot be resolved', async () => {
	GeocodingService.resolveLocation = (async () => null) as typeof GeocodingService.resolveLocation;

	const now = new Date();
	const startsAt = now.toISOString();
	const endsAt = new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString();
	await assert.rejects(
		() => gql(
			server.baseUrl,
			`mutation { createVoteEvent(name: "Bad location", votePolicy: LOCATION_TIME, location: "nowhere-at-all-xyz", radiusMeters: 250, startsAt: "${startsAt}", endsAt: "${endsAt}") { id } }`,
			createEventToken,
		),
		/Could not resolve that location/,
	);
});

test('the voteEvents list query only reports can_vote true for a LOCATION_TIME event when the caller passes matching in-range coordinates', async () => {
	const now = new Date();
	const startsAt = new Date(now.getTime() - 60 * 1000).toISOString();
	const endsAt = new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString();
	const locationEventId = Number(await VoteEventDb.create(ownerId, 'Nearby event', true, 'LOCATION_TIME', {
		latitude: 48.8584,
		longitude: 2.2945,
		radiusMeters: 250,
		startsAt,
		endsAt,
	}));
	try {
		const withoutLocation = await gql<{ voteEvents: { id: number; can_vote: boolean; can_vote_reason: string | null }[] }>(
			server.baseUrl,
			'query { voteEvents { id can_vote can_vote_reason } }',
			createEventToken,
		);
		const withoutLocationEvent = withoutLocation.voteEvents.find(e => e.id === locationEventId);
		assert.ok(withoutLocationEvent, 'the event must be visible in the list');
		assert.equal(withoutLocationEvent!.can_vote, false, 'without coordinates the event must not be votable');
		assert.equal(withoutLocationEvent!.can_vote_reason, 'LOCATION_UNAVAILABLE');

		const withLocation = await gql<{ voteEvents: { id: number; can_vote: boolean; can_vote_reason: string | null }[] }>(
			server.baseUrl,
			'query { voteEvents(latitude: 48.8584, longitude: 2.2945) { id can_vote can_vote_reason } }',
			createEventToken,
		);
		const withLocationEvent = withLocation.voteEvents.find(e => e.id === locationEventId);
		assert.ok(withLocationEvent, 'the event must be visible in the list');
		assert.equal(withLocationEvent!.can_vote, true, 'with matching coordinates the event must be votable');
		assert.equal(withLocationEvent!.can_vote_reason, null);
	} finally {
		await Database.query('DELETE FROM vote_events WHERE id = ?', locationEventId);
	}
});

test('deleteVoteEvent is owner-only and removes the event (and its rows) for everyone', async () => {
	const other = await createConfirmedUser(server.baseUrl, uniqueEmail('vote-delete-other'), 'Password-42!');
	try {
		const created = await gql<{ createVoteEvent: { id: number } }>(
			server.baseUrl,
			'mutation { createVoteEvent(name: "Deletable event") { id } }',
			createEventToken,
		);
		const deletableEventId = created.createVoteEvent.id;

		await assert.rejects(
			() => gql(server.baseUrl, `mutation { deleteVoteEvent(eventId: ${deletableEventId}) }`, other.token),
			/Only the owner can delete this event/,
		);
		const stillThere = await Database.query<{ id: number }>('SELECT id FROM vote_events WHERE id = ?', deletableEventId);
		assert.equal(stillThere.length, 1, 'a non-owner delete attempt must not remove the event');

		const deleted = await gql<{ deleteVoteEvent: boolean }>(
			server.baseUrl,
			`mutation { deleteVoteEvent(eventId: ${deletableEventId}) }`,
			createEventToken,
		);
		assert.equal(deleted.deleteVoteEvent, true);

		const rows = await Database.query<{ id: number }>('SELECT id FROM vote_events WHERE id = ?', deletableEventId);
		assert.equal(rows.length, 0, 'the event row must be gone after deletion');
	} finally {
		await fetch(`${server.baseUrl}/accounts/me`, {
			method: 'DELETE',
			headers: { 'Access-Token': other.token },
		}).catch(() => {});
	}
});

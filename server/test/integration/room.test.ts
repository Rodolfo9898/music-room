import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
	startTestServer,
	uniqueEmail,
	gql,
	createConfirmedUser,
	TestServer,
} from './helpers';

// Grading flow: launch a playlist. Uses the GraphQL HTTP endpoint (/ws) with
// the seeded catalog (make db-migrate): music 1 = "The Fellowship",
// music 2 = "Hey Brother". Requires the local Docker DB.

const email = uniqueEmail('grader-room');
const password = 'Grading-password-42';
const secondEmail = uniqueEmail('grader-room-member');
const secondPassword = 'Grading-password-43';

let server: TestServer;
let authToken: string;
let accountId: number;
let roomId: number;
let secondToken: string;
let secondAccountId: number;

before(async () => {
	server = await startTestServer();
	const user = await createConfirmedUser(server.baseUrl, email, password);
	authToken = user.token;
	accountId = user.accountId;
	const secondUser = await createConfirmedUser(server.baseUrl, secondEmail, secondPassword);
	secondToken = secondUser.token;
	secondAccountId = secondUser.accountId;
});

after(async () => {
	// Last member leaving closes the room and stops the playback loop.
	if (roomId) {
		await gql(server.baseUrl, `mutation { leaveRoom(roomId: ${roomId}) }`, authToken).catch(() => {});
	}
	// Deleting the account also cleans up the playlists created below (FK cascade).
	await fetch(`${server.baseUrl}/accounts/me`, {
		method: 'DELETE',
		headers: { 'Access-Token': authToken },
	}).catch(() => {});
	await fetch(`${server.baseUrl}/accounts/me`, {
		method: 'DELETE',
		headers: { 'Access-Token': secondToken },
	}).catch(() => {});
	await server.close();
});

test('the seeded catalog is available', async () => {
	const data = await gql<{ musics: { id: number; title: string }[] }>(
		server.baseUrl,
		'query { musics { id title } }',
		authToken,
	);
	assert.ok(data.musics.length >= 14, `expected at least 14 seeded musics, got ${data.musics.length}`);
	assert.ok(data.musics.some(music => music.title === 'The Fellowship'));
});

test('createRoom creates an idle room with the user as host', async () => {
	const data = await gql<{ createRoom: { id: number; status: string; hostId: number } }>(
		server.baseUrl,
		'mutation { createRoom(name: "grading-room") { id status hostId } }',
		authToken,
	);
	assert.ok(data.createRoom.id > 0);
	assert.equal(data.createRoom.status, 'IDLE');
	assert.equal(data.createRoom.hostId, accountId);
	roomId = data.createRoom.id;
});

test('addToQueue queues a seeded music and auto-starts playback in an idle room', async () => {
	const data = await gql<{
		addToQueue: {
			success: boolean;
			room: { playlist: { musicId: number }[]; status: string; currentMusicId: number | null };
		};
	}>(
		server.baseUrl,
		`mutation { addToQueue(roomId: ${roomId}, musicId: 1) { success room { playlist { musicId } status currentMusicId } } }`,
		authToken,
	);
	assert.equal(data.addToQueue.success, true);
	assert.deepEqual(data.addToQueue.room.playlist.map(item => item.musicId), [1]);
	assert.equal(data.addToQueue.room.status, 'PLAYING');
	assert.equal(data.addToQueue.room.currentMusicId, 1);
});

test('play is a no-op when the queued playlist is already playing', async () => {
	const data = await gql<{ play: { success: boolean; room: { status: string; currentMusicId: number } } }>(
		server.baseUrl,
		`mutation { play(roomId: ${roomId}) { success room { status currentMusicId } } }`,
		authToken,
	);
	assert.equal(data.play.success, true);
	assert.equal(data.play.room.status, 'PLAYING');
	assert.equal(data.play.room.currentMusicId, 1);
});

test('creating a second room automatically leaves the first', async () => {
	// Keep the first room alive after the host leaves it by having a second
	// user join it first (host reassigns to them instead of the room closing).
	const joined = await gql<{ joinRoom: { id: number; hostId: number } }>(
		server.baseUrl,
		`mutation { joinRoom(roomId: ${roomId}) { id hostId } }`,
		secondToken,
	);
	assert.equal(joined.joinRoom.id, roomId);

	const created = await gql<{ createRoom: { id: number; status: string; hostId: number } }>(
		server.baseUrl,
		'mutation { createRoom(name: "grading-room-2") { id status hostId } }',
		authToken,
	);
	const secondRoomId = created.createRoom.id;
	assert.ok(secondRoomId > 0);
	assert.notEqual(secondRoomId, roomId);
	assert.equal(created.createRoom.hostId, accountId);

	const rooms = await gql<{ rooms: { id: number; hostId: number; memberIds: number[] }[] }>(
		server.baseUrl,
		'query { rooms { id hostId memberIds } }',
		authToken,
	);
	const firstRoom = rooms.rooms.find(room => room.id === roomId);
	const secondRoom = rooms.rooms.find(room => room.id === secondRoomId);
	assert.ok(firstRoom, 'first room should still be open (the second member kept it alive)');
	assert.ok(!firstRoom!.memberIds.includes(accountId), 'creating a new room should have left the first');
	assert.equal(firstRoom!.hostId, secondAccountId, 'host should be reassigned when the original host leaves');
	assert.ok(secondRoom);
	assert.deepEqual(secondRoom!.memberIds, [accountId]);

	// Point the shared `roomId`/cleanup at the still-open second room; leave
	// the first room via the second user so it closes cleanly too.
	roomId = secondRoomId;
	await gql(server.baseUrl, `mutation { leaveRoom(roomId: ${joined.joinRoom.id}) }`, secondToken).catch(() => {});
});

test('a persisted playlist can be created and filled', async () => {
	const created = await gql<{ createPlaylist: { id: number; version: number } }>(
		server.baseUrl,
		'mutation { createPlaylist(name: "grading-playlist", isPublic: true) { id version } }',
		authToken,
	);
	assert.ok(created.createPlaylist.id > 0);

	const updated = await gql<{ addTrackToPlaylist: { track_count: number; music_ids: number[] } }>(
		server.baseUrl,
		`mutation { addTrackToPlaylist(playlistId: ${created.createPlaylist.id}, musicId: 2) { track_count music_ids } }`,
		authToken,
	);
	assert.equal(updated.addTrackToPlaylist.track_count, 1);
	assert.deepEqual(updated.addTrackToPlaylist.music_ids, [2]);
});

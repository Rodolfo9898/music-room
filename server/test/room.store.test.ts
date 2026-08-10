import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { RoomStore } from '../src/rooms/room.store';
import { MusicDb } from '../src/database/music.db';
import { VoteEventDb, VoteTrackRow } from '../src/database/vote-event.db';

type GetByIdFn = typeof MusicDb.getById;
const originalGetById = MusicDb.getById;
const originalCanView = VoteEventDb.canView;
const originalGetTracks = VoteEventDb.getTracks;
const originalSuggest = VoteEventDb.suggest;

beforeEach(() => {
	// Avoid touching the real DB / filesystem: any room action that triggers
	// playback (addMusic/setQueue/play/next/previous) looks up the track via
	// MusicDb.getById in the background. Returning null makes RoomStore mark
	// the room idle immediately instead of trying to stream a real file.
	MusicDb.getById = (async () => null) as GetByIdFn;
});

afterEach(() => {
	MusicDb.getById = originalGetById;
	VoteEventDb.canView = originalCanView;
	VoteEventDb.getTracks = originalGetTracks;
	VoteEventDb.suggest = originalSuggest;
});

function mockVoteTracks(musicIds: number[]): void {
	VoteEventDb.getTracks = (async () => musicIds.map((musicId, index) => ({
		music_id: musicId,
		title: `Track ${musicId}`,
		artist_name: 'Artist',
		duration: 100,
		vote_count: musicIds.length - index,
		suggested_by: 1,
	} satisfies VoteTrackRow))) as typeof VoteEventDb.getTracks;
}

test('createRoom adds the host as a member and removes them from any other room they were in', () => {
	const store = new RoomStore();
	const { room: roomA } = store.createRoom(1, 'Room A');
	assert.deepEqual(roomA.memberIds(), [1]);

	const { leftRoomIds } = store.createRoom(1, 'Room B');
	assert.deepEqual(leftRoomIds, [roomA.id]);
	assert.equal(store.getRoom(roomA.id), null); // room A closed once empty
});

test('joinRoom moves a user out of their previous room and makes them a member of the new one', () => {
	const store = new RoomStore();
	const { room: roomA } = store.createRoom(1, 'Room A');
	const { room: roomB } = store.createRoom(2, 'Room B');

	const { leftRoomIds } = store.joinRoom(roomB.id, 1);
	assert.deepEqual(leftRoomIds, [roomA.id]);
	assert.deepEqual(roomB.memberIds().sort(), [1, 2]);
	assert.equal(store.getRoom(roomA.id), null); // room A closed once empty
});

test('leaveRoom reassigns the host to another member, or closes the room once empty', () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);
	assert.equal(room.hostId, 1);

	store.leaveRoom(room.id, 1);
	assert.equal(room.hostId, 2);
	assert.deepEqual(room.memberIds(), [2]);

	store.leaveRoom(room.id, 2);
	assert.equal(store.getRoom(room.id), null); // closed once empty
});

test('deleteRoom is host-only and removes the room', () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);

	assert.equal(store.deleteRoom(room.id, 2).ok, false);
	assert.ok(store.getRoom(room.id));

	assert.equal(store.deleteRoom(room.id, 1).ok, true);
	assert.equal(store.getRoom(room.id), null);
});

test('deleteRoom on an unknown room fails gracefully', () => {
	const store = new RoomStore();
	assert.equal(store.deleteRoom(999, 1).ok, false);
});

test('transferHost is host-only and requires the target to already be a room member', () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);

	assert.equal(store.transferHost(room.id, 2, 1).ok, false); // not host
	assert.equal(store.transferHost(room.id, 1, 99).ok, false); // target not a member
	assert.equal(store.transferHost(room.id, 1, 2).ok, true);
	assert.equal(room.hostId, 2);
});

test('addMusic/setQueue/play/next/previous/seek are rejected for non-hosts', () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);

	assert.equal(store.addMusic(room.id, 2, 100).ok, false);
	assert.equal(store.setQueue(room.id, 2, [1, 2]).ok, false);
	assert.equal(store.play(room.id, 2).ok, false);
	assert.equal(store.next(room.id, 2).ok, false);
	assert.equal(store.previous(room.id, 2).ok, false);
	assert.equal(store.seek(room.id, 2, 100).ok, false);

	assert.equal(store.addMusic(room.id, 1, 100).ok, true);
	assert.equal(store.setQueue(room.id, 1, [10, 20]).ok, true);
});

test('room actions on an unknown room id all fail with a not-found message', () => {
	const store = new RoomStore();
	assert.equal(store.addMusic(999, 1, 1).ok, false);
	assert.equal(store.setQueue(999, 1, [1]).ok, false);
	assert.equal(store.play(999, 1).ok, false);
	assert.equal(store.pause(999, 1).ok, false);
	assert.equal(store.next(999, 1).ok, false);
	assert.equal(store.previous(999, 1).ok, false);
	assert.equal(store.seek(999, 1, 1).ok, false);
});

test('schedulePendingLeave delays removal, and cancelPendingLeave (e.g. rejoin) prevents it', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);

	store.schedulePendingLeave(room.id, 2, 20);
	assert.deepEqual(room.memberIds().sort(), [1, 2]);

	store.cancelPendingLeave(room.id, 2);
	await new Promise(resolve => setTimeout(resolve, 40));
	assert.deepEqual(room.memberIds().sort(), [1, 2]); // cancelled: still a member
});

test('schedulePendingLeave eventually removes the member if not cancelled', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);

	store.schedulePendingLeave(room.id, 2, 20);
	await new Promise(resolve => setTimeout(resolve, 60));
	assert.deepEqual(room.memberIds(), [1]);
});

test('joining while a pending leave is scheduled cancels the leave', () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);

	store.schedulePendingLeave(room.id, 2, 20);
	store.joinRoom(room.id, 2); // reconnect before the grace period elapses
	assert.deepEqual(room.memberIds().sort(), [1, 2]);
});

test('subscribeRooms emits an updated room list whenever rooms are created, joined, or closed', async () => {
	const store = new RoomStore();
	const iterator = store.subscribeRooms();

	const firstUpdate = iterator.next();
	store.createRoom(1, 'Room A');
	const first = await firstUpdate;
	assert.equal(first.done, false);
	assert.equal(first.value.length, 1);

	await iterator.return?.(undefined);
});

test('subscribe delivers STATE events for room changes and a CLOSED event when the room is destroyed', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	const iterator = store.subscribe(room.id);

	const statePromise = iterator.next();
	store.joinRoom(room.id, 2);
	const stateEvent = await statePromise;
	assert.equal(stateEvent.done, false);
	assert.equal(stateEvent.value.type, 'STATE');

	const closedPromise = iterator.next();
	store.deleteRoom(room.id, 1);
	const closedEvent = await closedPromise;
	assert.equal(closedEvent.value.type, 'CLOSED');
});

test('subscribe on an unknown room throws', () => {
	const store = new RoomStore();
	assert.throws(() => store.subscribe(999));
});

test('linkVoteEvent is host-only and requires the event to be viewable', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	store.joinRoom(room.id, 2);
	mockVoteTracks([100, 200]);
	room.setPlaybackIterator({} as never); // simulate active streaming so linking doesn't race a real playback start

	VoteEventDb.canView = (async () => true) as typeof VoteEventDb.canView;
	assert.equal((await store.linkVoteEvent(room.id, 2, 42)).ok, false); // not host

	VoteEventDb.canView = (async () => false) as typeof VoteEventDb.canView;
	assert.equal((await store.linkVoteEvent(room.id, 1, 42)).ok, false); // not viewable

	VoteEventDb.canView = (async () => true) as typeof VoteEventDb.canView;
	const result = await store.linkVoteEvent(room.id, 1, 42);
	assert.equal(result.ok, true);
	assert.equal(room.linkedVoteEventId, 42);
	assert.deepEqual(room.playlist.snapshot().map(item => item.musicId), [100, 200]);
});

test('linkVoteEvent seeds the queue and future vote-event updates reorder the upcoming tail', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	VoteEventDb.canView = (async () => true) as typeof VoteEventDb.canView;
	mockVoteTracks([100, 200, 300]);
	// Simulate active streaming throughout so the store never races a real
	// playback start/stop against the reordering under test.
	room.setPlaybackIterator({} as never);

	await store.linkVoteEvent(room.id, 1, 42);
	assert.deepEqual(room.playlist.snapshot().map(item => item.musicId), [100, 200, 300]);

	room.next(1); // advance to musicId 200, index 1
	assert.equal(room.currentMusicId, 200);

	// Votes change the ranking; new suggestion (400) enters.
	mockVoteTracks([300, 400, 100]);
	const publishModule = await import('../src/web-socket/vote.events');
	publishModule.publishVoteEventUpdate(42);

	// Give the background sync loop a tick to react to the published event.
	await new Promise(resolve => setTimeout(resolve, 20));

	assert.equal(room.currentMusicId, 200); // untouched: still playing
	const ids = room.playlist.snapshot().map(item => item.musicId);
	assert.deepEqual(ids, [100, 200, 300, 400]);
});

test('unlinkVoteEvent is host-only and stops future auto-reordering', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	VoteEventDb.canView = (async () => true) as typeof VoteEventDb.canView;
	mockVoteTracks([100, 200]);
	await store.linkVoteEvent(room.id, 1, 42);

	store.joinRoom(room.id, 2);
	assert.equal(store.unlinkVoteEvent(room.id, 2).ok, false); // not host
	assert.equal(store.unlinkVoteEvent(room.id, 1).ok, true);
	assert.equal(room.linkedVoteEventId, null);

	const idsBefore = room.playlist.snapshot().map(item => item.musicId);
	mockVoteTracks([999]);
	const publishModule = await import('../src/web-socket/vote.events');
	publishModule.publishVoteEventUpdate(42);
	await new Promise(resolve => setTimeout(resolve, 20));
	assert.deepEqual(room.playlist.snapshot().map(item => item.musicId), idsBefore); // unaffected
});

test('addMusic best-effort suggests the newly queued track to a linked vote event', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	VoteEventDb.canView = (async () => true) as typeof VoteEventDb.canView;
	mockVoteTracks([100]);
	await store.linkVoteEvent(room.id, 1, 42);

	let suggestedArgs: unknown[] | null = null;
	VoteEventDb.suggest = (async (...args: unknown[]) => {
		suggestedArgs = args;
	}) as typeof VoteEventDb.suggest;

	assert.equal(store.addMusic(room.id, 1, 555).ok, true);
	await new Promise(resolve => setTimeout(resolve, 20));
	assert.deepEqual(suggestedArgs, [42, 1, 555]);
});

test('addMusic does not fail the queue action if suggesting to the linked vote event is rejected', async () => {
	const store = new RoomStore();
	const { room } = store.createRoom(1, 'Room A');
	VoteEventDb.canView = (async () => true) as typeof VoteEventDb.canView;
	mockVoteTracks([100]);
	await store.linkVoteEvent(room.id, 1, 42);

	VoteEventDb.suggest = (async () => {
		throw new Error('Not eligible to suggest tracks for this event');
	}) as typeof VoteEventDb.suggest;

	const result = store.addMusic(room.id, 1, 555);
	assert.equal(result.ok, true);
	await new Promise(resolve => setTimeout(resolve, 20)); // rejection is swallowed
});

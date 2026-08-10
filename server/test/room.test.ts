import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Room } from '../src/rooms/room';

const HOST = 1;
const MEMBER = 2;

function newRoomWithTrack(): Room {
	const room = new Room(1, HOST, 'Room');
	room.addMember(HOST); // Room itself does not auto-add its host; RoomStore.createRoom does
	room.addMember(MEMBER);
	room.addMusic(HOST, 100);
	return room;
}

test('only the host can add music, play, pause, next, previous, seek, and set the queue', () => {
	const room = newRoomWithTrack();

	assert.equal(room.addMusic(MEMBER, 200).ok, false);
	assert.equal(room.play(MEMBER).ok, false);
	assert.equal(room.pause(MEMBER).ok, false);
	assert.equal(room.next(MEMBER).ok, false);
	assert.equal(room.previous(MEMBER).ok, false);
	assert.equal(room.seek(MEMBER, 1000).ok, false);
	assert.equal(room.setQueue(MEMBER, [1, 2]).ok, false);
	assert.equal(room.playTrack(MEMBER, 0).ok, false);

	assert.equal(room.addMusic(HOST, 200).ok, true);
	assert.equal(room.play(HOST).ok, true);
	assert.equal(room.pause(HOST).ok, true);
	assert.equal(room.seek(HOST, 500).ok, true);
	assert.equal(room.setQueue(HOST, [3, 4]).ok, true);
});

test('addMusic starts playback from idle and appends without disrupting an active track', () => {
	const room = new Room(1, HOST, 'Room');
	assert.equal(room.currentIndex, null);
	assert.equal(room.status, 'IDLE');

	room.addMusic(HOST, 100);
	assert.equal(room.currentIndex, 0);
	assert.equal(room.status, 'PLAYING');
	assert.equal(room.currentMusicId, 100);

	room.addMusic(HOST, 200);
	assert.equal(room.currentIndex, 0); // unchanged: already playing
	assert.equal(room.currentMusicId, 100);
	assert.equal(room.playlist.size, 2);
});

test('setQueue rejects an empty list and otherwise replaces the queue and restarts playback', () => {
	const room = newRoomWithTrack();
	assert.equal(room.setQueue(HOST, []).ok, false);

	const result = room.setQueue(HOST, [10, 20, 30]);
	assert.equal(result.ok, true);
	assert.equal(room.currentIndex, 0);
	assert.equal(room.currentMusicId, 10);
	assert.equal(room.status, 'PLAYING');
});

test('next/previous move through the playlist and reject out-of-range moves', () => {
	const room = newRoomWithTrack();
	room.setQueue(HOST, [10, 20, 30]);

	assert.equal(room.previous(HOST).ok, false); // already at index 0

	assert.equal(room.next(HOST).ok, true);
	assert.equal(room.currentMusicId, 20);

	assert.equal(room.next(HOST).ok, true);
	assert.equal(room.currentMusicId, 30);

	assert.equal(room.next(HOST).ok, false); // no next track

	assert.equal(room.previous(HOST).ok, true);
	assert.equal(room.currentMusicId, 20);
});

test('play/pause on an empty playlist is rejected', () => {
	const room = new Room(1, HOST, 'Room');
	assert.equal(room.play(HOST).ok, false);
});

test('seek clamps negative positions to zero and requires an active track', () => {
	const room = new Room(1, HOST, 'Room');
	assert.equal(room.seek(HOST, 500).ok, false); // no active track yet

	room.addMusic(HOST, 100);
	const result = room.seek(HOST, -500);
	assert.equal(result.ok, true);
	assert.equal(room.playbackTimeMs, 0);
});

test('playback time advances while PLAYING but is frozen while PAUSED', async () => {
	const room = newRoomWithTrack(); // status: PLAYING, playbackTimeMs: 0
	await new Promise(resolve => setTimeout(resolve, 30));
	const whilePlaying = room.playbackTimeMs;
	assert.ok(whilePlaying !== null && whilePlaying >= 25);

	room.pause(HOST);
	const atPause = room.playbackTimeMs;
	await new Promise(resolve => setTimeout(resolve, 30));
	assert.equal(room.playbackTimeMs, atPause); // frozen while paused
});

test('advanceTrack moves to the next track, or marks the room idle at the end of the playlist', () => {
	const room = newRoomWithTrack();
	room.setQueue(HOST, [10, 20]);

	assert.equal(room.advanceTrack(), true);
	assert.equal(room.currentMusicId, 20);

	assert.equal(room.advanceTrack(), false);
	assert.equal(room.status, 'IDLE');
	assert.equal(room.currentIndex, null);
	assert.equal(room.currentMusicId, null);
});

test('member management: add/remove, host checks, and host reassignment', () => {
	const room = new Room(1, HOST, 'Room');
	room.addMember(HOST); // Room itself does not auto-add its host; RoomStore.createRoom does
	assert.equal(room.addMember(MEMBER), true);
	assert.equal(room.addMember(MEMBER), false); // already a member
	assert.deepEqual(room.memberIds().sort(), [HOST, MEMBER].sort());

	assert.equal(room.isHost(HOST), true);
	assert.equal(room.isHost(MEMBER), false);

	room.setHost(MEMBER);
	assert.equal(room.isHost(MEMBER), true);
	assert.equal(room.isHost(HOST), false);

	assert.equal(room.removeMember(HOST), true);
	assert.equal(room.removeMember(HOST), false); // already removed
	assert.deepEqual(room.memberIds(), [MEMBER]);
});

test('toState reflects the current room snapshot', () => {
	const room = newRoomWithTrack();
	const state = room.toState();

	assert.equal(state.id, 1);
	assert.equal(state.hostId, HOST);
	assert.deepEqual(state.memberIds.sort(), [HOST, MEMBER].sort());
	assert.equal(state.status, 'PLAYING');
	assert.equal(state.currentMusicId, 100);
	assert.equal(state.currentIndex, 0);
	assert.equal(state.playlist.length, 1);
	assert.equal(state.linkedVoteEventId, null);
});

test('reorderQueue is host-only and rejects an empty list', () => {
	const room = newRoomWithTrack();
	assert.equal(room.reorderQueue(MEMBER, [1, 2]).ok, false);
	assert.equal(room.reorderQueue(HOST, []).ok, false);
});

test('reorderQueue behaves like setQueue when the room is idle', () => {
	const room = new Room(1, HOST, 'Room');
	assert.equal(room.currentIndex, null);

	const result = room.reorderQueue(HOST, [10, 20, 30]);
	assert.equal(result.ok, true);
	assert.equal(room.currentIndex, 0);
	assert.equal(room.currentMusicId, 10);
	assert.equal(room.status, 'PLAYING');
	assert.deepEqual(room.playlist.snapshot().map(item => item.musicId), [10, 20, 30]);
});

test('reorderQueue keeps the currently playing track untouched and only reorders the upcoming tail', () => {
	const room = newRoomWithTrack(); // playing musicId 100 at index 0
	room.setQueue(HOST, [10, 20, 30]);
	room.next(HOST); // now playing 20, index 1

	const currentMusicId = room.currentMusicId;
	const currentIndex = room.currentIndex;
	const playbackTimeMs = room.playbackTimeMs;
	assert.equal(currentMusicId, 20);
	assert.equal(currentIndex, 1);

	// New ranking puts 30 first, and introduces a brand-new suggestion (40).
	const result = room.reorderQueue(HOST, [30, 40, 10]);
	assert.equal(result.ok, true);

	// Playback position/track are untouched (no restart).
	assert.equal(room.currentIndex, currentIndex);
	assert.equal(room.currentMusicId, currentMusicId);
	assert.equal(room.playbackTimeMs, playbackTimeMs);

	const ids = room.playlist.snapshot().map(item => item.musicId);
	// Already-played prefix (10, 20) is preserved, followed by the new ranking's
	// upcoming order (30, 40) with 10 excluded since it was already played.
	assert.deepEqual(ids, [10, 20, 30, 40]);
});

test('playTrack jumps to a valid queue index and rejects out-of-range indexes', () => {
	const room = newRoomWithTrack();
	room.addMusic(HOST, 200);
	room.addMusic(HOST, 300);

	assert.equal(room.playTrack(HOST, 2).ok, true);
	assert.equal(room.currentIndex, 2);
	assert.equal(room.status, 'PLAYING');

	assert.equal(room.playTrack(HOST, -1).ok, false);
	assert.equal(room.playTrack(HOST, 3).ok, false);
	assert.equal(room.currentIndex, 2);
});

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { Playlist } from '../src/rooms/playlist';

test('a new playlist is empty', () => {
	const playlist = new Playlist();
	assert.equal(playlist.isEmpty, true);
	assert.equal(playlist.size, 0);
	assert.equal(playlist.firstMusicId(), null);
	assert.deepEqual(playlist.snapshot(), []);
});

test('add appends items in order and tracks who added them', () => {
	const playlist = new Playlist();
	const item = playlist.add(10, 1);

	assert.equal(item.musicId, 10);
	assert.equal(item.addedByUserId, 1);
	assert.equal(typeof item.addedAt, 'number');

	playlist.add(20, 2);

	assert.equal(playlist.size, 2);
	assert.equal(playlist.isEmpty, false);
	assert.equal(playlist.firstMusicId(), 10);
	assert.deepEqual(playlist.items.map(i => i.musicId), [10, 20]);
});

test('replace clears the playlist and re-populates it from the given music ids', () => {
	const playlist = new Playlist();
	playlist.add(1, 1);
	playlist.add(2, 1);

	playlist.replace([5, 6, 7], 9);

	assert.equal(playlist.size, 3);
	assert.deepEqual(playlist.items.map(i => i.musicId), [5, 6, 7]);
	assert.ok(playlist.items.every(i => i.addedByUserId === 9));
});

test('snapshot returns a copy that does not mutate the internal list', () => {
	const playlist = new Playlist();
	playlist.add(1, 1);

	const snapshot = playlist.snapshot();
	snapshot.push({ musicId: 999, addedByUserId: 1, addedAt: Date.now() });

	assert.equal(playlist.size, 1);
	assert.equal(playlist.items.length, 1);
});

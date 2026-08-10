import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { Database } from '../src/database/database';
import { MusicDb } from '../src/database/music.db';

type QueryFn = typeof Database.query;

const originalQuery = Database.query;

afterEach(() => {
	Database.query = originalQuery;
});

test('getById returns the matching row, or null when no music matches', async () => {
	const musics = [{ id: 1, title: 'Song', artist_id: 2, genre_id: 3, file_path: 'song.mp3', duration: 180 }];
	Database.query = (async (_sql: string, ...args: any[]) => {
		const [id] = args;
		return musics.filter(music => music.id === id);
	}) as QueryFn;

	const found = await MusicDb.getById(1);
	assert.equal(found?.title, 'Song');
	assert.equal(await MusicDb.getById(404), null);
});

test('getAll returns every music row', async () => {
	const musics = [
		{ id: 1, title: 'B', artist_id: 1, genre_id: 1, file_path: 'b.mp3', duration: 100 },
		{ id: 2, title: 'A', artist_id: 1, genre_id: 1, file_path: 'a.mp3', duration: 200 },
	];
	Database.query = (async () => musics) as QueryFn;

	const all = await MusicDb.getAll();
	assert.deepEqual(all.map(music => music.id), [1, 2]);
});

test('getGenres returns every genre row', async () => {
	const genres = [{ id: 1, name: 'Rock', description: 'Rock music' }];
	Database.query = (async () => genres) as QueryFn;

	assert.deepEqual(await MusicDb.getGenres(), genres);
});

test('search wraps the query in wildcard percent signs for both title and artist name matching', async () => {
	let capturedArgs: any[] = [];
	Database.query = (async (_sql: string, ...args: any[]) => {
		capturedArgs = args;
		return [{ id: 1, title: 'Song', artist_id: 1, genre_id: 1, file_path: 'song.mp3', duration: 100, artist_name: 'Someone' }];
	}) as QueryFn;

	const results = await MusicDb.search('song');
	assert.deepEqual(capturedArgs, ['%song%', '%song%']);
	assert.equal(results[0].artist_name, 'Someone');
});

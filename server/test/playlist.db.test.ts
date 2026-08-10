import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { Database } from '../src/database/database';
import { PlaylistDb } from '../src/database/playlist.db';

type QueryFn = typeof Database.query;

const originalQuery = Database.query;

afterEach(() => {
	Database.query = originalQuery;
});

test('playlist edit permission follows owner, public license, and collaborator rules', async () => {
	const playlists = [
		{ id: 10, owner_id: 1, is_public: true, edit_policy: 'EVERYONE' },
		{ id: 11, owner_id: 1, is_public: true, edit_policy: 'COLLABORATORS' },
		{ id: 12, owner_id: 1, is_public: false, edit_policy: 'COLLABORATORS' },
	];
	const collaborators = [{ playlist_id: 11, user_id: 2 }];

	Database.query = (async (_sql: string, ...args: any[]) => {
		const [playlistId, userId] = args;
		const playlist = playlists.find(item => item.id === playlistId);
		const canEdit = Boolean(
			playlist &&
			(playlist.owner_id === userId ||
				(playlist.is_public && playlist.edit_policy === 'EVERYONE') ||
				collaborators.some(
					item => item.playlist_id === playlistId && item.user_id === userId,
				)),
		);
		return canEdit ? [{ found: 1 }] : [];
	}) as QueryFn;

	assert.equal(await PlaylistDb.canEdit(10, 99), true);
	assert.equal(await PlaylistDb.canEdit(11, 99), false);
	assert.equal(await PlaylistDb.canEdit(11, 2), true);
	assert.equal(await PlaylistDb.canEdit(12, 1), true);
	assert.equal(await PlaylistDb.canEdit(12, 2), false);
});

test('playlist view permission respects public and invited-private visibility', async () => {
	const playlists = [
		{ id: 80, owner_id: 1, is_public: true },
		{ id: 81, owner_id: 1, is_public: false },
	];
	const collaborators = [{ playlist_id: 81, user_id: 2 }];

	Database.query = (async (_sql: string, ...args: any[]) => {
		const [playlistId, userId] = args;
		const playlist = playlists.find(item => item.id === playlistId);
		const canView = Boolean(
			playlist &&
			(playlist.is_public ||
				playlist.owner_id === userId ||
				collaborators.some(
					item => item.playlist_id === playlistId && item.user_id === userId,
				)),
		);
		return canView ? [{ found: 1 }] : [];
	}) as QueryFn;

	assert.equal(await PlaylistDb.canView(80, 99), true);
	assert.equal(await PlaylistDb.canView(81, 99), false);
	assert.equal(await PlaylistDb.canView(81, 2), true);
	assert.equal(await PlaylistDb.canView(81, 1), true);
});

test('playlist collaborator invite is owner-only', async () => {
	const collaborators: Array<{ playlist_id: number; user_id: number }> = [];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT 1 AS found FROM playlists')) {
			const [playlistId, ownerId] = args;
			return playlistId === 20 && ownerId === 1 ? [{ found: 1 }] : [];
		}
		if (sql.includes('INSERT IGNORE INTO playlist_collaborators')) {
			const [playlistId, userId] = args;
			collaborators.push({ playlist_id: playlistId, user_id: userId });
			return [];
		}
		if (sql.includes('UPDATE playlists SET version = version + 1')) {
			return [];
		}
		throw new Error(`Unexpected SQL in collaborator test: ${sql}`);
	}) as QueryFn;

	assert.equal(await PlaylistDb.addCollaborator(20, 2, 5), false);
	assert.deepEqual(collaborators, []);

	assert.equal(await PlaylistDb.addCollaborator(20, 1, 5), true);
	assert.deepEqual(collaborators, [{ playlist_id: 20, user_id: 5 }]);
});

test('playlist license updates are owner-only and persisted as license entities', async () => {
	let playlistPolicy = 'EVERYONE';
	let licensePolicy = 'EVERYONE';

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT 1 AS found FROM playlists')) {
			const [playlistId, ownerId] = args;
			return playlistId === 40 && ownerId === 1 ? [{ found: 1 }] : [];
		}
		if (sql.includes('UPDATE playlists SET edit_policy')) {
			const [editPolicy] = args;
			playlistPolicy = editPolicy;
			return [];
		}
		if (sql.includes('INSERT INTO playlist_licenses')) {
			const [_playlistId, editPolicy] = args;
			licensePolicy = editPolicy;
			return [];
		}
		if (sql.includes('UPDATE playlists SET version = version + 1')) {
			return [];
		}
		throw new Error(`Unexpected SQL in license test: ${sql}`);
	}) as QueryFn;

	assert.equal(await PlaylistDb.setEditPolicy(40, 2, 'COLLABORATORS'), false);
	assert.equal(playlistPolicy, 'EVERYONE');
	assert.equal(licensePolicy, 'EVERYONE');

	assert.equal(await PlaylistDb.setEditPolicy(40, 1, 'COLLABORATORS'), true);
	assert.equal(playlistPolicy, 'COLLABORATORS');
	assert.equal(licensePolicy, 'COLLABORATORS');
});

test('playlist reorder rewrites contiguous track positions', async () => {
	const tracks = [
		{ playlist_id: 30, music_id: 1, position: 0 },
		{ playlist_id: 30, music_id: 2, position: 1 },
		{ playlist_id: 30, music_id: 3, position: 2 },
	];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT music_id FROM playlist_tracks')) {
			const [playlistId] = args;
			return tracks
				.filter(track => track.playlist_id === playlistId)
				.sort((a, b) => a.position - b.position)
				.map(track => ({ music_id: track.music_id }));
		}
		if (sql.includes('UPDATE playlist_tracks SET position')) {
			const [position, playlistId, musicId] = args;
			const track = tracks.find(
				item => item.playlist_id === playlistId && item.music_id === musicId,
			);
			if (track) track.position = position;
			return [];
		}
		if (sql.includes('UPDATE playlists SET version = version + 1')) {
			return [];
		}
		throw new Error(`Unexpected SQL in reorder test: ${sql}`);
	}) as QueryFn;

	assert.equal(await PlaylistDb.moveTrack(30, 1, 2), true);
	assert.deepEqual(
		tracks
			.sort((a, b) => a.position - b.position)
			.map(track => track.music_id),
		[2, 3, 1],
	);

	assert.equal(await PlaylistDb.moveTrack(30, 404, 0), false);
});

test('simultaneous playlist adds are serialized and produce unique positions', async () => {
	let version = 0;
	const tracks: Array<{ playlist_id: number; music_id: number; position: number }> = [];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT version FROM playlists')) {
			await new Promise(resolve => setTimeout(resolve, 5));
			return [{ version }];
		}
		if (sql.includes('SELECT COALESCE(MAX(position) + 1, 0) AS nextPosition')) {
			const [playlistId] = args;
			const maxPosition = tracks
				.filter(track => track.playlist_id === playlistId)
				.reduce((max, track) => Math.max(max, track.position), -1);
			return [{ nextPosition: maxPosition + 1 }];
		}
		if (sql.includes('INSERT IGNORE INTO playlist_tracks')) {
			const [playlistId, musicId, position] = args;
			tracks.push({
				playlist_id: playlistId,
				music_id: musicId,
				position,
			});
			return [];
		}
		if (sql.includes('UPDATE playlists SET version = version + 1')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL in simultaneous add test: ${sql}`);
	}) as QueryFn;

	const [first, second] = await Promise.all([
		PlaylistDb.addTrack(50, 101),
		PlaylistDb.addTrack(50, 102),
	]);

	assert.equal(first, true);
	assert.equal(second, true);
	assert.deepEqual(
		tracks
			.sort((a, b) => a.position - b.position)
			.map(track => [track.music_id, track.position]),
		[
			[101, 0],
			[102, 1],
		],
	);
	assert.equal(version, 2);
});

test('stale simultaneous playlist reorder is rejected by expected version', async () => {
	let version = 7;
	const tracks = [
		{ playlist_id: 60, music_id: 1, position: 0 },
		{ playlist_id: 60, music_id: 2, position: 1 },
		{ playlist_id: 60, music_id: 3, position: 2 },
	];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT version FROM playlists')) {
			return [{ version }];
		}
		if (sql.includes('SELECT music_id FROM playlist_tracks')) {
			const [playlistId] = args;
			return tracks
				.filter(track => track.playlist_id === playlistId)
				.sort((a, b) => a.position - b.position)
				.map(track => ({ music_id: track.music_id }));
		}
		if (sql.includes('UPDATE playlist_tracks SET position')) {
			const [position, playlistId, musicId] = args;
			const track = tracks.find(
				item => item.playlist_id === playlistId && item.music_id === musicId,
			);
			if (track) track.position = position;
			return [];
		}
		if (sql.includes('UPDATE playlists SET version = version + 1')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL in stale reorder test: ${sql}`);
	}) as QueryFn;

	const first = PlaylistDb.moveTrack(60, 1, 2, 7);
	const second = PlaylistDb.moveTrack(60, 2, 0, 7);
	const results = await Promise.allSettled([first, second]);

	assert.equal(results[0].status, 'fulfilled');
	assert.equal(results[1].status, 'rejected');
	assert.equal(version, 8);
	assert.deepEqual(
		tracks
			.sort((a, b) => a.position - b.position)
			.map(track => track.music_id),
		[2, 3, 1],
	);
});

test('stale simultaneous playlist remove is rejected by expected version', async () => {
	let version = 3;
	const tracks = [
		{ playlist_id: 70, music_id: 1, position: 0 },
		{ playlist_id: 70, music_id: 2, position: 1 },
		{ playlist_id: 70, music_id: 3, position: 2 },
	];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT version FROM playlists')) {
			return [{ version }];
		}
		if (sql.includes('DELETE FROM playlist_tracks')) {
			const [playlistId, musicId] = args;
			const index = tracks.findIndex(
				track => track.playlist_id === playlistId && track.music_id === musicId,
			);
			if (index >= 0) tracks.splice(index, 1);
			return [];
		}
		if (sql.includes('SELECT music_id FROM playlist_tracks')) {
			const [playlistId] = args;
			return tracks
				.filter(track => track.playlist_id === playlistId)
				.sort((a, b) => a.position - b.position)
				.map(track => ({ music_id: track.music_id }));
		}
		if (sql.includes('UPDATE playlist_tracks SET position')) {
			const [position, playlistId, musicId] = args;
			const track = tracks.find(
				item => item.playlist_id === playlistId && item.music_id === musicId,
			);
			if (track) track.position = position;
			return [];
		}
		if (sql.includes('UPDATE playlists SET version = version + 1')) {
			version += 1;
			return [];
		}
		throw new Error(`Unexpected SQL in stale remove test: ${sql}`);
	}) as QueryFn;

	const first = PlaylistDb.removeTrack(70, 1, 3);
	const second = PlaylistDb.removeTrack(70, 2, 3);
	const results = await Promise.allSettled([first, second]);

	assert.equal(results[0].status, 'fulfilled');
	assert.equal(results[1].status, 'rejected');
	assert.equal(version, 4);
	assert.deepEqual(
		tracks
			.sort((a, b) => a.position - b.position)
			.map(track => [track.music_id, track.position]),
		[
			[2, 0],
			[3, 1],
		],
	);
});

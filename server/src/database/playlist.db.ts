import { Database } from './database';
import { PlaylistLicenseModel, PlaylistModel, PlaylistTrackModel } from './database.models';
import { PoolConnection } from 'mariadb';

export interface PlaylistWithTrackCount extends PlaylistModel {
	track_count: number;
}

export interface PlaylistTrackWithMusic extends PlaylistTrackModel {
	title: string;
	artist_id: number;
	genre_id: number;
	duration: number;
	file_path: string;
}

export class PlaylistConflictError extends Error {
	constructor(message = 'Playlist was changed by another user') {
		super(message);
		this.name = 'PlaylistConflictError';
	}
}

export class PlaylistDb {
	private static locks = new Map<number, Promise<void>>();

	static async getByOwner(userId: number): Promise<PlaylistWithTrackCount[]> {
		return Database.query<PlaylistWithTrackCount>(
			`SELECT p.id, p.name, p.owner_id, p.is_public, p.version, p.created_at, p.updated_at,
			        COALESCE(pl.edit_policy, p.edit_policy, 'EVERYONE') AS edit_policy, COUNT(pt.id) AS track_count
			 FROM playlists p
			 LEFT JOIN playlist_licenses pl ON pl.playlist_id = p.id
			 LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
			 WHERE p.owner_id = ?
			 GROUP BY p.id
			 ORDER BY p.updated_at DESC`,
			userId,
		);
	}

	static async getAccessible(userId: number): Promise<PlaylistWithTrackCount[]> {
		return Database.query<PlaylistWithTrackCount>(
			`SELECT p.id, p.name, p.owner_id, p.is_public, p.version, p.created_at, p.updated_at,
			        COALESCE(pl.edit_policy, p.edit_policy, 'EVERYONE') AS edit_policy, COUNT(pt.id) AS track_count
			 FROM playlists p
			 LEFT JOIN playlist_licenses pl ON pl.playlist_id = p.id
			 LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
			 WHERE p.is_public = TRUE OR p.owner_id = ? OR p.id IN (
			   SELECT playlist_id FROM playlist_collaborators WHERE user_id = ?
			 )
			 GROUP BY p.id
			 ORDER BY p.updated_at DESC`,
			userId,
			userId,
		);
	}

	static async search(userId: number, query: string): Promise<PlaylistWithTrackCount[]> {
		return Database.query<PlaylistWithTrackCount>(
			`SELECT p.id, p.name, p.owner_id, p.is_public, p.version, p.created_at, p.updated_at,
			        COALESCE(pl.edit_policy, p.edit_policy, 'EVERYONE') AS edit_policy, COUNT(pt.id) AS track_count
			 FROM playlists p
			 LEFT JOIN playlist_licenses pl ON pl.playlist_id = p.id
			 LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id
			 WHERE (p.is_public = TRUE OR p.owner_id = ? OR p.id IN (
			   SELECT playlist_id FROM playlist_collaborators WHERE user_id = ?
			 )) AND p.name LIKE ?
			 GROUP BY p.id
			 ORDER BY p.updated_at DESC`,
			userId,
			userId,
			`%${query}%`,
		);
	}

	static async getById(id: number): Promise<PlaylistModel | null> {
		const rows = await Database.query<PlaylistModel>(
			`SELECT p.id, p.name, p.owner_id, p.is_public, p.version, p.created_at, p.updated_at,
			        COALESCE(pl.edit_policy, p.edit_policy, 'EVERYONE') AS edit_policy
			 FROM playlists p
			 LEFT JOIN playlist_licenses pl ON pl.playlist_id = p.id
			 WHERE p.id = ?`,
			id,
		);
		return rows.length > 0 ? rows[0] : null;
	}

	static async canView(playlistId: number, userId: number): Promise<boolean> {
		const rows = await Database.query<{ found: number }>(
			`SELECT 1 AS found FROM playlists WHERE id = ? AND (
				 is_public = TRUE OR owner_id = ? OR id IN (
					 SELECT playlist_id FROM playlist_collaborators WHERE user_id = ?
				 )
			 )
			 LIMIT 1`,
			playlistId,
			userId,
			userId,
		);
		return rows.length > 0;
	}

	static async getTracks(playlistId: number): Promise<PlaylistTrackWithMusic[]> {
		return Database.query<PlaylistTrackWithMusic>(
			`SELECT pt.*, m.title, m.artist_id, m.genre_id, m.duration, m.file_path, a.name as 'artist_name'
			 FROM playlist_tracks pt
			 JOIN musics m ON m.id = pt.music_id
			 Join artists a ON a.id = m.artist_id
			 WHERE pt.playlist_id = ?
			 ORDER BY pt.position`,
			playlistId,
		);
	}

	static async create(
		name: string,
		ownerId: number,
		isPublic: boolean,
		editPolicy: 'EVERYONE' | 'COLLABORATORS' = 'EVERYONE',
	): Promise<PlaylistModel | null> {
		const result = await Database.query<{ insertId: number }>(
			'INSERT INTO playlists (name, owner_id, is_public, edit_policy) VALUES (?, ?, ?, ?)',
			name,
			ownerId,
			isPublic,
			editPolicy,
		);
		// MariaDB returns insertId on the result meta
		const insertId = (result as any).insertId ?? (result[0] as any)?.insertId;
		if (!insertId) return null;
		await PlaylistDb.setLicense(insertId, editPolicy);
		return PlaylistDb.getById(insertId);
	}

	static async addTrack(playlistId: number, musicId: number, expectedVersion?: number): Promise<boolean> {
		return PlaylistDb.withPlaylistTransaction(playlistId, async conn => {
			await PlaylistDb.assertVersion(playlistId, expectedVersion, conn);
			// Two statements instead of a single `INSERT ... SELECT FROM` the same
			// table: under concurrency, InnoDB classifies that combined form as a
			// bulk insert and takes a table-wide auto-increment lock, which can
			// throw ER_AUTOINC_READ_FAILED (1467) across unrelated playlists even
			// though the row lock above already serializes access per playlist.
			const [{ nextPosition }] = await conn.query<{ nextPosition: number }[]>(
				'SELECT COALESCE(MAX(position) + 1, 0) AS nextPosition FROM playlist_tracks WHERE playlist_id = ?',
				[playlistId],
			);
			await conn.query(
				'INSERT IGNORE INTO playlist_tracks (playlist_id, music_id, position) VALUES (?, ?, ?)',
				[playlistId, musicId, nextPosition],
			);
			await PlaylistDb.bumpVersion(playlistId, conn);
			return true;
		});
	}

	static async removeTrack(playlistId: number, musicId: number, expectedVersion?: number): Promise<boolean> {
		return PlaylistDb.withPlaylistTransaction(playlistId, async conn => {
			await PlaylistDb.assertVersion(playlistId, expectedVersion, conn);
			await conn.query(
				'DELETE FROM playlist_tracks WHERE playlist_id = ? AND music_id = ?',
				[playlistId, musicId],
			);
			await PlaylistDb.compactPositions(playlistId, conn);
			await PlaylistDb.bumpVersion(playlistId, conn);
			return true;
		});
	}

	static async moveTrack(playlistId: number, musicId: number, newPosition: number, expectedVersion?: number): Promise<boolean> {
		return PlaylistDb.withPlaylistTransaction(playlistId, async conn => {
			await PlaylistDb.assertVersion(playlistId, expectedVersion, conn);
			const rows = await conn.query<{ music_id: number }[]>(
				'SELECT music_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position',
				[playlistId],
			);
			const orderedIds = rows.map(row => row.music_id);
			const currentIndex = orderedIds.indexOf(musicId);
			if (currentIndex < 0) return false;

			orderedIds.splice(currentIndex, 1);
			const targetIndex = Math.max(0, Math.min(newPosition, orderedIds.length));
			orderedIds.splice(targetIndex, 0, musicId);

			for (let i = 0; i < orderedIds.length; i++) {
				await conn.query(
					'UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND music_id = ?',
					[i, playlistId, orderedIds[i]],
				);
			}
			await PlaylistDb.bumpVersion(playlistId, conn);
			return true;
		});
	}

	static async setVisibility(playlistId: number, ownerId: number, isPublic: boolean, expectedVersion?: number): Promise<boolean> {
		return PlaylistDb.withPlaylistTransaction(playlistId, async conn => {
			await PlaylistDb.assertVersion(playlistId, expectedVersion, conn);
			await conn.query(
				'UPDATE playlists SET is_public = ? WHERE id = ? AND owner_id = ?',
				[isPublic, playlistId, ownerId],
			);
			await PlaylistDb.bumpVersion(playlistId, conn);
			return true;
		});
	}

	static async setEditPolicy(
		playlistId: number,
		ownerId: number,
		editPolicy: 'EVERYONE' | 'COLLABORATORS',
		expectedVersion?: number,
	): Promise<boolean> {
		return PlaylistDb.withPlaylistTransaction(playlistId, async conn => {
			await PlaylistDb.assertVersion(playlistId, expectedVersion, conn);
			const ownerRows = await conn.query<{ found: number }[]>(
				'SELECT 1 AS found FROM playlists WHERE id = ? AND owner_id = ? LIMIT 1',
				[playlistId, ownerId],
			);
			if (ownerRows.length === 0) return false;

			await conn.query(
				'UPDATE playlists SET edit_policy = ? WHERE id = ? AND owner_id = ?',
				[editPolicy, playlistId, ownerId],
			);
			await PlaylistDb.setLicense(playlistId, editPolicy, conn);
			await PlaylistDb.bumpVersion(playlistId, conn);
			return true;
		});
	}

	static async addCollaborator(playlistId: number, ownerId: number, userId: number, expectedVersion?: number): Promise<boolean> {
		return PlaylistDb.withPlaylistTransaction(playlistId, async conn => {
			await PlaylistDb.assertVersion(playlistId, expectedVersion, conn);
			const rows = await conn.query<{ found: number }[]>(
				'SELECT 1 AS found FROM playlists WHERE id = ? AND owner_id = ? LIMIT 1',
				[playlistId, ownerId],
			);
			if (rows.length === 0) return false;

			await conn.query(
				'INSERT IGNORE INTO playlist_collaborators (playlist_id, user_id) VALUES (?, ?)',
				[playlistId, userId],
			);
			await PlaylistDb.bumpVersion(playlistId, conn);
			return true;
		});
	}

	static async canEdit(playlistId: number, userId: number): Promise<boolean> {
		const rows = await Database.query<{ found: number }>(
			`SELECT 1 AS found FROM playlists p
			 LEFT JOIN playlist_licenses pl ON pl.playlist_id = p.id
			 WHERE p.id = ? AND (
				 p.owner_id = ? OR (p.is_public = TRUE AND COALESCE(pl.edit_policy, p.edit_policy, 'EVERYONE') = 'EVERYONE')
			 )
			 UNION
			 SELECT 1 AS found FROM playlist_collaborators WHERE playlist_id = ? AND user_id = ?
			 LIMIT 1`,
			playlistId,
			userId,
			playlistId,
			userId,
		);
		return rows.length > 0;
	}

	static async getCollaboratorIds(playlistId: number): Promise<number[]> {
		const rows = await Database.query<{ user_id: number }>(
			'SELECT user_id FROM playlist_collaborators WHERE playlist_id = ? ORDER BY user_id',
			playlistId,
		);
		return rows.map(r => r.user_id);
	}

	static async getMusicIds(playlistId: number): Promise<number[]> {
		const rows = await Database.query<{ music_id: number }>(
			'SELECT music_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position',
			playlistId,
		);
		return rows.map(r => r.music_id);
	}

	private static async compactPositions(playlistId: number, conn: PoolConnection): Promise<void> {
		const rows = await conn.query<{ music_id: number }[]>(
			'SELECT music_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position',
			[playlistId],
		);
		for (let i = 0; i < rows.length; i++) {
			await conn.query(
				'UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND music_id = ?',
				[i, playlistId, rows[i].music_id],
			);
		}
	}

	private static async setLicense(
		playlistId: number,
		editPolicy: PlaylistLicenseModel['edit_policy'],
		conn?: PoolConnection,
	): Promise<void> {
		const sql =
			`INSERT INTO playlist_licenses (playlist_id, edit_policy)
			 VALUES (?, ?)
			 ON DUPLICATE KEY UPDATE edit_policy = VALUES(edit_policy)`;
		if (conn) await conn.query(sql, [playlistId, editPolicy]);
		else await Database.query(sql, playlistId, editPolicy);
	}

	private static async assertVersion(playlistId: number, expectedVersion: number | undefined, conn: PoolConnection): Promise<void> {
		if (expectedVersion === undefined || expectedVersion === null) return;
		const rows = await conn.query<{ version: number }[]>(
			'SELECT version FROM playlists WHERE id = ?',
			[playlistId],
		);
		const currentVersion = rows[0]?.version;
		if (currentVersion !== expectedVersion) throw new PlaylistConflictError();
	}

	private static async bumpVersion(playlistId: number, conn: PoolConnection): Promise<void> {
		await conn.query(
			'UPDATE playlists SET version = version + 1 WHERE id = ?',
			[playlistId],
		);
	}

	private static async withPlaylistTransaction<T>(playlistId: number, action: (conn: PoolConnection) => Promise<T>): Promise<T> {
		const previous = PlaylistDb.locks.get(playlistId) ?? Promise.resolve();
		let release!: () => void;
		const current = new Promise<void>(resolve => { release = resolve; });
		const chained = previous.then(() => current);
		PlaylistDb.locks.set(playlistId, chained);
		await previous;
		try {
			return await Database.transaction(async conn => {
				// Row locking makes ordering/version mutations safe across server instances.
				if (Database.isConfigured) {
					await conn.query('SELECT id FROM playlists WHERE id = ? FOR UPDATE', [playlistId]);
				}
				return action(conn);
			});
		} finally {
			release();
			if (PlaylistDb.locks.get(playlistId) === chained) PlaylistDb.locks.delete(playlistId);
		}
	}
}

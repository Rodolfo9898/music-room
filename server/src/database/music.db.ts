import { Database } from './database';
import { GenreModel, MusicModel } from './database.models';

export interface MusicSearchResult extends MusicModel {
	artist_name?: string;
}

export class MusicDb {
	static async getById(id: number): Promise<MusicModel | null> {
		const rows = await Database.query<MusicModel>('SELECT id, title, artist_id, genre_id, file_path, duration FROM musics WHERE id = ?', id);
		return rows.length > 0 ? rows[0] : null;
	}

	static async getAll(): Promise<MusicModel[]> {
		return Database.query<MusicModel>('SELECT id, title, artist_id, genre_id, file_path, duration FROM musics ORDER BY title');
	}

	static async getGenres(): Promise<GenreModel[]> {
		return Database.query<GenreModel>(
			`SELECT id, name, description
			 FROM genres
			 ORDER BY name`,
		);
	}

	static async search(query: string): Promise<MusicSearchResult[]> {
		const pattern = `%${query}%`;
		return Database.query<MusicSearchResult>(
			`SELECT m.id, m.title, m.artist_id, m.genre_id, m.file_path, m.duration, a.name AS artist_name
			 FROM musics m
			 LEFT JOIN artists a ON a.id = m.artist_id
			 WHERE m.title LIKE ? OR a.name LIKE ?
			 ORDER BY m.title
			 LIMIT 50`,
			pattern,
			pattern,
		);
	}
}

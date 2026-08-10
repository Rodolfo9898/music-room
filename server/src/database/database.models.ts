export interface UserModel {
	id: number;
	email: string;
	password_hash: string | null; // null when account uses Google-only auth
	display_name: string;
	google_id: string | null;
	has_public_preference: boolean;
	public_info: string | null;
	friends_info: string | null;
	private_info: string | null;
	email_confirmation_token: string | null;
	password_reset_token: string | null;
}

// Backward-compatible alias used by account-related services/controllers.
export type AccountModel = UserModel;

export interface GenreModel {
	id: number;
	name: string;
	description: string;
}

export interface MusicModel {
	id: number;
	title: string;
	artist_id: number;
	genre_id: number;
	file_path: string;
	duration: number; // seconds
}

export interface PlaylistModel {
	id: number;
	name: string;
	owner_id: number;
	is_public: boolean;
	edit_policy: 'EVERYONE' | 'COLLABORATORS';
	version: number;
	created_at: string;
	updated_at: string;
}

export interface PlaylistLicenseModel {
	id: number;
	playlist_id: number;
	edit_policy: 'EVERYONE' | 'COLLABORATORS';
	created_at: string;
	updated_at: string;
}

export interface PlaylistTrackModel {
	id: number;
	playlist_id: number;
	music_id: number;
	position: number;
	added_at: string;
}

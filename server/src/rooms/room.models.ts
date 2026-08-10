import { MusicChunkPayload } from '../web-socket/music.service';

export type PlaybackStatus = 'IDLE' | 'PLAYING' | 'PAUSED';

export interface PlaylistItem {
	musicId: number;
	addedByUserId: number;
	addedAt: number;
}

export interface RoomState {
	id: number;
	name: string;
	hostId: number;
	memberIds: number[];
	playlist: PlaylistItem[];
	status: PlaybackStatus;
	currentMusicId: number | null;
	currentIndex: number | null;
	playbackTimeMs: number | null;
	playbackUpdatedAtMs: number | null;
	linkedVoteEventId: number | null;
}

export interface ActionResult {
	success: boolean;
	message: string | null;
}

export type StoreResult =
	| { ok: true; message?: string }
	| { ok: false; message: string };

export type RoomEvent =
	| { type: 'STATE'; state: RoomState }
	| { type: 'CHUNK'; chunk: MusicChunkPayload }
	| { type: 'CLOSED'; roomId: number };

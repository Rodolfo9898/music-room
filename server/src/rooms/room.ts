import { Playlist } from './playlist';
import { PlaybackStatus, RoomState, StoreResult } from './room.models';
import { MusicChunkPayload } from '../web-socket/music.service';

export class Room {
	readonly id: number;
	readonly name: string;
	hostId: number;
	readonly playlist: Playlist;
	readonly createdAt: number;
	readonly hostDeviceKey: string;

	private readonly members = new Map<number, number>();
	private _linkedVoteEventId: number | null = null;
	private _status: PlaybackStatus = 'IDLE';
	private _currentIndex: number | null = null;
	private _playbackIterator: AsyncIterator<MusicChunkPayload> | null = null;
	private _trackBuffer: MusicChunkPayload[] = [];
	private _playbackTimeMs: number | null = null;
	private _playbackUpdatedAtMs: number | null = null;

	constructor(id: number, hostUserId: number, name: string, hostDeviceKey = 'unknown') {
		this.id = id;
		this.hostId = hostUserId;
		this.name = name;
		this.playlist = new Playlist();
		this.createdAt = Date.now();
		this.hostDeviceKey = hostDeviceKey;
	}

	get status(): PlaybackStatus {
		return this._status;
	}

	get currentIndex(): number | null {
		return this._currentIndex;
	}

	get currentMusicId(): number | null {
		if (this._currentIndex === null) return null;
		return this.playlist.items[this._currentIndex]?.musicId ?? null;
	}

	get playbackIterator(): AsyncIterator<MusicChunkPayload> | null {
		return this._playbackIterator;
	}

	get playbackTimeMs(): number | null {
		return this.playbackSnapshot().playbackTimeMs;
	}

	get playbackUpdatedAtMs(): number | null {
		return this.playbackSnapshot().playbackUpdatedAtMs;
	}

	effectivePlaybackTimeMs(): number | null {
		return this.playbackSnapshot().playbackTimeMs;
	}

	get linkedVoteEventId(): number | null {
		return this._linkedVoteEventId;
	}

	setLinkedVoteEvent(eventId: number | null): void {
		this._linkedVoteEventId = eventId;
	}

	isHost(userId: number): boolean {
		return this.hostId === userId;
	}

	setHost(userId: number): void {
		this.hostId = userId;
	}

	memberIds(): number[] {
		return Array.from(this.members.keys());
	}

	addMember(userId: number): boolean {
		if (this.members.has(userId)) return false;
		this.members.set(userId, 1);
		return true;
	}

	removeMember(userId: number): boolean {
		return this.members.delete(userId);
	}

	addMusic(userId: number, musicId: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can add music' };
		const wasIdle = this._currentIndex === null;
		this.playlist.add(musicId, userId);
		if (wasIdle) {
			this._currentIndex = 0;
			this._trackBuffer = [];
			this.setPlaybackTime(0);
			this._status = 'PLAYING';
		}
		return { ok: true };
	}

	setQueue(userId: number, musicIds: number[]): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can set the queue' };
		if (musicIds.length === 0) return { ok: false, message: 'Music list is empty' };
		this.playlist.replace(musicIds, userId);
		this._currentIndex = 0;
		this._trackBuffer = [];
		this.setPlaybackTime(0);
		this._status = 'PLAYING';
		return { ok: true };
	}

	// Reorders the queue to follow `musicIds` (e.g. a live vote ranking) without
	// restarting playback: any already-played/currently-playing items are left
	// untouched, and only the upcoming tail is replaced. If nothing is currently
	// playing, this behaves like `setQueue` and starts playback fresh.
	reorderQueue(userId: number, musicIds: number[]): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can reorder the queue' };
		if (musicIds.length === 0) return { ok: false, message: 'Music list is empty' };

		if (this._currentIndex === null) {
			return this.setQueue(userId, musicIds);
		}

		const items = this.playlist.items;
		const playedItems = items.slice(0, this._currentIndex + 1);
		const playedIds = new Set(playedItems.map(item => item.musicId));
		const upcomingIds = musicIds.filter(musicId => !playedIds.has(musicId));
		const now = Date.now();
		const newItems = [
			...playedItems,
			...upcomingIds.map(musicId => ({ musicId, addedByUserId: userId, addedAt: now })),
		];
		this.playlist.replaceAll(newItems);
		return { ok: true };
	}

	play(userId: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can play' };
		if (this.playlist.isEmpty) return { ok: false, message: 'Playlist is empty' };
		if (this._currentIndex === null) {
			this._currentIndex = 0;
		}
		const now = Date.now();
		const currentTime = this.playbackSnapshot(now).playbackTimeMs ?? 0;
		this.setPlaybackTime(currentTime, now);
		this._status = 'PLAYING';
		return { ok: true };
	}

	pause(userId: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can pause' };
		const now = Date.now();
		const currentTime = this.playbackSnapshot(now).playbackTimeMs;
		this._status = 'PAUSED';
		this.setPlaybackTime(currentTime, now);
		return { ok: true };
	}

	next(userId: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can skip' };
		const items = this.playlist.items;
		if (items.length === 0) return { ok: false, message: 'Playlist is empty' };
		const nextIndex = (this._currentIndex ?? -1) + 1;
		if (nextIndex >= items.length) return { ok: false, message: 'No next track' };
		this._currentIndex = nextIndex;
		this._trackBuffer = [];
		this.setPlaybackTime(0);
		this._status = 'PLAYING';
		return { ok: true };
	}

	previous(userId: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can rewind' };
		if (this._currentIndex === null || this._currentIndex <= 0) {
			return { ok: false, message: 'No previous track' };
		}
		this._currentIndex -= 1;
		this._trackBuffer = [];
		this.setPlaybackTime(0);
		this._status = 'PLAYING';
		return { ok: true };
	}

	playTrack(userId: number, index: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can change the track' };
		const items = this.playlist.items;
		if (index < 0 || index >= items.length) return { ok: false, message: 'Invalid track index' };
		this._currentIndex = index;
		this._trackBuffer = [];
		this.setPlaybackTime(0);
		this._status = 'PLAYING';
		return { ok: true };
	}

	seek(userId: number, positionMs: number): StoreResult {
		if (!this.isHost(userId)) return { ok: false, message: 'Only the host can seek' };
		if (this._currentIndex === null) return { ok: false, message: 'No active track' };
		const clamped = Math.max(0, positionMs);
		this.setPlaybackTime(clamped);
		return { ok: true };
	}

	setPlaybackIterator(iterator: AsyncIterator<MusicChunkPayload> | null): void {
		this._playbackIterator = iterator;
	}

	resetTrack(playbackTimeMs: number): void {
		this._trackBuffer = [];
		this.setPlaybackTime(playbackTimeMs);
	}

	appendChunk(chunk: MusicChunkPayload): void {
		this._trackBuffer.push(chunk);
	}

	getTrackBufferSnapshot(): MusicChunkPayload[] {
		return this._trackBuffer.slice();
	}

	advanceTrack(): boolean {
		const items = this.playlist.items;
		const nextIndex = (this._currentIndex ?? -1) + 1;
		if (nextIndex >= items.length) {
			this._currentIndex = null;
			this._status = 'IDLE';
			this._trackBuffer = [];
			this.setPlaybackTime(null);
			return false;
		}
		this._currentIndex = nextIndex;
		this._trackBuffer = [];
		this.setPlaybackTime(0);
		return true;
	}

	markIdle(): void {
		this._status = 'IDLE';
		this._currentIndex = null;
		this._trackBuffer = [];
		this.setPlaybackTime(null);
	}

	toState(): RoomState {
		const playback = this.playbackSnapshot();
		return {
			id: this.id,
			name: this.name,
			hostId: this.hostId,
			memberIds: this.memberIds(),
			playlist: this.playlist.snapshot(),
			status: this._status,
			currentMusicId: this.currentMusicId,
			currentIndex: this._currentIndex,
			playbackTimeMs: playback.playbackTimeMs,
			playbackUpdatedAtMs: playback.playbackUpdatedAtMs,
			linkedVoteEventId: this._linkedVoteEventId,
		};
	}

	private setPlaybackTime(playbackTimeMs: number | null, now = Date.now()): void {
		if (playbackTimeMs === null) {
			this._playbackTimeMs = null;
			this._playbackUpdatedAtMs = null;
			return;
		}
		this._playbackTimeMs = Math.max(0, playbackTimeMs);
		this._playbackUpdatedAtMs = now;
	}

	private playbackSnapshot(now = Date.now()): { playbackTimeMs: number | null; playbackUpdatedAtMs: number | null } {
		if (this._playbackTimeMs === null || this._playbackUpdatedAtMs === null) {
			return { playbackTimeMs: null, playbackUpdatedAtMs: null };
		}

		if (this._status !== 'PLAYING') {
			return {
				playbackTimeMs: this._playbackTimeMs,
				playbackUpdatedAtMs: this._playbackUpdatedAtMs,
			};
		}

		return {
			playbackTimeMs: Math.max(0, this._playbackTimeMs + (now - this._playbackUpdatedAtMs)),
			playbackUpdatedAtMs: now,
		};
	}
}

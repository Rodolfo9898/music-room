import { EventEmitter } from 'node:events';
import { Room } from './room';
import {
	ActionResult,
	RoomEvent,
	RoomState,
	StoreResult,
} from './room.models';
import { MusicDb } from '../database/music.db';
import { MusicService, MusicChunkPayload } from '../web-socket/music.service';
import { VoteEventDb } from '../database/vote-event.db';
import { publishVoteEventUpdate, subscribeToVoteEvent } from '../web-socket/vote.events';

const EVENT_CHANNEL = 'event';
const ROOMS_CHANNEL = 'rooms_changed';
const LEAVE_GRACE_MS = 60_000;

interface VoteEventLink {
	eventId: number;
	iterator: AsyncIterator<number>;
}

export class RoomStore {
	private readonly rooms = new Map<number, Room>();
	private readonly emitters = new Map<number, EventEmitter>();
	private readonly globalEmitter = new EventEmitter();
	private readonly pendingLeaves = new Map<string, NodeJS.Timeout>();
	private readonly voteEventLinks = new Map<number, VoteEventLink>();
	private nextRoomId = 1;

	constructor() {
		this.globalEmitter.setMaxListeners(0);
	}

	createRoom(hostUserId: number, name: string, hostDeviceKey = 'unknown'): { room: Room; leftRoomIds: number[] } {
		// A user can only actively belong to one room at a time; leave any
		// other room(s) they're still a member of before creating this one.
		const leftRoomIds = this.leaveOtherRooms(hostUserId);
		const id = this.nextRoomId++;
		const room = new Room(id, hostUserId, name, hostDeviceKey);
		this.rooms.set(id, room);
		const emitter = new EventEmitter();
		emitter.setMaxListeners(0);
		this.emitters.set(id, emitter);
		room.addMember(hostUserId);
		this.broadcastRoomsList();
		return { room, leftRoomIds };
	}

	// Removes `userId` from every room they currently belong to, except
	// `exceptRoomId` if given. Reuses `leaveRoom` so host-reassignment and
	// room-close-when-empty behavior stay consistent. Returns the ids of the
	// rooms the user was removed from.
	leaveOtherRooms(userId: number, exceptRoomId?: number): number[] {
		const left: number[] = [];
		for (const room of Array.from(this.rooms.values())) {
			if (room.id === exceptRoomId) continue;
			if (!room.memberIds().includes(userId)) continue;
			this.leaveRoom(room.id, userId);
			left.push(room.id);
		}
		return left;
	}

	getRoom(roomId: number): Room | null {
		return this.rooms.get(roomId) ?? null;
	}

	listRooms(): RoomState[] {
		return Array.from(this.rooms.values()).map(room => room.toState());
	}

	joinRoom(roomId: number, userId: number): { room: Room; leftRoomIds: number[] } {
		const room = this.rooms.get(roomId);
		if (!room) throw new Error(`Room ${roomId} not found`);
		this.cancelPendingLeave(roomId, userId);
		// A user can only actively belong to one room at a time; leave any
		// other room(s) they're still a member of before joining this one.
		const leftRoomIds = this.leaveOtherRooms(userId, roomId);
		const wasEmpty = room.memberIds().length === 0;
		const added = room.addMember(userId);
		if (added) {
			if (wasEmpty) room.setHost(userId);
			this.broadcastState(room);
			this.broadcastRoomsList();
		}
		return { room, leftRoomIds };
	}

	// Schedules a member's removal after a grace period, allowing a brief
	// disconnect (e.g. network blip) to be reconnected without losing room
	// membership or, if applicable, host status. Cancelled by
	// `cancelPendingLeave` if the user reconnects in time.
	schedulePendingLeave(roomId: number, userId: number, delayMs: number = LEAVE_GRACE_MS): void {
		const key = this.pendingLeaveKey(roomId, userId);
		const existing = this.pendingLeaves.get(key);
		if (existing) clearTimeout(existing);
		const timer = setTimeout(() => {
			this.pendingLeaves.delete(key);
			this.leaveRoom(roomId, userId);
		}, delayMs);
		timer.unref?.();
		this.pendingLeaves.set(key, timer);
	}

	cancelPendingLeave(roomId: number, userId: number): void {
		const key = this.pendingLeaveKey(roomId, userId);
		const timer = this.pendingLeaves.get(key);
		if (!timer) return;
		clearTimeout(timer);
		this.pendingLeaves.delete(key);
	}

	private pendingLeaveKey(roomId: number, userId: number): string {
		return `${roomId}:${userId}`;
	}

	private clearPendingLeavesForRoom(roomId: number): void {
		const prefix = `${roomId}:`;
		for (const key of this.pendingLeaves.keys()) {
			if (!key.startsWith(prefix)) continue;
			const timer = this.pendingLeaves.get(key);
			if (timer) clearTimeout(timer);
			this.pendingLeaves.delete(key);
		}
	}

	leaveRoom(roomId: number, userId: number): void {
		this.cancelPendingLeave(roomId, userId);
		const room = this.rooms.get(roomId);
		if (!room) return;
		const removed = room.removeMember(userId);
		if (!removed) return;

		const remaining = room.memberIds();
		if (remaining.length === 0) {
			this.closeRoom(room);
			return;
		}

		if (userId === room.hostId) {
			room.setHost(remaining[0]);
		}
		this.broadcastState(room);
		this.broadcastRoomsList();
	}

	deleteRoom(roomId: number, userId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		if (!room.isHost(userId)) return { ok: false, message: 'Only the host can delete the room' };
		this.closeRoom(room);
		return { ok: true };
	}

	transferHost(roomId: number, userId: number, targetUserId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		if (!room.isHost(userId)) return { ok: false, message: 'Only the host can transfer ownership' };
		if (!room.memberIds().includes(targetUserId)) {
			return { ok: false, message: 'Target user is not a member of this room' };
		}
		room.setHost(targetUserId);
		this.broadcastState(room);
		this.broadcastRoomsList();
		return { ok: true };
	}

	addMusic(roomId: number, userId: number, musicId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const wasPlaying = room.playbackIterator !== null;
		const result = room.addMusic(userId, musicId);
		if (!result.ok) return result;
		this.broadcastState(room);
		if (!wasPlaying && room.status === 'PLAYING' && room.currentMusicId !== null) {
			void this.startPlayback(room);
		}
		this.suggestToLinkedVoteEvent(room, userId, musicId);
		return result;
	}

	setQueue(roomId: number, userId: number, musicIds: number[]): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const result = room.setQueue(userId, musicIds);
		if (!result.ok) return result;
		this.stopPlayback(room);
		void this.startPlayback(room);
		return result;
	}

	play(roomId: number, userId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const result = room.play(userId);
		if (!result.ok) return result;
		if (room.playbackIterator) {
			this.broadcastState(room);
			return result;
		}
		void this.startPlayback(room);
		return result;
	}

	pause(roomId: number, userId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const result = room.pause(userId);
		if (result.ok) {
			this.broadcastState(room);
		}
		return result;
	}

	next(roomId: number, userId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const result = room.next(userId);
		if (!result.ok) return result;
		this.stopPlayback(room);
		void this.startPlayback(room);
		return result;
	}

	previous(roomId: number, userId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const result = room.previous(userId);
		if (!result.ok) return result;
		this.stopPlayback(room);
		void this.startPlayback(room);
		return result;
	}

	seek(roomId: number, userId: number, positionMs: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		const result = room.seek(userId, positionMs);
		if (result.ok) this.broadcastState(room);
		return result;
	}

	async linkVoteEvent(roomId: number, userId: number, eventId: number): Promise<StoreResult> {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		if (!room.isHost(userId)) return { ok: false, message: 'Only the host can link a vote event' };
		const canView = await VoteEventDb.canView(eventId, userId);
		if (!canView) return { ok: false, message: 'Vote event not found or not accessible' };

		this.stopVoteEventSync(room.id);
		room.setLinkedVoteEvent(eventId);
		this.broadcastState(room);
		await this.syncQueueFromVoteEvent(room, eventId);
		void this.startVoteEventSync(room, eventId);
		return { ok: true };
	}

	unlinkVoteEvent(roomId: number, userId: number): StoreResult {
		const room = this.rooms.get(roomId);
		if (!room) return { ok: false, message: `Room ${roomId} not found` };
		if (!room.isHost(userId)) return { ok: false, message: 'Only the host can unlink a vote event' };
		room.setLinkedVoteEvent(null);
		this.stopVoteEventSync(room.id);
		this.broadcastState(room);
		return { ok: true };
	}

	// Force-unlinks every room currently linked to `eventId`, e.g. when that
	// event has just been deleted. Unlike unlinkVoteEvent this isn't
	// host-gated since it's triggered by the event's deletion, not a room
	// action.
	unlinkRoomsForVoteEvent(eventId: number): void {
		for (const room of Array.from(this.rooms.values())) {
			if (room.linkedVoteEventId !== eventId) continue;
			room.setLinkedVoteEvent(null);
			this.stopVoteEventSync(room.id);
			this.broadcastState(room);
		}
	}

	// Best-effort: if the room is linked to a vote event, submit the newly
	// queued track as a suggestion. Ineligibility (e.g. invite-only events the
	// user isn't part of) is swallowed - the queue add itself already succeeded.
	private suggestToLinkedVoteEvent(room: Room, userId: number, musicId: number): void {
		const eventId = room.linkedVoteEventId;
		if (eventId === null) return;
		void VoteEventDb.suggest(eventId, userId, musicId)
			.then(() => publishVoteEventUpdate(eventId))
			.catch(() => { /* not eligible to suggest for this event; ignore */ });
	}

	// Consumes vote-event updates for a linked room and re-syncs the queue on
	// each change. Stops once superseded (relinked/unlinked) or the room closes.
	private async startVoteEventSync(room: Room, eventId: number): Promise<void> {
		const iterable = subscribeToVoteEvent(eventId);
		const iterator = iterable[Symbol.asyncIterator]();
		this.voteEventLinks.set(room.id, { eventId, iterator });
		try {
			while (true) {
				const next = await iterator.next();
				if (next.done) return;
				if (this.voteEventLinks.get(room.id)?.iterator !== iterator) return;
				if (!this.rooms.has(room.id)) return;
				await this.syncQueueFromVoteEvent(room, eventId);
			}
		} catch (err) {
			console.error('Vote event sync error:', err);
		}
	}

	private async syncQueueFromVoteEvent(room: Room, eventId: number): Promise<void> {
		if (room.linkedVoteEventId !== eventId) return;
		const tracks = await VoteEventDb.getTracks(eventId);
		if (tracks.length === 0) return;
		const musicIds = tracks.map(track => track.music_id);
		const wasPlaying = room.playbackIterator !== null;
		const result = room.reorderQueue(room.hostId, musicIds);
		if (!result.ok) return;
		this.broadcastState(room);
		if (!wasPlaying && room.status === 'PLAYING' && room.currentMusicId !== null) {
			void this.startPlayback(room);
		}
	}

	private stopVoteEventSync(roomId: number): void {
		const link = this.voteEventLinks.get(roomId);
		if (!link) return;
		this.voteEventLinks.delete(roomId);
		void link.iterator.return?.(undefined);
	}

	subscribe(roomId: number): AsyncIterableIterator<RoomEvent> {
		const emitter = this.emitters.get(roomId);
		const room = this.rooms.get(roomId);
		if (!emitter || !room) throw new Error(`Room ${roomId} not found`);

		const queue: RoomEvent[] = [];
		const waiters: Array<(value: IteratorResult<RoomEvent>) => void> = [];
		let closed = false;

		const onEvent = (roomEvent: RoomEvent) => {
			if (closed) return;
			const waiter = waiters.shift();
			if (waiter) waiter({ value: roomEvent, done: false });
			else queue.push(roomEvent);
			if (roomEvent.type === 'CLOSED') closed = true;
		};

		const buffered = room.getTrackBufferSnapshot();
		emitter.on(EVENT_CHANNEL, onEvent);
		for (const chunk of buffered) {
			queue.push({ type: 'CHUNK', chunk });
		}

		const cleanup = () => {
			emitter.off(EVENT_CHANNEL, onEvent);
			while (waiters.length) {
				const waiter = waiters.shift();
				waiter?.({ value: undefined as never, done: true });
			}
		};

		const iterator: AsyncIterableIterator<RoomEvent> = {
			next(): Promise<IteratorResult<RoomEvent>> {
				if (queue.length) {
					return Promise.resolve({ value: queue.shift()!, done: false });
				}
				if (closed) {
					return Promise.resolve({ value: undefined as never, done: true });
				}
				return new Promise(resolve => waiters.push(resolve));
			},
			return(): Promise<IteratorResult<RoomEvent>> {
				closed = true;
				cleanup();
				return Promise.resolve({ value: undefined as never, done: true });
			},
			throw(err: unknown): Promise<IteratorResult<RoomEvent>> {
				closed = true;
				cleanup();
				return Promise.reject(err);
			},
			[Symbol.asyncIterator]() {
				return this;
			},
		};
		return iterator;
	}

	subscribeRooms(): AsyncIterableIterator<RoomState[]> {
		const queue: RoomState[][] = [];
		const waiters: Array<(value: IteratorResult<RoomState[]>) => void> = [];
		let closed = false;

		const onRooms = (rooms: RoomState[]) => {
			if (closed) return;
			const waiter = waiters.shift();
			if (waiter) waiter({ value: rooms, done: false });
			else queue.push(rooms);
		};

		this.globalEmitter.on(ROOMS_CHANNEL, onRooms);

		const cleanup = () => {
			this.globalEmitter.off(ROOMS_CHANNEL, onRooms);
			while (waiters.length) {
				const waiter = waiters.shift();
				waiter?.({ value: undefined as never, done: true });
			}
		};

		const iterator: AsyncIterableIterator<RoomState[]> = {
			next(): Promise<IteratorResult<RoomState[]>> {
				if (queue.length) return Promise.resolve({ value: queue.shift()!, done: false });
				if (closed) return Promise.resolve({ value: undefined as never, done: true });
				return new Promise(resolve => waiters.push(resolve));
			},
			return(): Promise<IteratorResult<RoomState[]>> {
				closed = true;
				cleanup();
				return Promise.resolve({ value: undefined as never, done: true });
			},
			throw(err: unknown): Promise<IteratorResult<RoomState[]>> {
				closed = true;
				cleanup();
				return Promise.reject(err);
			},
			[Symbol.asyncIterator]() { return this; },
		};
		return iterator;
	}

	buildActionResult(result: StoreResult): ActionResult {
		if (result.ok) return { success: true, message: null };
		return { success: false, message: result.message };
	}

	private broadcastRoomsList(): void {
		this.globalEmitter.emit(ROOMS_CHANNEL, this.listRooms());
	}

	private broadcastState(room: Room): void {
		const emitter = this.emitters.get(room.id);
		if (!emitter) return;
		const roomEvent: RoomEvent = { type: 'STATE', state: room.toState() };
		emitter.emit(EVENT_CHANNEL, roomEvent);
	}

	private broadcastChunk(room: Room, chunk: MusicChunkPayload): void {
		const emitter = this.emitters.get(room.id);
		if (!emitter) return;
		emitter.emit(EVENT_CHANNEL, { type: 'CHUNK', chunk });
	}

	private async startPlayback(room: Room): Promise<void> {
		const musicId = room.currentMusicId;
		if (musicId === null) return;
		const music = await MusicDb.getById(musicId);
		if (!music) {
			room.markIdle();
			this.broadcastState(room);
			return;
		}
		const playbackTimeMs = room.effectivePlaybackTimeMs() ?? 0;
		room.resetTrack(playbackTimeMs);
		const iterator = MusicService
			.streamFile(music.file_path)
			[Symbol.asyncIterator]();
		room.setPlaybackIterator(iterator);
		this.broadcastState(room);
		void this.runPlaybackLoop(room, iterator, music.duration * 1000);
	}

	private async runPlaybackLoop(
		room: Room,
		iterator: AsyncIterator<MusicChunkPayload>,
		trackDurationMs: number,
	): Promise<void> {
		try {
			while (true) {
				if (room.playbackIterator !== iterator) return;
				while (room.playbackIterator === iterator && room.status === 'PAUSED') {
					await new Promise(resolve => setTimeout(resolve, 100));
				}
				if (room.playbackIterator !== iterator) return;
				const next = await iterator.next();
				if (room.playbackIterator !== iterator) return;
				if (next.done) break;
				const chunk = next.value;
				room.appendChunk(chunk);
				this.broadcastChunk(room, chunk);
				if (chunk.finished) break;
			}
			if (room.playbackIterator !== iterator) return;

			while (true) {
				if (room.playbackIterator !== iterator) return;
				const playbackTimeMs = room.effectivePlaybackTimeMs() ?? 0;
				const remaining = trackDurationMs - playbackTimeMs;
				if (remaining <= 0) break;
				await new Promise(resolve => setTimeout(resolve, Math.min(remaining, 250)));
			}
			if (room.playbackIterator !== iterator) return;

			room.setPlaybackIterator(null);
			const advanced = room.advanceTrack();
			if (advanced) {
				await this.startPlayback(room);
			} else {
				this.broadcastState(room);
			}
		} catch (err) {
			console.error('Playback loop error:', err);
			room.setPlaybackIterator(null);
			room.markIdle();
			this.broadcastState(room);
		} finally {
			try {
				await iterator.return?.(undefined);
			} catch (err) {
				console.error('Playback iterator close error:', err);
			}
		}
	}

	private stopPlayback(room: Room): void {
		const iterator = room.playbackIterator;
		if (!iterator) return;
		room.setPlaybackIterator(null);
		void iterator.return?.(undefined);
	}

	private closeRoom(room: Room): void {
		this.stopPlayback(room);
		this.stopVoteEventSync(room.id);
		this.clearPendingLeavesForRoom(room.id);
		const emitter = this.emitters.get(room.id);
		this.rooms.delete(room.id);
		this.emitters.delete(room.id);
		if (emitter) {
			const roomEvent: RoomEvent = { type: 'CLOSED', roomId: room.id };
			emitter.emit(EVENT_CHANNEL, roomEvent);
			emitter.removeAllListeners();
		}
		this.broadcastRoomsList();
	}
}

export const roomStore = new RoomStore();

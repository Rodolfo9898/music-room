import { MusicDb } from '../database/music.db';
import { PlaylistConflictError, PlaylistDb } from '../database/playlist.db';
import { AccountDb } from '../database/account.db';
import { roomStore } from '../rooms/room.store';
import { RoomState, StoreResult } from '../rooms/room.models';
import { SubscriptionContext } from './subscription';
import { publishPlaylistUpdate, subscribeToPlaylist } from './playlist.events';
import { VoteEventDb, VoteLocation, VotePolicy } from '../database/vote-event.db';
import { publishVoteEventUpdate, subscribeToVoteEvent, subscribeToVoteEvents } from './vote.events';
import { GeocodedLocation, GeocodingService } from '../utils/geocoding.service';

const MIN_RADIUS_METERS = 100;
const MAX_RADIUS_METERS = 10000;

function requireUser(context: SubscriptionContext): { id: number } {
	if (!context.user) throw new Error('No user attached to connection');
	return context.user;
}

async function effectiveController(roomId: number, userId: number, context: SubscriptionContext): Promise<number> {
	const room = roomStore.getRoom(roomId);
	if (!room) return userId;
	return await AccountDb.canControlOwnerDevice(room.hostId, room.hostDeviceKey, userId)
		? room.hostId
		: userId;
}

function wrapAction(result: StoreResult, roomState: RoomState | null) {
	if (result.ok) return { success: true, message: result.message ?? null, room: roomState };
	return { success: false, message: result.message, room: roomState };
}

async function withPlaylistConflict<T>(action: () => Promise<T>): Promise<T> {
	try {
		return await action();
	} catch (err) {
		if (err instanceof PlaylistConflictError) {
			throw new Error('Playlist changed by another user. Refresh and retry.');
		}
		throw err;
	}
}

async function buildPlaylistPayload(playlistId: number, userId: number) {
	const playlist = await PlaylistDb.getById(playlistId);
	if (!playlist) throw new Error('Playlist not found');
	const canView = await PlaylistDb.canView(playlistId, userId);
	if (!canView) throw new Error('Not authorized to view this playlist');
	const tracks = await PlaylistDb.getTracks(playlistId);
	const music_ids = tracks.map(t => t.music_id);
	const collaborator_ids = await PlaylistDb.getCollaboratorIds(playlistId);
	const can_edit = await PlaylistDb.canEdit(playlistId, userId);
	return {
		...playlist,
		is_public: Boolean(playlist.is_public),
		edit_policy: playlist.edit_policy ?? 'EVERYONE',
		track_count: tracks.length,
		tracks,
		music_ids,
		collaborator_ids,
		can_edit,
	};
}

async function buildVoteEventPayload(eventId: number, userId: number, location: VoteLocation = {}) {
	const event = await VoteEventDb.getById(eventId);
	if (!event || !(await VoteEventDb.canView(eventId, userId))) throw new Error('Voting event not found or not accessible');
	const eligibility = await VoteEventDb.getVoteEligibility(event, userId, location);
	return {
		...event,
		is_public: Boolean(event.is_public),
		can_vote: eligibility.eligible,
		can_vote_reason: eligibility.reason,
		invited_user_ids: await VoteEventDb.getInviteIds(eventId),
		members: await VoteEventDb.getMembers(event),
		user_vote_music_ids: await VoteEventDb.getUserVotes(eventId, userId),
		tracks: await VoteEventDb.getTracks(eventId),
	};
}

async function listVoteEventPayloads(userId: number, location: VoteLocation = {}) {
	const events = await VoteEventDb.getAccessible(userId);
	return Promise.all(events.map(event => buildVoteEventPayload(event.id, userId, location)));
}

export const resolvers = {
	Query: {
		me: (_parent: unknown, _args: unknown, context: SubscriptionContext) => requireUser(context).id,
		musics: async () => MusicDb.getAll(),
		searchMusics: async (_parent: unknown, args: { query: string }) => {
			const q = (args.query || '').trim();
			if (!q) return [];
			return MusicDb.search(q);
		},
		myPlaylists: async (_parent: unknown, _args: unknown, context: SubscriptionContext) => {
			const user = requireUser(context);
			const playlists = await PlaylistDb.getAccessible(user.id);
			return Promise.all(playlists.map(async (p) => ({
				...p,
				track_count: Number(p.track_count),
				is_public: Boolean(p.is_public),
				edit_policy: p.edit_policy ?? 'EVERYONE',
				music_ids: await PlaylistDb.getMusicIds(p.id),
				collaborator_ids: await PlaylistDb.getCollaboratorIds(p.id),
				can_edit: await PlaylistDb.canEdit(p.id, user.id),
			})));
		},
		searchPlaylists: async (_parent: unknown, args: { query: string }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const q = (args.query || '').trim();
			if (!q) return [];
			const playlists = await PlaylistDb.search(user.id, q);
			return Promise.all(playlists.map(async (p) => ({
				...p,
				track_count: Number(p.track_count),
				is_public: Boolean(p.is_public),
				edit_policy: p.edit_policy ?? 'EVERYONE',
				music_ids: await PlaylistDb.getMusicIds(p.id),
				collaborator_ids: await PlaylistDb.getCollaboratorIds(p.id),
				can_edit: await PlaylistDb.canEdit(p.id, user.id),
			})));
		},
		playlist: async (_parent: unknown, args: { id: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			return buildPlaylistPayload(args.id, user.id);
		},
		voteEvents: async (_parent: unknown, args: VoteLocation, context: SubscriptionContext) => {
			return listVoteEventPayloads(requireUser(context).id, args);
		},
		searchVoteEvents: async (_parent: unknown, args: { query: string }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const q = (args.query || '').trim();
			if (!q) return [];
			const events = await VoteEventDb.search(user.id, q);
			return Promise.all(events.map(event => buildVoteEventPayload(event.id, user.id)));
		},
		voteEvent: async (_parent: unknown, args: { id: number } & VoteLocation, context: SubscriptionContext) => {
			return buildVoteEventPayload(args.id, requireUser(context).id, args);
		},
		room: (_parent: unknown, args: { id: number }) => roomStore.getRoom(args.id)?.toState() ?? null,
		rooms: () => roomStore.listRooms(),
	},
	Mutation: {
		createRoom: (_parent: unknown, args: { name: string }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const { room, leftRoomIds } = roomStore.createRoom(user.id, args.name, context.client.deviceKey);
			for (const leftRoomId of leftRoomIds) context.joinedRoomIds.delete(leftRoomId);
			context.joinedRoomIds.add(room.id);
			return room.toState();
		},
		joinRoom: (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const { room, leftRoomIds } = roomStore.joinRoom(args.roomId, user.id);
			for (const leftRoomId of leftRoomIds) context.joinedRoomIds.delete(leftRoomId);
			context.joinedRoomIds.add(args.roomId);
			return room.toState();
		},
		leaveRoom: (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			roomStore.leaveRoom(args.roomId, user.id);
			context.joinedRoomIds.delete(args.roomId);
			return true;
		},
		deleteRoom: (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.deleteRoom(args.roomId, user.id);
			if (result.ok) context.joinedRoomIds.delete(args.roomId);
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		transferHost: (_parent: unknown, args: { roomId: number; targetUserId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.transferHost(args.roomId, user.id, args.targetUserId);
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		addToQueue: async (_parent: unknown, args: { roomId: number; musicId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.addMusic(args.roomId, await effectiveController(args.roomId, user.id, context), args.musicId);
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		setQueue: async (_parent: unknown, args: { roomId: number; musicIds: number[] }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.setQueue(args.roomId, await effectiveController(args.roomId, user.id, context), args.musicIds);
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		play: async (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.play(args.roomId, await effectiveController(args.roomId, user.id, context));
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		pause: async (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.pause(args.roomId, await effectiveController(args.roomId, user.id, context));
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		next: async (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.next(args.roomId, await effectiveController(args.roomId, user.id, context));
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		previous: async (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.previous(args.roomId, await effectiveController(args.roomId, user.id, context));
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		seek: async (_parent: unknown, args: { roomId: number; positionMs: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.seek(args.roomId, await effectiveController(args.roomId, user.id, context), args.positionMs);
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		linkVoteEvent: async (_parent: unknown, args: { roomId: number; eventId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = await roomStore.linkVoteEvent(args.roomId, await effectiveController(args.roomId, user.id, context), args.eventId);
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		unlinkVoteEvent: async (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const result = roomStore.unlinkVoteEvent(args.roomId, await effectiveController(args.roomId, user.id, context));
			return wrapAction(result, roomStore.getRoom(args.roomId)?.toState() ?? null);
		},
		createPlaylist: async (_parent: unknown, args: { name: string; isPublic: boolean; editPolicy?: 'EVERYONE' | 'COLLABORATORS' }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const playlist = await PlaylistDb.create(args.name, user.id, args.isPublic, args.editPolicy ?? 'EVERYONE');
			if (!playlist) throw new Error('Failed to create playlist');
			publishPlaylistUpdate(playlist.id);
			return buildPlaylistPayload(playlist.id, user.id);
		},
		updatePlaylistVisibility: async (_parent: unknown, args: { playlistId: number; isPublic: boolean; expectedVersion?: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			await withPlaylistConflict(() => PlaylistDb.setVisibility(args.playlistId, user.id, args.isPublic, args.expectedVersion));
			publishPlaylistUpdate(args.playlistId);
			return buildPlaylistPayload(args.playlistId, user.id);
		},
		updatePlaylistEditPolicy: async (_parent: unknown, args: { playlistId: number; editPolicy: 'EVERYONE' | 'COLLABORATORS'; expectedVersion?: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const ok = await withPlaylistConflict(() => PlaylistDb.setEditPolicy(args.playlistId, user.id, args.editPolicy, args.expectedVersion));
			if (!ok) throw new Error('Only the owner can update playlist license');
			publishPlaylistUpdate(args.playlistId);
			return buildPlaylistPayload(args.playlistId, user.id);
		},
		invitePlaylistCollaborator: async (_parent: unknown, args: { playlistId: number; email: string; expectedVersion?: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const account = await AccountDb.getAccountByEmail(args.email.trim().toLowerCase());
			if (!account) throw new Error('User not found');
			const ok = await withPlaylistConflict(() => PlaylistDb.addCollaborator(args.playlistId, user.id, Number(account.id), args.expectedVersion));
			if (!ok) throw new Error('Only the owner can invite collaborators');
			publishPlaylistUpdate(args.playlistId);
			return buildPlaylistPayload(args.playlistId, user.id);
		},
		addTrackToPlaylist: async (_parent: unknown, args: { playlistId: number; musicId: number; expectedVersion?: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const canEdit = await PlaylistDb.canEdit(args.playlistId, user.id);
			if (!canEdit) throw new Error('Not authorized to edit this playlist');
			await withPlaylistConflict(() => PlaylistDb.addTrack(args.playlistId, args.musicId, args.expectedVersion));
			publishPlaylistUpdate(args.playlistId);
			return buildPlaylistPayload(args.playlistId, user.id);
		},
		removeTrackFromPlaylist: async (_parent: unknown, args: { playlistId: number; musicId: number; expectedVersion?: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const canEdit = await PlaylistDb.canEdit(args.playlistId, user.id);
			if (!canEdit) throw new Error('Not authorized to edit this playlist');
			await withPlaylistConflict(() => PlaylistDb.removeTrack(args.playlistId, args.musicId, args.expectedVersion));
			publishPlaylistUpdate(args.playlistId);
			return buildPlaylistPayload(args.playlistId, user.id);
		},
		moveTrackInPlaylist: async (_parent: unknown, args: { playlistId: number; musicId: number; newPosition: number; expectedVersion?: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const canEdit = await PlaylistDb.canEdit(args.playlistId, user.id);
			if (!canEdit) throw new Error('Not authorized to edit this playlist');
			await withPlaylistConflict(() => PlaylistDb.moveTrack(args.playlistId, args.musicId, args.newPosition, args.expectedVersion));
			publishPlaylistUpdate(args.playlistId);
			return buildPlaylistPayload(args.playlistId, user.id);
		},
		createVoteEvent: async (_parent: unknown, args: {
			name: string; isPublic?: boolean; votePolicy?: VotePolicy; location?: string;
			radiusMeters?: number; startsAt?: string; endsAt?: string;
		}, context: SubscriptionContext) => {
			const user = requireUser(context);
			const name = String(args.name || '').trim();
			if (!name) throw new Error('Event name is required');
			const location = String(args.location || '').trim();
			if (args.votePolicy === 'LOCATION_TIME' && (
				!location || !args.radiusMeters || !args.startsAt || !args.endsAt
			)) throw new Error('Location/time events require a location, radius, start and end');
			if (args.votePolicy === 'LOCATION_TIME' && (
				!Number.isInteger(args.radiusMeters) || args.radiusMeters! < MIN_RADIUS_METERS || args.radiusMeters! > MAX_RADIUS_METERS
			)) throw new Error(`Radius must be between ${MIN_RADIUS_METERS} and ${MAX_RADIUS_METERS} meters`);
			let coordinates: GeocodedLocation | null = null;
			if (args.votePolicy === 'LOCATION_TIME') {
				coordinates = await GeocodingService.resolveLocation(location);
				if (!coordinates) throw new Error('Could not resolve that location');
			}
			const eventId = await VoteEventDb.create(user.id, name, args.isPublic ?? true, args.votePolicy ?? 'EVERYONE', {
				latitude: coordinates?.latitude,
				longitude: coordinates?.longitude,
				radiusMeters: args.radiusMeters,
				startsAt: args.startsAt,
				endsAt: args.endsAt,
			});
			publishVoteEventUpdate(eventId);
			return buildVoteEventPayload(eventId, user.id, coordinates ?? {});
		},
		deleteVoteEvent: async (_parent: unknown, args: { eventId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			if (!(await VoteEventDb.remove(args.eventId, user.id))) throw new Error('Only the owner can delete this event');
			roomStore.unlinkRoomsForVoteEvent(args.eventId);
			publishVoteEventUpdate(args.eventId);
			return true;
		},
		inviteVoteEventUser: async (_parent: unknown, args: { eventId: number; email: string }, context: SubscriptionContext) => {
			const user = requireUser(context);
			const account = await AccountDb.getAccountByEmail(String(args.email || '').trim().toLowerCase());
			if (!account) throw new Error('User not found');
			if (!(await VoteEventDb.invite(args.eventId, user.id, Number(account.id)))) throw new Error('Only the owner can invite users');
			publishVoteEventUpdate(args.eventId);
			return buildVoteEventPayload(args.eventId, user.id);
		},
		removeVoteEventUser: async (_parent: unknown, args: { eventId: number; userId: number }, context: SubscriptionContext) => {
			const user = requireUser(context);
			if (!(await VoteEventDb.removeInvite(args.eventId, user.id, args.userId))) throw new Error('Only the owner can remove members');
			publishVoteEventUpdate(args.eventId);
			return buildVoteEventPayload(args.eventId, user.id);
		},
		suggestVoteTrack: async (_parent: unknown, args: { eventId: number; musicId: number } & VoteLocation, context: SubscriptionContext) => {
			const user = requireUser(context);
			await VoteEventDb.suggest(args.eventId, user.id, args.musicId, args);
			publishVoteEventUpdate(args.eventId);
			return buildVoteEventPayload(args.eventId, user.id, args);
		},
		voteForTrack: async (_parent: unknown, args: { eventId: number; musicId: number } & VoteLocation, context: SubscriptionContext) => {
			const user = requireUser(context);
			await VoteEventDb.vote(args.eventId, user.id, args.musicId, args);
			publishVoteEventUpdate(args.eventId);
			return buildVoteEventPayload(args.eventId, user.id, args);
		},
	},
	Subscription: {
		roomState: {
			subscribe: async function* (_parent: unknown, args: { roomId: number }, context: SubscriptionContext) {
				const user = requireUser(context);
				const room = roomStore.getRoom(args.roomId);
				if (!room) throw new Error(`Room ${args.roomId} not found`);
				roomStore.cancelPendingLeave(args.roomId, user.id);
				context.joinedRoomIds.add(args.roomId);
				const iterator = roomStore.subscribe(args.roomId);
				yield { roomState: room.toState() };
				for await (const event of iterator) {
					if (event.type === 'STATE') yield { roomState: event.state };
					if (event.type === 'CLOSED') return;
				}
			},
		},
		streamMusic: {
			subscribe: async function* (_parent: unknown, args: { roomId: number }) {
				const room = roomStore.getRoom(args.roomId);
				if (!room) throw new Error(`Room ${args.roomId} not found`);
				const iterator = roomStore.subscribe(args.roomId);
				for await (const event of iterator) {
					if (event.type === 'CHUNK') yield { streamMusic: event.chunk };
					if (event.type === 'CLOSED') return;
				}
			},
		},
		playlistUpdated: {
			subscribe: async function* (_parent: unknown, args: { playlistId: number }, context: SubscriptionContext) {
				const user = requireUser(context);
				yield { playlistUpdated: await buildPlaylistPayload(args.playlistId, user.id) };
				const iterator = subscribeToPlaylist(args.playlistId);
				for await (const playlistId of iterator) {
					yield { playlistUpdated: await buildPlaylistPayload(playlistId, user.id) };
				}
			},
		},
		voteEventUpdated: {
			subscribe: async function* (_parent: unknown, args: { eventId: number } & VoteLocation, context: SubscriptionContext) {
				const user = requireUser(context);
				yield { voteEventUpdated: await buildVoteEventPayload(args.eventId, user.id, args) };
				for await (const event of subscribeToVoteEvent(args.eventId)) {
					const eventId = Array.isArray(event) ? Number(event[0]) : Number(event);
					yield { voteEventUpdated: await buildVoteEventPayload(eventId, user.id, args) };
				}
			},
		},
		voteEventsUpdated: {
			subscribe: async function* (_parent: unknown, args: VoteLocation, context: SubscriptionContext) {
				const user = requireUser(context);
				yield { voteEventsUpdated: await listVoteEventPayloads(user.id, args) };
				for await (const _event of subscribeToVoteEvents()) {
					yield { voteEventsUpdated: await listVoteEventPayloads(user.id, args) };
				}
			},
		},
		rooms: {
			subscribe: async function* () {
				yield { rooms: roomStore.listRooms() };
				const iterator = roomStore.subscribeRooms();
				for await (const roomsList of iterator) {
					yield { rooms: roomsList };
				}
			},
		},
	},
};

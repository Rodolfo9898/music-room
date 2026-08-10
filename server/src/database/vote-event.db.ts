import { Database } from './database';
import { Logger } from '../utils/logger';

// MariaDB rejects raw ISO-8601 strings with a 'T'/'Z' suffix (e.g. from
// Date#toISOString()) as DATETIME literals ("Incorrect datetime value").
// Converting to a JS Date lets the mariadb driver serialize it in the
// server-accepted DATETIME format instead.
function toDatetimeParam(value?: string | null): Date | null {
	if (!value) return null;
	const date = new Date(value);
	return Number.isNaN(date.getTime()) ? null : date;
}

export type VotePolicy = 'EVERYONE' | 'INVITED' | 'LOCATION_TIME';

export type VoteEligibilityReason =
	| 'NOT_VIEWABLE'
	| 'NOT_INVITED'
	| 'WINDOW_NOT_CONFIGURED'
	| 'OUTSIDE_TIME_WINDOW'
	| 'LOCATION_NOT_CONFIGURED'
	| 'LOCATION_UNAVAILABLE'
	| 'OUTSIDE_RADIUS';

export interface VoteEligibility {
	eligible: boolean;
	reason: VoteEligibilityReason | null;
}

const VOTE_ELIGIBILITY_MESSAGES: Record<VoteEligibilityReason, string> = {
	NOT_VIEWABLE: "you don't have access to this event",
	NOT_INVITED: "you haven't been invited to vote on this event",
	WINDOW_NOT_CONFIGURED: "this event's voting window isn't configured yet",
	OUTSIDE_TIME_WINDOW: 'the voting window for this event is not currently open',
	LOCATION_NOT_CONFIGURED: "this event's location isn't configured",
	LOCATION_UNAVAILABLE: 'your location could not be determined',
	OUTSIDE_RADIUS: "you're too far from the event's location",
};

// Turns a VoteEligibilityReason into a precise, user-facing sentence fragment
// (used to build "Not eligible to vote: <message>" errors). Never includes
// raw coordinates/distances — those stay in the server-side debug logs.
export function voteEligibilityMessage(reason: VoteEligibilityReason | null): string {
	if (!reason) return 'you are eligible';
	return VOTE_ELIGIBILITY_MESSAGES[reason];
}

export interface VoteEventRow {
	id: number;
	name: string;
	owner_id: number;
	is_public: boolean;
	vote_policy: VotePolicy;
	latitude: number | null;
	longitude: number | null;
	radius_meters: number | null;
	starts_at: string | null;
	ends_at: string | null;
	version: number;
}

export interface VoteTrackRow {
	music_id: number;
	title: string;
	artist_name: string;
	duration: number;
	vote_count: number;
	suggested_by: number;
}

export interface VoteLocation {
	latitude?: number | null;
	longitude?: number | null;
}

export interface VoteMemberRow {
	id: number;
	email: string;
	display_name: string;
}

export class VoteEventDb {
	static async create(
		ownerId: number,
		name: string,
		isPublic = true,
		votePolicy: VotePolicy = 'EVERYONE',
		location: VoteLocation & {
			radiusMeters?: number | null;
			startsAt?: string | null;
			endsAt?: string | null
		} = {},
	): Promise<number> {
		const result = await Database.query<{ insertId: number }>(
			`INSERT INTO vote_events
             (name, owner_id, is_public, vote_policy, latitude, longitude, radius_meters, starts_at, ends_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			name,
			ownerId,
			isPublic,
			votePolicy,
			location.latitude ?? null,
			location.longitude ?? null,
			location.radiusMeters ?? null,
			toDatetimeParam(location.startsAt),
			toDatetimeParam(location.endsAt),
		);
		return (result as any).insertId ?? (result[0] as any)?.insertId;
	}

	static async getAccessible(userId: number): Promise<VoteEventRow[]> {
		return Database.query<VoteEventRow>(
			`SELECT *
             FROM vote_events e
             WHERE e.is_public = TRUE
                OR e.owner_id = ?
                OR EXISTS (SELECT 1 FROM vote_event_invites i WHERE i.event_id = e.id AND i.user_id = ?)
             ORDER BY e.updated_at DESC`,
			userId,
			userId,
		);
	}

	static async search(userId: number, query: string): Promise<VoteEventRow[]> {
		return Database.query<VoteEventRow>(
			`SELECT *
             FROM vote_events e
             WHERE (e.is_public = TRUE
                 OR e.owner_id = ?
                 OR EXISTS (SELECT 1 FROM vote_event_invites i WHERE i.event_id = e.id AND i.user_id = ?))
               AND e.name LIKE ?
             ORDER BY e.updated_at DESC`,
			userId,
			userId,
			`%${query}%`,
		);
	}

	static async getById(eventId: number): Promise<VoteEventRow | null> {
		const rows = await Database.query<VoteEventRow>('SELECT * FROM vote_events WHERE id = ?', eventId);
		return rows[0] ?? null;
	}

	static async canView(eventId: number, userId: number): Promise<boolean> {
		const rows = await Database.query<{ found: number }>(
			`SELECT 1 found
             FROM vote_events e
             WHERE e.id = ?
               AND (
                 e.is_public = TRUE OR e.owner_id = ? OR
                 EXISTS (SELECT 1 FROM vote_event_invites i WHERE i.event_id = e.id AND i.user_id = ?))
             LIMIT 1`,
			eventId,
			userId,
			userId,
		);
		return rows.length > 0;
	}

	static async canVote(event: VoteEventRow, userId: number, location: VoteLocation = {}): Promise<boolean> {
		return (await VoteEventDb.getVoteEligibility(event, userId, location)).eligible;
	}

	// Computes whether a user may vote/suggest for an event, along with a specific
	// reason when they may not. Debug-logs the breakdown (never raw coordinates to
	// the client) so eligibility issues reported by users can be diagnosed from logs.
	static async getVoteEligibility(event: VoteEventRow, userId: number, location: VoteLocation = {}): Promise<VoteEligibility> {
		const deny = (reason: VoteEligibilityReason, extra?: Record<string, unknown>): VoteEligibility => {
			Logger.debug('Vote eligibility denied', {
				eventId: event.id,
				userId,
				votePolicy: event.vote_policy,
				reason,
				...extra,
			});
			return {eligible: false, reason};
		};

		if (!(await VoteEventDb.canView(event.id, userId))) return deny('NOT_VIEWABLE');
		if (event.vote_policy === 'EVERYONE') return {eligible: true, reason: null};
		if (event.vote_policy === 'INVITED') {
			const invited = await VoteEventDb.isInvited(event.id, userId);
			return invited || event.owner_id === userId ? {eligible: true, reason: null} : deny('NOT_INVITED');
		}

		if (!event.starts_at || !event.ends_at) return deny('WINDOW_NOT_CONFIGURED');
		const now = Date.now();
		const startsAtMs = new Date(event.starts_at).getTime();
		const endsAtMs = new Date(event.ends_at).getTime();
		if (now < startsAtMs || now > endsAtMs) {
			return deny('OUTSIDE_TIME_WINDOW', {now, startsAtMs, endsAtMs});
		}

		if (event.latitude == null || event.longitude == null || event.radius_meters == null) {
			return deny('LOCATION_NOT_CONFIGURED');
		}
		if (location.latitude == null || location.longitude == null) {
			return deny('LOCATION_UNAVAILABLE');
		}

		const distanceMeters = haversineMeters(event.latitude, event.longitude, location.latitude, location.longitude);
		console.log(distanceMeters);
		if (distanceMeters > event.radius_meters) {
			return deny('OUTSIDE_RADIUS', {distanceMeters, radiusMeters: event.radius_meters});
		}
		return {eligible: true, reason: null};
	}

	static async isInvited(eventId: number, userId: number): Promise<boolean> {
		const rows = await Database.query<{ found: number }>(
			'SELECT 1 found FROM vote_event_invites WHERE event_id = ? AND user_id = ? LIMIT 1',
			eventId,
			userId,
		);
		return rows.length > 0;
	}

	static async invite(eventId: number, ownerId: number, userId: number): Promise<boolean> {
		const event = await VoteEventDb.getById(eventId);
		if (!event || event.owner_id !== ownerId) return false;
		await Database.query(
			'INSERT IGNORE INTO vote_event_invites (event_id, user_id) VALUES (?, ?)',
			eventId,
			userId,
		);
		await Database.query('UPDATE vote_events SET version = version + 1 WHERE id = ?', eventId);
		return true;
	}

	// Deletes the event outright. Only the owner may delete it. Child rows
	// (invites, tracks, votes) cascade via FK ON DELETE CASCADE, so a single
	// DELETE on vote_events is enough to clean everything up.
	static async remove(eventId: number, ownerId: number): Promise<boolean> {
		const event = await VoteEventDb.getById(eventId);
		if (!event || event.owner_id !== ownerId) return false;
		await Database.query('DELETE FROM vote_events WHERE id = ?', eventId);
		return true;
	}

	// Removes an invited user and clears any vote they cast, since a removed
	// member should no longer influence the ranking.
	static async removeInvite(eventId: number, ownerId: number, userId: number): Promise<boolean> {
		const event = await VoteEventDb.getById(eventId);
		if (!event || event.owner_id !== ownerId) return false;
		await Database.transaction(async conn => {
			await conn.query('DELETE FROM vote_event_invites WHERE event_id = ? AND user_id = ?', [eventId, userId]);
			await conn.query('DELETE FROM vote_event_votes WHERE event_id = ? AND user_id = ?', [eventId, userId]);
			await conn.query('UPDATE vote_events SET version = version + 1 WHERE id = ?', [eventId]);
		});
		return true;
	}

	static async getInviteMembers(eventId: number): Promise<VoteMemberRow[]> {
		return Database.query<VoteMemberRow>(
			`SELECT u.id, u.email, u.display_name
             FROM vote_event_invites i
                      JOIN users u ON u.id = i.user_id
             WHERE i.event_id = ?
             ORDER BY u.display_name`,
			eventId,
		);
	}

	// Users with no invite mechanism (EVERYONE / LOCATION_TIME policies) are
	// instead listed by the votes they've actually cast, read-only.
	static async getVoterMembers(eventId: number): Promise<VoteMemberRow[]> {
		return Database.query<VoteMemberRow>(
			`SELECT DISTINCT u.id, u.email, u.display_name
             FROM vote_event_votes v
                      JOIN users u ON u.id = v.user_id
             WHERE v.event_id = ?
             ORDER BY u.display_name`,
			eventId,
		);
	}

	static async getMembers(event: VoteEventRow): Promise<VoteMemberRow[]> {
		// Private events gate access via vote_event_invites regardless of vote
		// policy (see canView), so the owner must be able to manage invitees
		// even when the policy itself isn't INVITED. Only public events with a
		// policy that has no invite mechanism fall back to the read-only voter
		// list.
		return event.vote_policy === 'INVITED' || !event.is_public
			? VoteEventDb.getInviteMembers(event.id)
			: VoteEventDb.getVoterMembers(event.id);
	}

	static async suggest(eventId: number, userId: number, musicId: number, location: VoteLocation = {}): Promise<void> {
		const event = await VoteEventDb.getById(eventId);
		if (!event) throw new Error('Voting event not found');
		const eligibility = await VoteEventDb.getVoteEligibility(event, userId, location);
		if (!eligibility.eligible) {
			throw new Error(`Not eligible to suggest tracks for this event: ${voteEligibilityMessage(eligibility.reason)}`);
		}
		await Database.transaction(async conn => {
			await conn.query(
				'INSERT IGNORE INTO vote_event_tracks (event_id, music_id, suggested_by) VALUES (?, ?, ?)',
				[eventId, musicId, userId],
			);
			await conn.query('UPDATE vote_events SET version = version + 1 WHERE id = ?', [eventId]);
		});
	}

	static async vote(eventId: number, userId: number, musicId: number, location: VoteLocation = {}): Promise<void> {
		const event = await VoteEventDb.getById(eventId);
		if (!event) throw new Error('Voting event not found');
		const eligibility = await VoteEventDb.getVoteEligibility(event, userId, location);
		if (!eligibility.eligible) {
			throw new Error(`Not eligible to vote for this event: ${voteEligibilityMessage(eligibility.reason)}`);
		}
		await Database.transaction(async conn => {
			// Every voter for an event locks the same parent row first. This gives a
			// deterministic lock order and prevents concurrent toggle deadlocks.
			await conn.query('SELECT id FROM vote_events WHERE id = ? FOR UPDATE', [eventId]);
			const tracks = await conn.query(
				'SELECT 1 found FROM vote_event_tracks WHERE event_id = ? AND music_id = ? FOR UPDATE',
				[eventId, musicId],
			);
			if (!tracks.length) throw new Error('Track is not in this voting event');
			// Voting is a toggle: casting a vote for a track the user already backed
			// removes it, letting a user back several different tracks at once.
			const existingVote = await conn.query(
				'SELECT 1 found FROM vote_event_votes WHERE event_id = ? AND user_id = ? AND music_id = ? FOR UPDATE',
				[eventId, userId, musicId],
			);
			if (existingVote.length) {
				await conn.query(
					'DELETE FROM vote_event_votes WHERE event_id = ? AND user_id = ? AND music_id = ?',
					[eventId, userId, musicId],
				);
			} else {
				await conn.query(
					'INSERT INTO vote_event_votes (event_id, user_id, music_id) VALUES (?, ?, ?)',
					[eventId, userId, musicId],
				);
			}
			await conn.query('UPDATE vote_events SET version = version + 1 WHERE id = ?', [eventId]);
		});
	}

	static async getTracks(eventId: number): Promise<VoteTrackRow[]> {
		return Database.query<VoteTrackRow>(
			`SELECT t.music_id,
                    m.title,
                    a.name           artist_name,
                    m.duration,
                    t.suggested_by,
                    COUNT(v.user_id) vote_count
             FROM vote_event_tracks t
                      JOIN musics m ON m.id = t.music_id
                      JOIN artists a ON a.id = m.artist_id
                      LEFT JOIN vote_event_votes v ON v.event_id = t.event_id AND v.music_id = t.music_id
             WHERE t.event_id = ?
             GROUP BY t.event_id, t.music_id
             ORDER BY vote_count DESC, t.suggested_at ASC, t.music_id ASC`,
			eventId,
		);
	}

	static async getUserVotes(eventId: number, userId: number): Promise<number[]> {
		const rows = await Database.query<{ music_id: number }>(
			'SELECT music_id FROM vote_event_votes WHERE event_id = ? AND user_id = ?',
			eventId,
			userId,
		);
		return rows.map(row => row.music_id);
	}

	static async getInviteIds(eventId: number): Promise<number[]> {
		const rows = await Database.query<{ user_id: number }>(
			'SELECT user_id FROM vote_event_invites WHERE event_id = ? ORDER BY user_id',
			eventId,
		);
		return rows.map(row => row.user_id);
	}
}

function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
	const radians = (degrees: number) => degrees * Math.PI / 180;
	const earthRadius = 6371000;
	const dLat = radians(lat2 - lat1);
	const dLon = radians(lon2 - lon1);
	const a = Math.sin(dLat / 2) ** 2
		+ Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
	return earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

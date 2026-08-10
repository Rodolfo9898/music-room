import { Database } from './database';
import { AccountModel } from './database.models';

export class AccountDb {


	static async insert(email: string, display_name: string, password_hash: string) {
		interface ret {
			id: number
		}

		const res: ret[] = await Database.query<ret>(`
                    INSERT INTO users (email, display_name, password_hash)
                    VALUES (?, ?, ?)
                    RETURNING id`,
			email,
			display_name,
			password_hash
		);
		if (res.length === 0) {
			return null;
		}
		return res[0].id;
	}

	static async getAccountByEmail(email: string, get_password_hash: boolean = false): Promise<AccountModel> {
		const res: AccountModel[] = await Database.query<AccountModel>(`
                    SELECT *, IF(?, users.password_hash, NULL) AS password_hash
                    FROM users
                    WHERE email = ?
			`,
			get_password_hash,
			email);
		if (res.length === 0) {
			return null;
		}
		return res[0];
	}

	static async getAccountById(accountId: number): Promise<AccountModel> {
		const res: AccountModel[] = await Database.query<AccountModel>(`
                    SELECT *
                    FROM users
                    WHERE id = ?
			`,
			accountId);
		if (res.length === 0) {
			return null;
		}
		return res[0];
	}

	static async getAccountByGoogleId(googleId: string): Promise<AccountModel> {
		const res: AccountModel[] = await Database.query<AccountModel>(`
            SELECT *
            FROM users
            WHERE google_id = ?
		`, googleId);
		if (res.length === 0) {
			return null;
		}
		return res[0];
	}

	static async setGoogleId(accountId: number, googleId: string): Promise<void> {
		await Database.query(`
            UPDATE users
            SET google_id = ?
            WHERE id = ?
		`, googleId, accountId);
	}

	static async updateDisplayName(accountId: number, displayName: string): Promise<void> {
		await Database.query(`
            UPDATE users
            SET display_name = ?
            WHERE id = ?
		`, displayName, accountId);
	}

	static async updateProfile(
		accountId: number,
		displayName: string,
		publicInfo: string,
		friendsInfo: string,
		privateInfo: string,
		hasPublicPreference: boolean,
	): Promise<void> {
		await Database.query(`
            UPDATE users
            SET display_name          = ?,
                public_info           = ?,
                friends_info          = ?,
                private_info          = ?,
                has_public_preference = ?
            WHERE id = ?
		`, displayName, publicInfo, friendsInfo, privateInfo, hasPublicPreference, accountId);
	}

	static async getGenrePreferenceIds(accountId: number): Promise<number[]> {
		const rows = await Database.query<{ genre_id: number }>(`
            SELECT genre_id
            FROM user_genre_preferences
            WHERE user_id = ?
            ORDER BY genre_id
		`, accountId);
		return rows.map(row => row.genre_id);
	}

	static async setGenrePreferences(accountId: number, genreIds: number[]): Promise<void> {
		await Database.query('DELETE FROM user_genre_preferences WHERE user_id = ?', accountId);
		for (const genreId of genreIds) {
			await Database.query(`
                INSERT IGNORE INTO user_genre_preferences (user_id, genre_id)
                VALUES (?, ?)
			`, accountId, genreId);
		}
	}

	static async deleteAccount(accountId: number): Promise<void> {
		await Database.query(`
            DELETE
            FROM users
            WHERE id = ?
		`, accountId);
	}

	static async setEmailConfirmationToken(accountId: number, token: string): Promise<void> {
		await Database.query(`
            UPDATE users
            SET email_confirmation_token      = ?,
                email_confirmation_expires_at = DATE_ADD(NOW(), INTERVAL 24 HOUR)
            WHERE id = ?
		`, token, accountId);
	}

	static async getAccountByEmailConfirmationToken(token: string): Promise<AccountModel> {
		const res: AccountModel[] = await Database.query<AccountModel>(`
            SELECT *
            FROM users
            WHERE email_confirmation_token = ?
              AND email_confirmation_token IS NOT NULL
              AND email_confirmation_expires_at > NOW()
		`, token);
		if (res.length === 0) {
			return null;
		}
		return res[0];
	}

	static async confirmEmail(accountId: number): Promise<void> {
		await Database.query(`
            UPDATE users
            SET email_confirmation_token      = NULL,
                email_confirmation_expires_at = NULL
            WHERE id = ?
		`, accountId);
	}

	static async setPasswordResetToken(accountId: number, token: string): Promise<void> {
		await Database.query(`
            UPDATE users
            SET password_reset_token      = ?,
                password_reset_expires_at = DATE_ADD(NOW(), INTERVAL 1 HOUR)
            WHERE id = ?
		`, token, accountId);
	}

	static async getAccountByPasswordResetToken(token: string): Promise<AccountModel> {
		const res: AccountModel[] = await Database.query<AccountModel>(`
            SELECT *
            FROM users
            WHERE password_reset_token = ?
              AND password_reset_token IS NOT NULL
              AND password_reset_expires_at > NOW()
		`, token);
		if (res.length === 0) {
			return null;
		}
		return res[0];
	}

	static async updatePasswordAndClearReset(accountId: number, passwordHash: string): Promise<void> {
		await Database.query(`
            UPDATE users
            SET password_hash             = ?,
                password_reset_token      = NULL,
                password_reset_expires_at = NULL
            WHERE id = ?
		`, passwordHash, accountId);
	}

	static async areFriends(firstUserId: number, secondUserId: number): Promise<boolean> {
		const rows = await Database.query<{ found: number }>(`
            SELECT 1 found
            FROM friendships
            WHERE status = 'ACCEPTED'
              AND (
                (requester_id = ? AND addressee_id = ?) OR
                (requester_id = ? AND addressee_id = ?)
                )
            LIMIT 1
		`, firstUserId, secondUserId, secondUserId, firstUserId);
		return rows.length > 0;
	}

	static async listFriends(accountId: number) {
		return Database.query<{
			id: number;
			email: string;
			display_name: string;
			status: 'PENDING' | 'ACCEPTED';
			direction: 'INCOMING' | 'OUTGOING';
		}>(`
            SELECT u.id,
                   u.email,
                   u.display_name,
                   f.status,
                   IF(f.addressee_id = ?, 'INCOMING', 'OUTGOING') direction
            FROM friendships f
                     JOIN users u ON u.id = IF(f.requester_id = ?, f.addressee_id, f.requester_id)
            WHERE f.requester_id = ?
               OR f.addressee_id = ?
            ORDER BY f.status, u.display_name
		`, accountId, accountId, accountId, accountId);
	}

	static async requestFriend(requesterId: number, addresseeId: number): Promise<void> {
		await Database.query(`
            INSERT INTO friendships (requester_id, addressee_id, status)
            VALUES (?, ?, 'PENDING')
            ON DUPLICATE KEY UPDATE updated_at = CURRENT_TIMESTAMP
		`, requesterId, addresseeId);
	}

	static async acceptFriend(accountId: number, requesterId: number): Promise<boolean> {
		const result = await Database.query(`
            UPDATE friendships
            SET status = 'ACCEPTED'
            WHERE requester_id = ?
              AND addressee_id = ?
              AND status = 'PENDING'
		`, requesterId, accountId);
		return ((result as any).affectedRows ?? 0) > 0;
	}

	static async removeFriend(accountId: number, otherUserId: number): Promise<void> {
		await Database.query(`
            DELETE
            FROM friendships
            WHERE (requester_id = ? AND addressee_id = ?)
               OR (requester_id = ? AND addressee_id = ?)
		`, accountId, otherUserId, otherUserId, accountId);
	}

	static async registerDevice(
		accountId: number,
		deviceKey: string,
		name: string,
		platform: string,
		appVersion: string,
	): Promise<void> {
		await Database.query(`
            INSERT INTO user_devices (user_id, device_key, name, platform, app_version)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name         = VALUES(name),
                                    platform     = VALUES(platform),
                                    app_version  = VALUES(app_version),
                                    last_seen_at = CURRENT_TIMESTAMP
		`, accountId, deviceKey, name, platform, appVersion);
	}

	static async listDevices(accountId: number) {
		return Database.query<{
			id: number;
			device_key: string;
			name: string;
			platform: string;
			app_version: string;
			can_control: boolean;
			last_seen_at: string;
			delegate_ids: string | null;
		}>(`SELECT d.*, GROUP_CONCAT(cd.friend_user_id ORDER BY cd.friend_user_id) delegate_ids
            FROM user_devices d
                     LEFT JOIN device_control_delegations cd ON cd.device_id = d.id
            WHERE d.user_id = ?
            GROUP BY d.id
            ORDER BY d.last_seen_at DESC`, accountId);
	}

	static async grantDeviceControl(accountId: number, deviceId: number, friendId: number): Promise<boolean> {
		if (!(await AccountDb.areFriends(accountId, friendId))) return false;
		const result = await Database.query(
			`INSERT IGNORE INTO device_control_delegations (device_id, friend_user_id, granted_by)
             SELECT id, ?, ?
             FROM user_devices
             WHERE id = ?
               AND user_id = ?
               AND can_control = TRUE`,
			friendId, accountId, deviceId, accountId,
		);
		return ((result as any).affectedRows ?? 0) > 0;
	}

	static async revokeDeviceControl(accountId: number, deviceId: number, friendId: number): Promise<void> {
		await Database.query(
			`DELETE cd
             FROM device_control_delegations cd
                      JOIN user_devices d ON d.id = cd.device_id
             WHERE cd.device_id = ?
               AND cd.friend_user_id = ?
               AND d.user_id = ?`,
			deviceId, friendId, accountId,
		);
	}

	static async canControlOwnerDevice(ownerId: number, deviceKey: string, actingUserId: number): Promise<boolean> {
		if (ownerId === actingUserId) return true;
		if (!deviceKey || deviceKey === 'unknown') return false;
		const rows = await Database.query<{ found: number }>(
			`SELECT 1 found
             FROM user_devices d
                      JOIN device_control_delegations cd ON cd.device_id = d.id
                      JOIN friendships f ON f.status = 'ACCEPTED' AND (
                 (f.requester_id = d.user_id AND f.addressee_id = cd.friend_user_id) OR
                 (f.addressee_id = d.user_id AND f.requester_id = cd.friend_user_id))
             WHERE d.user_id = ?
               AND d.device_key = ?
               AND d.can_control = TRUE
               AND cd.friend_user_id = ?
             LIMIT 1`,
			ownerId, deviceKey, actingUserId,
		);
		return rows.length > 0;
	}

	static async setDevicePermission(accountId: number, deviceId: number, canControl: boolean): Promise<boolean> {
		const result = await Database.query(
			'UPDATE user_devices SET can_control = ? WHERE id = ? AND user_id = ?',
			canControl,
			deviceId,
			accountId,
		);
		return ((result as any).affectedRows ?? 0) > 0;
	}

	static async deleteDevice(accountId: number, deviceId: number): Promise<void> {
		await Database.query('DELETE FROM user_devices WHERE id = ? AND user_id = ?', deviceId, accountId);
	}

	static async createSession(sessionId: string, accountId: number, refreshTokenHash: string): Promise<void> {
		await Database.query(`
            INSERT INTO user_sessions (id, user_id, refresh_token_hash, expires_at)
            VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 30 DAY))
		`, sessionId, accountId, refreshTokenHash);
	}

	static async getSessionByRefreshHash(refreshTokenHash: string) {
		const rows = await Database.query<{ id: string; user_id: number }>(`
            SELECT id, user_id
            FROM user_sessions
            WHERE refresh_token_hash = ?
              AND revoked_at IS NULL
              AND expires_at > NOW()
            LIMIT 1
		`, refreshTokenHash);
		return rows[0] ?? null;
	}

	static async rotateSession(sessionId: string, refreshTokenHash: string): Promise<void> {
		await Database.query(`
            UPDATE user_sessions
            SET refresh_token_hash = ?,
                last_used_at       = CURRENT_TIMESTAMP
            WHERE id = ?
              AND revoked_at IS NULL
              AND expires_at > NOW()
		`, refreshTokenHash, sessionId);
	}

	static async isSessionActive(sessionId: string, accountId: number): Promise<boolean> {
		const rows = await Database.query<{ found: number }>(`
            SELECT 1 found
            FROM user_sessions
            WHERE id = ?
              AND user_id = ?
              AND revoked_at IS NULL
              AND expires_at > NOW()
            LIMIT 1
		`, sessionId, accountId);
		return rows.length > 0;
	}

	static async revokeSession(sessionId: string, accountId: number): Promise<void> {
		await Database.query(
			'UPDATE user_sessions SET revoked_at = NOW() WHERE id = ? AND user_id = ?',
			sessionId,
			accountId,
		);
	}
}

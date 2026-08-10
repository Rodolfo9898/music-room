import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { Database } from '../src/database/database';
import { AccountDb } from '../src/database/account.db';

type QueryFn = typeof Database.query;

const originalQuery = Database.query;

afterEach(() => {
	Database.query = originalQuery;
});

test('insert returns the new account id, or null when the insert produces no row', async () => {
	Database.query = (async (sql: string) => {
		if (sql.includes('INSERT INTO users')) return [{ id: 42 }];
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;
	assert.equal(await AccountDb.insert('a@test.com', 'a', 'hash'), 42);

	Database.query = (async () => []) as QueryFn;
	assert.equal(await AccountDb.insert('a@test.com', 'a', 'hash'), null);
});

test('getAccountByEmail returns null when not found and the row otherwise', async () => {
	Database.query = (async (_sql: string, ...args: any[]) => {
		const [, email] = args;
		return email === 'found@test.com' ? [{ id: 1, email }] : [];
	}) as QueryFn;

	assert.equal(await AccountDb.getAccountByEmail('missing@test.com'), null);
	const account = await AccountDb.getAccountByEmail('found@test.com');
	assert.equal(account?.email, 'found@test.com');
});

test('getAccountById and getAccountByGoogleId return null when no row matches', async () => {
	Database.query = (async () => []) as QueryFn;
	assert.equal(await AccountDb.getAccountById(1), null);
	assert.equal(await AccountDb.getAccountByGoogleId('g-1'), null);
});

test('getAccountByEmailConfirmationToken / getAccountByPasswordResetToken return null when no row matches', async () => {
	Database.query = (async () => []) as QueryFn;
	assert.equal(await AccountDb.getAccountByEmailConfirmationToken('tok'), null);
	assert.equal(await AccountDb.getAccountByPasswordResetToken('tok'), null);
});

test('areFriends is true only when an ACCEPTED friendship exists between the two users', async () => {
	const friendships = [{ requester_id: 1, addressee_id: 2, status: 'ACCEPTED' }];
	Database.query = (async (_sql: string, ...args: any[]) => {
		const [first, second, third, fourth] = args;
		const found = friendships.some(
			f => f.status === 'ACCEPTED' &&
				((f.requester_id === first && f.addressee_id === second) ||
					(f.requester_id === third && f.addressee_id === fourth)),
		);
		return found ? [{ found: 1 }] : [];
	}) as QueryFn;

	assert.equal(await AccountDb.areFriends(1, 2), true);
	assert.equal(await AccountDb.areFriends(2, 1), true);
	assert.equal(await AccountDb.areFriends(1, 3), false);
});

test('requestFriend inserts a PENDING request and acceptFriend only accepts pending requests addressed to the caller', async () => {
	const friendships: Array<{ requester_id: number; addressee_id: number; status: string }> = [];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('INSERT INTO friendships')) {
			const [requesterId, addresseeId] = args;
			friendships.push({ requester_id: requesterId, addressee_id: addresseeId, status: 'PENDING' });
			return [];
		}
		if (sql.includes('UPDATE friendships SET status')) {
			const [requesterId, accountId] = args;
			const friendship = friendships.find(
				f => f.requester_id === requesterId && f.addressee_id === accountId && f.status === 'PENDING',
			);
			if (!friendship) return { affectedRows: 0 } as any;
			friendship.status = 'ACCEPTED';
			return { affectedRows: 1 } as any;
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	await AccountDb.requestFriend(1, 2);
	assert.deepEqual(friendships, [{ requester_id: 1, addressee_id: 2, status: 'PENDING' }]);

	assert.equal(await AccountDb.acceptFriend(99, 1), false);
	assert.equal(await AccountDb.acceptFriend(2, 1), true);
	assert.equal(friendships[0].status, 'ACCEPTED');
});

test('setEmailConfirmationToken / confirmEmail and password reset token lifecycle', async () => {
	const users: Record<number, { email_confirmation_token: string | null; password_reset_token: string | null }> = {
		1: { email_confirmation_token: null, password_reset_token: null },
	};

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SET email_confirmation_token = ?, email_confirmation_expires_at')) {
			const [token, accountId] = args;
			users[accountId].email_confirmation_token = token;
			return [];
		}
		if (sql.includes('SET email_confirmation_token = NULL')) {
			const [accountId] = args;
			users[accountId].email_confirmation_token = null;
			return [];
		}
		if (sql.includes('SET password_reset_token = ?, password_reset_expires_at')) {
			const [token, accountId] = args;
			users[accountId].password_reset_token = token;
			return [];
		}
		if (sql.includes('password_reset_token = NULL')) {
			const [, accountId] = args;
			users[accountId].password_reset_token = null;
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	await AccountDb.setEmailConfirmationToken(1, 'confirm-tok');
	assert.equal(users[1].email_confirmation_token, 'confirm-tok');
	await AccountDb.confirmEmail(1);
	assert.equal(users[1].email_confirmation_token, null);

	await AccountDb.setPasswordResetToken(1, 'reset-tok');
	assert.equal(users[1].password_reset_token, 'reset-tok');
	await AccountDb.updatePasswordAndClearReset(1, 'new-hash');
	assert.equal(users[1].password_reset_token, null);
});

test('session lifecycle: create, lookup by refresh hash, rotate, isActive, revoke', async () => {
	const sessions: Record<string, { id: string; user_id: number; refresh_token_hash: string; revoked: boolean }> = {};

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('INSERT INTO user_sessions')) {
			const [sessionId, accountId, refreshHash] = args;
			sessions[sessionId] = { id: sessionId, user_id: accountId, refresh_token_hash: refreshHash, revoked: false };
			return [];
		}
		if (sql.includes('SELECT id, user_id FROM user_sessions')) {
			const [refreshHash] = args;
			const found = Object.values(sessions).find(s => s.refresh_token_hash === refreshHash && !s.revoked);
			return found ? [{ id: found.id, user_id: found.user_id }] : [];
		}
		if (sql.includes('UPDATE user_sessions SET refresh_token_hash')) {
			const [refreshHash, sessionId] = args;
			if (sessions[sessionId] && !sessions[sessionId].revoked) sessions[sessionId].refresh_token_hash = refreshHash;
			return [];
		}
		if (sql.includes('SELECT 1 found FROM user_sessions')) {
			const [sessionId, accountId] = args;
			const session = sessions[sessionId];
			const active = Boolean(session && !session.revoked && session.user_id === accountId);
			return active ? [{ found: 1 }] : [];
		}
		if (sql.includes('UPDATE user_sessions SET revoked_at')) {
			const [sessionId, accountId] = args;
			if (sessions[sessionId] && sessions[sessionId].user_id === accountId) sessions[sessionId].revoked = true;
			return [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	await AccountDb.createSession('sid-1', 1, 'hash-a');
	const found = await AccountDb.getSessionByRefreshHash('hash-a');
	assert.equal(found?.id, 'sid-1');
	assert.equal(await AccountDb.isSessionActive('sid-1', 1), true);
	assert.equal(await AccountDb.isSessionActive('sid-1', 2), false);

	await AccountDb.rotateSession('sid-1', 'hash-b');
	assert.equal(await AccountDb.getSessionByRefreshHash('hash-a'), null);
	assert.equal((await AccountDb.getSessionByRefreshHash('hash-b'))?.id, 'sid-1');

	await AccountDb.revokeSession('sid-1', 1);
	assert.equal(await AccountDb.isSessionActive('sid-1', 1), false);
});

test('grantDeviceControl requires an accepted friendship and device ownership', async () => {
	const friendships = [{ requester_id: 1, addressee_id: 2, status: 'ACCEPTED' }];
	const grants: Array<{ device_id: number; friend_user_id: number }> = [];

	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('SELECT 1 found FROM friendships')) {
			const [first, second, third, fourth] = args;
			const found = friendships.some(
				f => f.status === 'ACCEPTED' &&
					((f.requester_id === first && f.addressee_id === second) ||
						(f.requester_id === third && f.addressee_id === fourth)),
			);
			return found ? [{ found: 1 }] : [];
		}
		if (sql.includes('INSERT IGNORE INTO device_control_delegations')) {
			const [friendId, , deviceId, ownerId] = args;
			if (deviceId === 10 && ownerId === 1) {
				grants.push({ device_id: deviceId, friend_user_id: friendId });
				return { affectedRows: 1 } as any;
			}
			return { affectedRows: 0 } as any;
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	// Not friends with the account: denied before touching the device table.
	assert.equal(await AccountDb.grantDeviceControl(1, 10, 3), false);
	assert.deepEqual(grants, []);

	assert.equal(await AccountDb.grantDeviceControl(1, 10, 2), true);
	assert.deepEqual(grants, [{ device_id: 10, friend_user_id: 2 }]);
});

test('canControlOwnerDevice allows the owner, delegated friends with matching device key, and denies others', async () => {
	Database.query = (async (sql: string, ...args: any[]) => {
		if (sql.includes('FROM user_devices d') && sql.includes('device_control_delegations')) {
			const [ownerId, deviceKey, actingUserId] = args;
			const isDelegated = ownerId === 1 && deviceKey === 'device-key-1' && actingUserId === 2;
			return isDelegated ? [{ found: 1 }] : [];
		}
		throw new Error(`Unexpected SQL: ${sql}`);
	}) as QueryFn;

	assert.equal(await AccountDb.canControlOwnerDevice(1, 'device-key-1', 1), true);
	assert.equal(await AccountDb.canControlOwnerDevice(1, 'device-key-1', 2), true);
	assert.equal(await AccountDb.canControlOwnerDevice(1, 'device-key-1', 3), false);
	assert.equal(await AccountDb.canControlOwnerDevice(1, 'unknown', 2), false);
	assert.equal(await AccountDb.canControlOwnerDevice(1, '', 2), false);
});

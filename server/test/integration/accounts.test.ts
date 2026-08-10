import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { Database } from '../../src/database/database';
import {
	startTestServer,
	uniqueEmail,
	postJson,
	getEmailConfirmationToken,
	createConfirmedUser,
	TestServer,
} from './helpers';

// Grading flows: signup with email confirmation, login, account deletion.
// Requires the local Docker DB (make db-up db-migrate).

const email = uniqueEmail('grader-account');
const password = 'Grading-password-42';

let server: TestServer;
let loginToken: string;
let refreshToken: string;
let accountId: number;
const friendEmail = uniqueEmail('grader-friend');
let friendToken: string;
let friendId: number;

before(async () => {
	server = await startTestServer();
});

after(async () => {
	await server.close();
});

test('signup with email creates an account (201)', async () => {
	const response = await postJson(`${server.baseUrl}/accounts/signup`, {
		email,
		password,
		displayName: 'grader',
	});
	assert.equal(response.status, 201);
	const envelope = await response.json() as { data: { accountId: number; email: string; message: string } };
	const body = envelope.data;
	assert.equal(body.email, email);
	assert.ok(body.accountId > 0);
	assert.ok(body.message);
});

test('login is blocked until the email is confirmed (403)', async () => {
	const response = await postJson(`${server.baseUrl}/accounts/login`, { email, password });
	assert.equal(response.status, 403);
});

test('the confirmation link confirms the email', async () => {
	// IS_LOCAL=TRUE means no real email goes out; the token in the DB is the
	// same one the confirmation link would carry.
	const token = await getEmailConfirmationToken(email);
	assert.ok(token, 'a confirmation token should be stored at signup');

	const response = await fetch(
		`${server.baseUrl}/accounts/confirm-email?token=${encodeURIComponent(token)}`,
	);
	assert.equal(response.status, 200);
	assert.equal(await getEmailConfirmationToken(email), null);
});

test('login with email succeeds after confirmation (200)', async () => {
	const response = await postJson(`${server.baseUrl}/accounts/login`, { email, password });
	assert.equal(response.status, 200);
	const envelope = await response.json() as { data: { token: string; refreshToken: string; accountId: number; email: string } };
	const body = envelope.data;
	assert.ok(body.token);
	assert.equal(body.email, email);
	accountId = body.accountId;
	loginToken = body.token;
	refreshToken = body.refreshToken;
});

test('refresh renews an authenticated session (200)', async () => {
	const response = await postJson(`${server.baseUrl}/accounts/refresh`, { refreshToken });
	assert.equal(response.status, 200);
	const envelope = await response.json() as { data: { token: string; refreshToken: string; accountId: number; email: string } };
	const body = envelope.data;
	assert.ok(body.token);
	assert.equal(body.email, email);
	assert.ok(body.accountId > 0);
	loginToken = body.token;
	refreshToken = body.refreshToken;
});

test('login with a wrong password is rejected (400)', async () => {
	const response = await postJson(`${server.baseUrl}/accounts/login`, {
		email,
		password: 'not-the-password',
	});
	assert.equal(response.status, 400);
});

test('profile tiers, music preferences, and mobile metadata are persisted', async () => {
	const response = await fetch(`${server.baseUrl}/accounts/me`, {
		method: 'PATCH',
		headers: {
			'content-type': 'application/json',
			'Access-Token': loginToken,
			'X-Client-Platform': 'android',
			'X-Client-Device': 'Integration Pixel',
			'X-App-Version': '1.0.0+1',
			'X-Device-Key': 'integration-pixel',
		},
		body: JSON.stringify({
			displayName: 'Privacy tester',
			publicInfo: 'public biography',
			friendsInfo: 'friends biography',
			privateInfo: 'private biography',
			hasPublicPreference: true,
		}),
	});
	assert.equal(response.status, 200);

	const preferencesResponse = await fetch(`${server.baseUrl}/accounts/me/preferences`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json', 'Access-Token': loginToken },
		body: JSON.stringify({ genreIds: [1, 2] }),
	});
	assert.equal(preferencesResponse.status, 200);
	const profile = (await preferencesResponse.json() as { data: {
		publicInfo: string; friendsInfo: string; privateInfo: string; musicPreferenceGenreIds: number[];
	} }).data;
	assert.equal(profile.publicInfo, 'public biography');
	assert.equal(profile.friendsInfo, 'friends biography');
	assert.equal(profile.privateInfo, 'private biography');
	assert.deepEqual(profile.musicPreferenceGenreIds, [1, 2]);

	await new Promise(resolve => setTimeout(resolve, 25));
	const logs = await Database.query<{ platform: string; device: string; app_version: string }>(
		`SELECT platform, device, app_version FROM mobile_action_logs
		 WHERE user_id = ? AND operation = 'PATCH /accounts/me' ORDER BY id DESC LIMIT 1`,
		accountId,
	);
	assert.equal(logs[0]?.platform, 'android');
	assert.equal(logs[0]?.device, 'Integration Pixel');
	assert.equal(logs[0]?.app_version, '1.0.0+1');
});

test('friends-only profile data is visible only after friendship acceptance', async () => {
	const friend = await createConfirmedUser(server.baseUrl, friendEmail, password);
	friendToken = friend.token;
	friendId = friend.accountId;

	const before = await fetch(`${server.baseUrl}/accounts/users/${accountId}/profile`, {
		headers: { 'Access-Token': friendToken },
	});
	assert.equal(before.status, 200);
	const beforeProfile = (await before.json() as { data: { publicInfo: string; friendsInfo: string | null; privateInfo: string | null } }).data;
	assert.equal(beforeProfile.publicInfo, 'public biography');
	assert.equal(beforeProfile.friendsInfo, null);
	assert.equal(beforeProfile.privateInfo, null);

	const request = await postJson(`${server.baseUrl}/accounts/me/friends`, { email: friendEmail }, loginToken);
	assert.equal(request.status, 201);
	const accept = await postJson(`${server.baseUrl}/accounts/me/friends/${accountId}/accept`, {}, friendToken);
	assert.equal(accept.status, 200);

	const after = await fetch(`${server.baseUrl}/accounts/users/${accountId}/profile`, {
		headers: { 'Access-Token': friendToken },
	});
	const afterProfile = (await after.json() as { data: { friendsInfo: string | null; privateInfo: string | null } }).data;
	assert.equal(afterProfile.friendsInfo, 'friends biography');
	assert.equal(afterProfile.privateInfo, null);
});

test('delete account removes the user', async () => {
	const response = await fetch(`${server.baseUrl}/accounts/me`, {
		method: 'DELETE',
		headers: { 'Access-Token': loginToken },
	});
	assert.equal(response.status, 200);
	const body = await response.json() as { success: boolean };
	assert.equal(body.success, true);

	const loginResponse = await postJson(`${server.baseUrl}/accounts/login`, { email, password });
	assert.equal(loginResponse.status, 400);

	const rows = await Database.query('SELECT id FROM users WHERE email = ?', email);
	assert.equal(rows.length, 0);
	if (friendId) await Database.query('DELETE FROM users WHERE id = ?', friendId);
});

test('account endpoints reject brute-force request bursts', async () => {
	let limited = false;
	for (let attempt = 0; attempt < 35; attempt++) {
		const response = await postJson(`${server.baseUrl}/accounts/login`, {
			email: 'nobody@example.com',
			password: 'Invalid-password-42',
		});
		if (response.status === 429) {
			limited = true;
			break;
		}
	}
	assert.equal(limited, true);
});

import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { AccountDb } from '../src/database/account.db';
import { AccountService } from '../src/api/accounts/account.service';
import { MailService } from '../src/utils/mail.service';

(global as any).config = { jwtSecret: 'test-secret', publicUrl: 'http://localhost:3000' };

const originalMethods: Record<string, any> = {};
function stub<T extends Record<string, any>, K extends keyof T>(obj: T, key: K, impl: T[K]) {
	const original = obj[key];
	originalMethods[`${(obj as any).name}.${String(key)}`] = { obj, key, original };
	obj[key] = impl;
}

afterEach(() => {
	for (const { obj, key, original } of Object.values(originalMethods)) {
		obj[key] = original;
	}
	for (const key of Object.keys(originalMethods)) delete originalMethods[key];
});

test('validatePasswordStrength enforces length, case, digit, and special-character rules', () => {
	assert.equal(AccountService.validatePasswordStrength('Ab1!Ab1!'), null); // valid
	assert.match(AccountService.validatePasswordStrength('Ab1!') || '', /at least 8 characters/);
	assert.match(AccountService.validatePasswordStrength('abcdefg1!') || '', /uppercase/);
	assert.match(AccountService.validatePasswordStrength('ABCDEFG1!') || '', /lowercase/);
	assert.match(AccountService.validatePasswordStrength('Abcdefgh!') || '', /number/);
	assert.match(AccountService.validatePasswordStrength('Abcdefgh1') || '', /special character/);
});

test('hashPassword produces a bcrypt hash that tryLogin can verify', () => {
	const hash = AccountService.hashPassword('Sup3r!Secret');
	assert.notEqual(hash, 'Sup3r!Secret');
	assert.equal(
		AccountService.tryLogin('user@test.com', 'Sup3r!Secret', { email: 'user@test.com', password_hash: hash } as any),
		true,
	);
	assert.equal(
		AccountService.tryLogin('user@test.com', 'wrong-password', { email: 'user@test.com', password_hash: hash } as any),
		false,
	);
	assert.equal(
		AccountService.tryLogin('other@test.com', 'Sup3r!Secret', { email: 'user@test.com', password_hash: hash } as any),
		false,
	);
});

test('getLoginToken / decodeAccessToken round-trip a valid JWT and reject invalid or malformed tokens', () => {
	const token = AccountService.getLoginToken(7, 'session-abc');
	const decoded = AccountService.decodeAccessToken(token);
	assert.deepEqual(decoded, { id: 7, sessionId: 'session-abc' });

	assert.equal(AccountService.decodeAccessToken('not-a-jwt'), null);
	assert.equal(AccountService.decodeAccessToken(''), null);
});

test('decodeToken returns the account id, or null for an invalid token', () => {
	const token = AccountService.getLoginToken(3, 'session-xyz');
	assert.equal(AccountService.decodeToken(token), 3);
	assert.equal(AccountService.decodeToken('garbage'), null);
});

test('register rejects missing fields, invalid email format, and weak passwords', async () => {
	const missing = await AccountService.register('', '', 'name');
	assert.equal(missing.ok, false);
	assert.equal(missing.status, 400);

	const badEmail = await AccountService.register('not-an-email', 'Ab1!Ab1!', 'name');
	assert.equal(badEmail.ok, false);
	assert.match(badEmail.message || '', /invalid email format/);

	const weakPassword = await AccountService.register('user@test.com', 'weak', 'name');
	assert.equal(weakPassword.ok, false);
	assert.equal(weakPassword.status, 400);
});

test('register creates the account and sends a confirmation email on success', async () => {
	let insertedArgs: any[] = [];
	let confirmationTokenSet: any[] = [];
	stub(AccountDb, 'insert', async (email: string, displayName: string, hash: string) => {
		insertedArgs = [email, displayName, hash];
		return 55;
	});
	stub(AccountDb, 'setEmailConfirmationToken', async (accountId: number, token: string) => {
		confirmationTokenSet = [accountId, token];
	});
	let mailSent: any = null;
	stub(MailService, 'sendMail', async (email: any, recipient: any) => {
		mailSent = { email, recipient };
	});

	const result = await AccountService.register(' User@Test.com ', 'Ab1!Ab1!', ' DisplayName ');
	assert.equal(result.ok, true);
	assert.equal(result.status, 201);
	assert.equal(result.data?.accountId, 55);
	assert.equal(result.data?.email, 'user@test.com');
	assert.equal(insertedArgs[0], 'user@test.com');
	assert.equal(confirmationTokenSet[0], 55);
	assert.ok(mailSent);
	assert.equal(mailSent.recipient, 'user@test.com');
});

test('register reports a failure when account creation does not return an id', async () => {
	stub(AccountDb, 'insert', async () => null);
	const result = await AccountService.register('user@test.com', 'Ab1!Ab1!', 'name');
	assert.equal(result.ok, false);
	assert.equal(result.status, 500);
});

test('authenticate rejects missing fields, wrong credentials, and unconfirmed emails', async () => {
	const missing = await AccountService.authenticate('', '');
	assert.equal(missing.ok, false);
	assert.equal(missing.status, 400);

	stub(AccountDb, 'getAccountByEmail', async () => null);
	const noAccount = await AccountService.authenticate('user@test.com', 'Ab1!Ab1!');
	assert.equal(noAccount.ok, false);
	assert.equal(noAccount.status, 400);

	const hash = AccountService.hashPassword('Ab1!Ab1!');
	stub(AccountDb, 'getAccountByEmail', async () => ({
		id: 1, email: 'user@test.com', password_hash: hash, email_confirmation_token: 'pending-token',
	} as any));
	const unconfirmed = await AccountService.authenticate('user@test.com', 'Ab1!Ab1!');
	assert.equal(unconfirmed.ok, false);
	assert.equal(unconfirmed.status, 403);
});

test('authenticate succeeds for a confirmed account with the correct password', async () => {
	const hash = AccountService.hashPassword('Ab1!Ab1!');
	stub(AccountDb, 'getAccountByEmail', async () => ({
		id: 1, email: 'user@test.com', display_name: 'user', password_hash: hash, email_confirmation_token: null,
	} as any));
	stub(AccountDb, 'createSession', async () => {});

	const result = await AccountService.authenticate('user@test.com', 'Ab1!Ab1!');
	assert.equal(result.ok, true);
	assert.equal(result.status, 200);
	assert.equal(result.data?.accountId, 1);
	assert.ok(result.data?.token);
	assert.ok(result.data?.refreshToken);
});

test('resetPassword rejects an invalid token, a weak password, and mismatched confirmation', async () => {
	stub(AccountDb, 'getAccountByPasswordResetToken', async () => null);
	const invalidToken = await AccountService.resetPassword('', 'Ab1!Ab1!', 'Ab1!Ab1!');
	assert.equal(invalidToken.type, 'invalid_token');

	stub(AccountDb, 'getAccountByPasswordResetToken', async () => ({ id: 1 } as any));
	const weak = await AccountService.resetPassword('tok', 'weak', 'weak');
	assert.equal(weak.type, 'invalid_input');

	const mismatch = await AccountService.resetPassword('tok', 'Ab1!Ab1!', 'Different1!');
	assert.equal(mismatch.type, 'invalid_input');
});

test('resetPassword succeeds and persists the new password hash when the token and passwords are valid', async () => {
	stub(AccountDb, 'getAccountByPasswordResetToken', async () => ({ id: 1 } as any));
	let updatedArgs: any[] = [];
	stub(AccountDb, 'updatePasswordAndClearReset', async (accountId: number, hash: string) => {
		updatedArgs = [accountId, hash];
	});

	const result = await AccountService.resetPassword('tok', 'Ab1!Ab1!', 'Ab1!Ab1!');
	assert.equal(result.type, 'success');
	assert.equal(updatedArgs[0], 1);
	assert.notEqual(updatedArgs[1], 'Ab1!Ab1!');
});

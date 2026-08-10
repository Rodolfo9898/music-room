import assert from 'node:assert/strict';
import { test } from 'node:test';

import { generateToken, buildTokenLink } from '../src/utils/token.util';

test('generateToken returns a hex string of the requested byte length by default', () => {
	const token = generateToken();
	assert.equal(token.length, 64); // default length is 64 hex chars (32 bytes)
	assert.match(token, /^[0-9a-f]+$/);
});

test('generateToken honors a custom length and produces distinct tokens', () => {
	const token = generateToken(16);
	assert.equal(token.length, 16);
	assert.match(token, /^[0-9a-f]+$/);

	const other = generateToken(16);
	assert.notEqual(token, other);
});

test('buildTokenLink appends the token query param to the configured public URL', () => {
	(global as any).config = { publicUrl: 'http://localhost:3000' };
	const link = buildTokenLink('/accounts/confirm-email', 'abc123');
	assert.equal(link, 'http://localhost:3000/accounts/confirm-email?token=abc123');
});

test('buildTokenLink strips a trailing slash from the configured public URL', () => {
	(global as any).config = { publicUrl: 'http://localhost:3000/' };
	const link = buildTokenLink('/accounts/confirm-email', 'abc123');
	assert.equal(link, 'http://localhost:3000/accounts/confirm-email?token=abc123');
});

test('buildTokenLink URL-encodes special characters in the token', () => {
	(global as any).config = { publicUrl: 'http://localhost:3000' };
	const link = buildTokenLink('/accounts/reset-password', 'a b&c=d');
	assert.equal(link, 'http://localhost:3000/accounts/reset-password?token=a%20b%26c%3Dd');
});

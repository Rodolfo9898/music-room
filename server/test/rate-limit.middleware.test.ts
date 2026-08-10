import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Request, Response } from 'express';

import { rateLimit } from '../src/middleware/rate-limit.middleware';

function fakeReq(ip = '1.2.3.4'): Request {
	return { ip, socket: { remoteAddress: ip } } as unknown as Request;
}

function fakeRes(): Response & { headers: Record<string, unknown>; statusCode?: number; body?: unknown } {
	const res: any = {
		headers: {},
		setHeader(name: string, value: unknown) {
			res.headers[name] = value;
		},
		status(code: number) {
			res.statusCode = code;
			return res;
		},
		json(body: unknown) {
			res.body = body;
			return res;
		},
	};
	return res;
}

test('rateLimit allows requests under the configured max and sets the RateLimit headers', () => {
	const middleware = rateLimit({ windowMs: 60_000, max: 3, name: 'test-allow' });
	let nextCalled = 0;

	for (let i = 0; i < 3; i++) {
		const req = fakeReq();
		const res = fakeRes();
		middleware(req, res, () => { nextCalled++; });
		assert.equal(res.statusCode, undefined);
		assert.equal(res.headers['RateLimit-Limit'], 3);
		assert.equal(res.headers['RateLimit-Remaining'], 3 - (i + 1));
	}
	assert.equal(nextCalled, 3);
});

test('rateLimit blocks requests once the max is exceeded, returning 429 and Retry-After', () => {
	const middleware = rateLimit({ windowMs: 60_000, max: 2, name: 'test-block' });
	let nextCalled = 0;

	const req = fakeReq('9.9.9.9');
	for (let i = 0; i < 2; i++) {
		middleware(req, fakeRes(), () => { nextCalled++; });
	}

	const res = fakeRes();
	middleware(req, res, () => { nextCalled++; });

	assert.equal(nextCalled, 2);
	assert.equal(res.statusCode, 429);
	assert.equal((res.body as any).success, false);
	assert.ok(res.headers['Retry-After'] !== undefined);
});

test('rateLimit tracks separate buckets per IP address', () => {
	const middleware = rateLimit({ windowMs: 60_000, max: 1, name: 'test-per-ip' });

	const resA1 = fakeRes();
	middleware(fakeReq('1.1.1.1'), resA1, () => {});
	assert.notEqual(resA1.statusCode, 429);

	const resA2 = fakeRes();
	middleware(fakeReq('1.1.1.1'), resA2, () => {});
	assert.equal(resA2.statusCode, 429);

	// A different IP has its own independent bucket.
	const resB1 = fakeRes();
	middleware(fakeReq('2.2.2.2'), resB1, () => {});
	assert.notEqual(resB1.statusCode, 429);
});

test('rateLimit resets the bucket once the time window has elapsed', (t: any) => {
	t.mock.timers.enable({ apis: ['Date'] });
	const middleware = rateLimit({ windowMs: 1_000, max: 1, name: 'test-reset' });
	const req = fakeReq('3.3.3.3');

	const first = fakeRes();
	middleware(req, first, () => {});
	assert.notEqual(first.statusCode, 429);

	const blocked = fakeRes();
	middleware(req, blocked, () => {});
	assert.equal(blocked.statusCode, 429);

	t.mock.timers.tick(1_001);

	const afterReset = fakeRes();
	middleware(req, afterReset, () => {});
	assert.notEqual(afterReset.statusCode, 429);
});

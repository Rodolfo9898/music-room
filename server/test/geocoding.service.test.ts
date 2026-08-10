import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { GeocodingService } from '../src/utils/geocoding.service';

const originalFetch = global.fetch;

afterEach(() => {
	global.fetch = originalFetch;
});

test('resolveLocation returns coordinates from the first Nominatim match', async () => {
	global.fetch = (async (url: RequestInfo | URL, init?: RequestInit) => {
		assert.match(String(url), /^https:\/\/nominatim\.openstreetmap\.org\/search\?/);
		assert.match(String(url), /q=Eiffel\+Tower/);
		const headers = init?.headers as Record<string, string>;
		assert.ok(headers['User-Agent'], 'a User-Agent header is required by the Nominatim usage policy');
		return new Response(JSON.stringify([{ lat: '48.8584', lon: '2.2945' }]), { status: 200 });
	}) as typeof fetch;

	const result = await GeocodingService.resolveLocation('Eiffel Tower');
	assert.deepEqual(result, { latitude: 48.8584, longitude: 2.2945 });
});

test('resolveLocation returns null when no match is found', async () => {
	global.fetch = (async () => new Response(JSON.stringify([]), { status: 200 })) as typeof fetch;
	assert.equal(await GeocodingService.resolveLocation('nowhere-at-all-xyz'), null);
});

test('resolveLocation returns null when the request fails', async () => {
	global.fetch = (async () => new Response('error', { status: 500 })) as typeof fetch;
	assert.equal(await GeocodingService.resolveLocation('somewhere'), null);
});

test('resolveLocation returns null for blank input without making a request', async () => {
	let called = false;
	global.fetch = (async () => {
		called = true;
		return new Response('[]', { status: 200 });
	}) as typeof fetch;

	assert.equal(await GeocodingService.resolveLocation('   '), null);
	assert.equal(called, false);
});

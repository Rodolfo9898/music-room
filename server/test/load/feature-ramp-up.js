// Ramp-up load test for the 3 "services" this project is graded on (V.7):
//   1. Track voting      -> voteForTrack mutation
//   2. Playlist editing  -> addTrackToPlaylist mutation
//   3. Host delegation   -> transferHost mutation (host hands control to a friend)
//
// Unlike server/test/load/ramp-up.js (which measures generic read traffic),
// this script drives the actual write mutations behind these 3 features so the
// measured capacity reflects real server-side work (DB writes, GraphQL
// resolvers, subscription fan-out).
//
// Fixture users/sessions are seeded directly in MariaDB (not via /accounts/signup)
// to avoid the per-IP signup rate limit (30/min) and email confirmation, which
// would otherwise make it impossible to spin up 100+ users per stage. The seeded
// JWTs are produced exactly like AccountService.getLoginToken so the server
// treats them as normal logged-in sessions.
//
// Each process invocation measures exactly ONE (scenario, concurrent-user-count)
// combination and prints one JSON line. This script is meant to be invoked once
// per combination from a *fresh* container (see run-feature-ramp-up.sh), each
// getting its own Docker-assigned IP: the server's global rate limiter
// (300 req/min per IP, see middleware/rate-limit.middleware.ts) buckets by
// client IP, and real distributed users would likewise each have their own
// bucket, so re-using a fresh container per run reflects that rather than
// artificially concentrating hundreds of requests behind one test-runner IP.
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const mariadb = require('mariadb');

const baseUrl = process.env.LOAD_BASE_URL || 'http://127.0.0.1:8080';
const scenario = process.env.LOAD_SCENARIO || 'vote'; // vote | playlist | host
const users = Number(process.env.LOAD_USERS || 10);
const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret) throw new Error('JWT_SECRET must be set (same secret the server uses) to sign fixture sessions');

const dbConfig = {
	host: process.env.DB_HOST || process.env.LOAD_DB_HOST || '127.0.0.1',
	port: Number(process.env.DB_PORT || process.env.LOAD_DB_PORT || 3306),
	user: process.env.DB_USER || process.env.LOAD_DB_USER || 'music_user',
	password: process.env.DB_PASS || process.env.LOAD_DB_PASS || 'music_pass',
	database: process.env.DB_NAME || process.env.LOAD_DB_NAME || 'MusicRoom',
	bigIntAsNumber: true,
	connectionLimit: 10,
};

const pool = mariadb.createPool(dbConfig);
const runId = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
// One fixed bcrypt hash reused for every fixture user: login is never exercised
// through this password (sessions are seeded directly), it only has to satisfy
// the `password_hash IS NOT NULL OR google_id IS NOT NULL` CHECK constraint.
const FIXTURE_PASSWORD_HASH = bcrypt.hashSync('feature-ramp-up-fixture', 4);
let userCounter = 0;

async function withConn(fn) {
	const conn = await pool.getConnection();
	try {
		return await fn(conn);
	} finally {
		await conn.release();
	}
}

async function mapLimit(items, limit, fn) {
	const results = new Array(items.length);
	let index = 0;
	async function worker() {
		while (index < items.length) {
			const current = index++;
			results[current] = await fn(items[current], current);
		}
	}
	await Promise.all(Array.from({length: Math.min(limit, items.length)}, worker));
	return results;
}

// Creates `count` confirmed users directly in the DB (bypasses signup rate
// limiting + email confirmation) and a live session per user, returning
// {id, token} pairs ready to use as `Access-Token` headers.
async function seedUsers(count, label) {
	return mapLimit(Array.from({length: count}, (_, i) => i), 10, async () => {
		const email = `${label}-${runId}-${userCounter++}@load-test.local`;
		const userId = await withConn(async conn => {
			const result = await conn.query(
				'INSERT INTO users (email, password_hash, display_name) VALUES (?, ?, ?)',
				[email, FIXTURE_PASSWORD_HASH, `${label} ${email}`],
			);
			return Number(result.insertId);
		});
		const sessionId = crypto.randomUUID();
		await withConn(conn => conn.query(
			`INSERT INTO user_sessions (id, user_id, refresh_token_hash, expires_at)
             VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 30 DAY))`,
			[sessionId, userId, `feature-ramp-up-unused-hash-${sessionId}`],
		));
		const token = jwt.sign({id: userId, sid: sessionId}, jwtSecret, {expiresIn: '30d'});
		return {id: userId, token};
	});
}

async function firstMusicId() {
	return withConn(async conn => {
		const rows = await conn.query('SELECT id FROM musics ORDER BY id LIMIT 1');
		if (!rows.length) throw new Error('No rows in `musics` table to run the load test against');
		return Number(rows[0].id);
	});
}

async function gql(token, query, variables) {
	const started = performance.now();
	try {
		const response = await fetch(`${baseUrl}/ws`, {
			method: 'POST',
			headers: {'content-type': 'application/json', 'Access-Token': token},
			body: JSON.stringify({query, variables}),
		});
		const body = await response.json();
		const ok = response.ok && !(body.errors && body.errors.length);
		return {ok, ms: performance.now() - started, status: response.status, errors: body.errors, data: body.data};
	} catch (error) {
		return {ok: false, ms: performance.now() - started, error: String(error)};
	}
}

function describeFailure(result) {
	return JSON.stringify({status: result.status, errors: result.errors, error: result.error});
}

function percentile(values, fraction) {
	const sorted = [...values].sort((a, b) => a - b);
	return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)] || 0;
}

function summarize(scenarioName, userCount, results) {
	const durationMs = Math.max(1, Math.max(...results.map(r => r.ms)));
	const failures = results.filter(r => !r.ok).length;
	return {
		scenario: scenarioName,
		users: userCount,
		requests: results.length,
		requestsPerSecond: Number((results.length / (durationMs / 1000)).toFixed(1)),
		errors: failures,
		errorRate: Number((failures / results.length).toFixed(4)),
		p50Ms: Math.round(percentile(results.map(r => r.ms), 0.5)),
		p95Ms: Math.round(percentile(results.map(r => r.ms), 0.95)),
		p99Ms: Math.round(percentile(results.map(r => r.ms), 0.99)),
	};
}

// --- Scenario 1: track voting -------------------------------------------------
async function voteScenario(userCount, musicId) {
	const owner = (await seedUsers(1, 'vote-owner'))[0];
	const voters = await seedUsers(userCount, 'voter');

	const eventResult = await gql(owner.token, `
        mutation Setup($name: String!) { createVoteEvent(name: $name, isPublic: true, votePolicy: EVERYONE) { id } }
    `, {name: `Load test event ${runId}`});
	if (!eventResult.ok) throw new Error(`vote event setup failed: ${describeFailure(eventResult)}`);
	const eventId = eventResult.data.createVoteEvent.id;

	const suggest = await gql(owner.token, `
        mutation Suggest($eventId: Int!, $musicId: Int!) { suggestVoteTrack(eventId: $eventId, musicId: $musicId) { id } }
    `, {eventId, musicId});
	if (!suggest.ok) throw new Error(`track suggestion failed: ${describeFailure(suggest)}`);

	const query = `
        mutation Vote($eventId: Int!, $musicId: Int!) { voteForTrack(eventId: $eventId, musicId: $musicId) { id } }
    `;
	return Promise.all(voters.map(voter => gql(voter.token, query, {eventId, musicId})));
}

// --- Scenario 2: playlist editing --------------------------------------------
async function playlistScenario(userCount, musicId) {
	const editors = await seedUsers(userCount, 'editor');
	const playlists = await Promise.all(editors.map(async (editor, i) => {
		const result = await gql(editor.token, `
            mutation Setup($name: String!) { createPlaylist(name: $name, isPublic: true) { id } }
        `, {name: `Load test playlist ${runId}-${i}`});
		if (!result.ok) throw new Error(`playlist setup failed: ${describeFailure(result)}`);
		return result.data.createPlaylist.id;
	}));

	const query = `
        mutation AddTrack($playlistId: Int!, $musicId: Int!) { addTrackToPlaylist(playlistId: $playlistId, musicId: $musicId) { id } }
    `;
	return Promise.all(editors.map((editor, i) => gql(editor.token, query, {playlistId: playlists[i], musicId})));
}

// --- Scenario 3: host change / remote-control delegation ---------------------
async function hostDelegationScenario(roomPairs) {
	const hosts = await seedUsers(roomPairs, 'host');
	const friends = await seedUsers(roomPairs, 'friend');

	const rooms = await Promise.all(hosts.map(async (host, i) => {
		const created = await gql(host.token, `
            mutation Setup($name: String!) { createRoom(name: $name) { id } }
        `, {name: `Load test room ${runId}-${i}`});
		if (!created.ok) throw new Error(`room creation failed: ${describeFailure(created)}`);
		const roomId = created.data.createRoom.id;
		const joined = await gql(friends[i].token, `
            mutation Join($roomId: Int!) { joinRoom(roomId: $roomId) { id } }
        `, {roomId});
		if (!joined.ok) throw new Error(`friend join failed: ${describeFailure(joined)}`);
		return roomId;
	}));

	const query = `
        mutation Transfer($roomId: Int!, $targetUserId: Int!) { transferHost(roomId: $roomId, targetUserId: $targetUserId) { success message } }
    `;
	return Promise.all(hosts.map((host, i) => gql(host.token, query, {roomId: rooms[i], targetUserId: friends[i].id})));
}

const SCENARIOS = {
	vote: {name: 'track-vote', run: voteScenario},
	playlist: {name: 'playlist-add-track', run: playlistScenario},
	host: {name: 'host-delegation', run: (userCount) => hostDelegationScenario(userCount)},
};

(async () => {
	const selected = SCENARIOS[scenario];
	if (!selected) throw new Error(`Unknown LOAD_SCENARIO "${scenario}", expected one of: ${Object.keys(SCENARIOS).join(', ')}`);
	const musicId = await firstMusicId();
	const results = await selected.run(users, musicId);
	const summary = summarize(selected.name, users, results);
	console.log(JSON.stringify(summary, null, 2));
	await pool.end();
	const maxErrorRate = Number(process.env.LOAD_MAX_ERROR_RATE || 0.01);
	const maxP95Ms = Number(process.env.LOAD_MAX_P95_MS || 1000);
	if (summary.errorRate > maxErrorRate || summary.p95Ms > maxP95Ms) process.exitCode = 1;
})().catch(async error => {
	console.error(error);
	await pool.end();
	process.exitCode = 1;
});

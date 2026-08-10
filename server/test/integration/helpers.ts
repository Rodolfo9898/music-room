import { AddressInfo } from 'node:net';
import { Database } from '../../src/database/database';

// Integration tests always target the local Docker DB (see docker-compose.yml).
// These must be set BEFORE app.ts is loaded below: app.ts runs dotenv.config()
// at module load, and dotenv never overrides already-set variables — so this
// guarantees the tests can't accidentally hit the remote DB via server/.env.
process.env.IS_LOCAL = 'TRUE';
process.env.DB_HOST = process.env.DB_HOST || '127.0.0.1';
process.env.DB_PORT = process.env.DB_PORT || '3306';
process.env.DB_USER = process.env.DB_USER || 'music_user';
process.env.DB_PASS = process.env.DB_PASS || 'music_pass';
process.env.DB_NAME = process.env.DB_NAME || 'MusicRoom';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'integration-test-secret';
process.env.PUBLIC_URL = process.env.PUBLIC_URL || 'http://localhost';

// tslint:disable-next-line:no-var-requires
const { startApp, loadConfig } = require('../../src/app') as typeof import('../../src/app');

export interface TestServer {
	baseUrl: string;
	close: () => Promise<void>;
}

export async function startTestServer(): Promise<TestServer> {
	loadConfig();
	const { httpServer, apolloServer } = await startApp(false);
	await new Promise<void>(resolve => httpServer.listen(0, resolve));
	const { port } = httpServer.address() as AddressInfo;
	return {
		baseUrl: `http://127.0.0.1:${port}`,
		close: async () => {
			await apolloServer.stop();
			await new Promise<void>(resolve => httpServer.close(() => resolve()));
			await Database.end();
		},
	};
}

export function uniqueEmail(prefix: string): string {
	return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 100000)}@example.com`;
}

export async function postJson(url: string, body: unknown, token?: string): Promise<Response> {
	return fetch(url, {
		method: 'POST',
		headers: {
			'content-type': 'application/json',
			...(token ? { 'Access-Token': token } : {}),
		},
		body: JSON.stringify(body),
	});
}

// Runs a GraphQL operation over the HTTP endpoint
export async function gql<T = any>(baseUrl: string, query: string, token?: string): Promise<T> {
	const response = await postJson(`${baseUrl}/ws`, { query }, token);
	const body = await response.json() as { data?: T; errors?: { message: string }[] };
	if (body.errors?.length) {
		throw new Error(`GraphQL error: ${body.errors.map(e => e.message).join('; ')}`);
	}
	return body.data as T;
}

export async function getEmailConfirmationToken(email: string): Promise<string | null> {
	const rows = await Database.query<{ email_confirmation_token: string | null }>(
		'SELECT email_confirmation_token FROM users WHERE email = ?',
		email,
	);
	return rows.length > 0 ? rows[0].email_confirmation_token : null;
}

export async function createConfirmedUser(
	baseUrl: string,
	email: string,
	password: string,
): Promise<{ token: string; accountId: number }> {
	const signupResponse = await postJson(`${baseUrl}/accounts/signup`, {
		email,
		password,
		displayName: 'grader',
	});
	if (signupResponse.status !== 201) {
		throw new Error(`signup failed: ${signupResponse.status} ${await signupResponse.text()}`);
	}

	const confirmationToken = await getEmailConfirmationToken(email);
	if (!confirmationToken) {
		throw new Error(`no confirmation token found for ${email}`);
	}
	const confirmResponse = await fetch(
		`${baseUrl}/accounts/confirm-email?token=${encodeURIComponent(confirmationToken)}`,
	);
	if (confirmResponse.status !== 200) {
		throw new Error(`email confirmation failed: ${confirmResponse.status}`);
	}

	const loginResponse = await postJson(`${baseUrl}/accounts/login`, { email, password });
	if (loginResponse.status !== 200) {
		throw new Error(`login failed: ${loginResponse.status} ${await loginResponse.text()}`);
	}
	const envelope = await loginResponse.json() as { data: { token: string; accountId: number } };
	const payload = envelope.data;
	return { token: payload.token, accountId: payload.accountId };
}

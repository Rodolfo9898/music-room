/** One inbound or outbound message across any transport (HTTP, GraphQL, WS). */
export interface AccessLogEntry {
	transport: 'http' | 'graphql' | 'ws';
	direction: 'in' | 'out';
	/** e.g. "POST /accounts/login" | "mutation play" | "subscribe roomState" */
	operation: string;
	userId?: number | null;
	/** HTTP status code | "ok"/"error" | "complete" */
	status?: number | string;
	durationMs?: number;
	/** Inbound payload (request body / variables). Sanitize before passing. */
	body?: unknown;
	/** Outbound payload (response). Sanitize before passing. */
	response?: unknown;
	error?: unknown;
}

const SENSITIVE_KEYS = ['password', 'token', 'accesstoken', 'access-token', 'authorization', 'jwt', 'cookie', 'cookies'];
const HTTP_STATUS_SERVER_ERROR = 500;
const HTTP_STATUS_CLIENT_ERROR = 400;

type AccessSeverity = 'ERROR' | 'WARNING' | 'INFO';

// Determine the severity of an access log entry based on its status/error
function severityFor(entry: AccessLogEntry): AccessSeverity {
	const httpStatus = typeof entry.status === 'number' ? entry.status : undefined;
	if (entry.error || entry.status === 'error' || (httpStatus !== undefined && httpStatus >= HTTP_STATUS_SERVER_ERROR)) {
		return 'ERROR';
	}
	if (httpStatus !== undefined && httpStatus >= HTTP_STATUS_CLIENT_ERROR) {
		return 'WARNING';
	}
	return 'INFO';
}

export function sanitize(value: unknown): unknown {
	if (value === null || typeof value !== 'object') {
		return value;
	}
	if (Array.isArray(value)) {
		return value.map(sanitize);
	}
	const result: Record<string, unknown> = {};
	for (const [key, fieldValue] of Object.entries(value as Record<string, unknown>)) {
		const normalizedKey = key.toLowerCase();
		result[key] = SENSITIVE_KEYS.includes(normalizedKey) || normalizedKey.endsWith('token')
			? '[SECRET]'
			: sanitize(fieldValue);
	}
	return result;
}

export class Logger {
	static report(err: unknown, _request?: unknown, customMessage?: string, _callback?: unknown) {
		console.error(JSON.stringify({
			type: 'error',
			message: customMessage ?? (err instanceof Error ? err.message : String(err)),
			stack: err instanceof Error ? err.stack : undefined,
			timestamp: new Date().toISOString(),
		}));
	}

	static access(entry: AccessLogEntry) {
		// Structured stdout is collected by Docker/Kubernetes and can be routed to
		// any production log backend without vendor credentials in the process.
		console.log(JSON.stringify({
			type: 'access',
			severity: severityFor(entry),
			timestamp: new Date().toISOString(),
			...entry,
		}));
	}

	// Structured debug logging for diagnosing business-logic decisions (e.g. why a
	// vote-eligibility check failed) without exposing that detail to API clients.
	static debug(message: string, context?: Record<string, unknown>) {
		console.debug(JSON.stringify({
			type: 'debug',
			message,
			timestamp: new Date().toISOString(),
			...context,
		}));
	}
}

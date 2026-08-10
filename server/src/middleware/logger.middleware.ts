import { NextFunction, Request, Response } from 'express';
import { Logger, sanitize } from '../utils/logger';
import { ApolloServerPlugin } from '@apollo/server';
import { Database } from '../database/database';

export interface ClientMetadata {
	platform: string;
	device: string;
	appVersion: string;
	deviceKey: string;
}

export function clientMetadataFromHeaders(headers: Record<string, unknown>): ClientMetadata {
	const value = (name: string) => String(headers[name] ?? headers[name.toLowerCase()] ?? 'unknown').slice(0, 190);
	return {
		platform: value('x-client-platform'),
		device: value('x-client-device'),
		appVersion: value('x-app-version'),
		deviceKey: value('x-device-key'),
	};
}

export function persistMobileAction(
	metadata: ClientMetadata,
	entry: { userId?: number | null; transport: string; operation: string; status?: string | number; durationMs?: number },
): void {
	if (metadata.platform === 'unknown' && metadata.device === 'unknown') return;
	void Database.query(
		`INSERT INTO mobile_action_logs
		 (user_id, transport, operation, platform, device, app_version, status, duration_ms)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		entry.userId ?? null,
		entry.transport,
		entry.operation.slice(0, 190),
		metadata.platform,
		metadata.device,
		metadata.appVersion,
		entry.status == null ? null : String(entry.status),
		entry.durationMs ?? null,
	).catch(error => Logger.report(error));
}

export function httpLoggerMiddleware(req: Request, res: Response, next: NextFunction) {
	const startedAt = Date.now();
	const operation = `${req.method} ${req.path}`;
	const userId = () => (req as { accountId?: number }).accountId ?? null;
	const metadata = clientMetadataFromHeaders(req.headers as Record<string, unknown>);

	Logger.access({ transport: 'http', direction: 'in', operation, userId: userId(), body: sanitize(req.body) });

	let body: unknown;
	let captured = false;
	const capture = <T>(send: (payload: T) => Response) => (payload: T) => {
		if (!captured) { body = payload; captured = true; }
		return send(payload);
	};
	res.json = capture(res.json.bind(res));
	res.send = capture(res.send.bind(res));

	res.on('finish', () => {
		const durationMs = Date.now() - startedAt;
		Logger.access({
			transport: 'http',
			direction: 'out',
			operation,
			userId: userId(),
			status: res.statusCode,
			durationMs,
			response: captured ? sanitize(body) : '[stream]',
		});
		persistMobileAction(metadata, { transport: 'http', operation, userId: userId(), status: res.statusCode, durationMs });
	});

	next();
}

export const apolloLoggerPlugin: ApolloServerPlugin = {
    async requestDidStart(requestContext) {
        const startedAt = Date.now();
		const graphqlContext = requestContext.contextValue as { user?: { id?: number }; client?: ClientMetadata };
		const userId = graphqlContext.user?.id ?? null;
        const operation = requestContext.request.operationName ?? 'anonymous';

        Logger.access({ transport: 'graphql', direction: 'in', operation, userId, body: sanitize(requestContext.request.variables) });

        return {
            async willSendResponse(responseContext) {
                const errors = responseContext.errors ?? [];
                Logger.access({
                    transport: 'graphql',
                    direction: 'out',
                    operation,
                    userId,
                    status: errors.length ? 'error' : 'ok',
				durationMs: Date.now() - startedAt,
                    error: errors.length ? errors.map((graphqlError) => graphqlError.message) : undefined,
                });
				persistMobileAction(graphqlContext.client ?? {
					platform: 'unknown', device: 'unknown', appVersion: 'unknown', deviceKey: 'unknown',
				}, {
					transport: 'graphql', operation, userId,
					status: errors.length ? 'error' : 'ok', durationMs: Date.now() - startedAt,
				});
            },
        };
    },
};

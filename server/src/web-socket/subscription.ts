import { WebSocketServer } from 'ws';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { useServer } = require('graphql-ws/use/ws');
import { GraphQLSchema } from 'graphql';
import * as http from 'node:http';
import { roomStore } from '../rooms/room.store';
import { AccountPreController } from '../api/accounts/account.pre.controller';
import { ClientMetadata, clientMetadataFromHeaders, persistMobileAction } from '../middleware/logger.middleware';
import { Logger, sanitize } from '../utils/logger';

export interface SubscriptionContext {
	user: { id: number } | null;
	joinedRoomIds: Set<number>;
	client: ClientMetadata;
}

interface ConnectionExtra {
	user?: { id: number };
	joinedRoomIds?: Set<number>;
	client?: ClientMetadata;
}

interface ConnectionContext {
	extra: ConnectionExtra;
	connectionParams?: Record<string, unknown>;
}

export function setupWebSocketServer(httpServer: http.Server, schema: GraphQLSchema) {
	const webSocketServer = new WebSocketServer({
		noServer: true,
	});

	useServer(
		{
			schema,
			onConnect: async (context: ConnectionContext) => {
				const token = extractConnectionToken(context);
				if (!token) {
					throw new Error('token not found');
				}
				const account = await AccountPreController.getAccount(token);
				if (!account) {
					throw new Error('invalid token');
				}
				context.extra.user = { id: Number(account.id) };
				context.extra.joinedRoomIds = new Set<number>();
				context.extra.client = extractClientMetadata(context);
				return true;
			},
			onSubscribe: (context: ConnectionContext, _id: string, payload: { operationName?: string; query?: string; variables?: unknown }) => {
				const operation = payload.operationName || operationFromQuery(payload.query) || 'anonymous';
				const userId = context.extra.user?.id ?? null;
				Logger.access({ transport: 'ws', direction: 'in', operation, userId, body: sanitize(payload.variables) });
				persistMobileAction(context.extra.client ?? unknownClient(), { transport: 'ws', operation, userId, status: 'received' });
			},
			onNext: (context: ConnectionContext, _id: string, payload: { operationName?: string; query?: string }) => {
				const operation = payload.operationName || operationFromQuery(payload.query) || 'anonymous';
				Logger.access({ transport: 'ws', direction: 'out', operation, userId: context.extra.user?.id ?? null, status: 'ok' });
			},
			onDisconnect: (context: ConnectionContext) => {
				const userId = context.extra?.user?.id;
				const joinedRoomIds = context.extra?.joinedRoomIds;
				if (!userId || !joinedRoomIds) return;
				for (const roomId of joinedRoomIds) {
					roomStore.schedulePendingLeave(roomId, userId);
				}
				joinedRoomIds.clear();
			},
			context: (context: ConnectionContext) => {
				return {
					user: context.extra?.user ?? null,
					joinedRoomIds: context.extra?.joinedRoomIds ?? new Set<number>(),
					client: context.extra?.client ?? unknownClient(),
				} as SubscriptionContext;
			},
		},
		webSocketServer,
	);

	return { webSocketServer };
}

export function setupDevWebSocketServer(httpServer: http.Server, schema: GraphQLSchema) {
	const devWebSocketServer = new WebSocketServer({
		noServer: true,
	});

	useServer(
		{
			schema,
			context: () => {
				return {
					user: null,
					joinedRoomIds: new Set<number>(),
					client: unknownClient(),
				} as SubscriptionContext;
			},
		},
		devWebSocketServer,
	);

	return { devWebSocketServer };
}

export function handleUpgrade(
	httpServer: http.Server,
	authWss: InstanceType<typeof WebSocketServer>,
	devWss?: InstanceType<typeof WebSocketServer>,
) {
	httpServer.on('upgrade', (request, socket, head) => {
		const { pathname } = new URL(request.url || '', `http://${request.headers.host}`);

		if (pathname === '/subscriptions') {
			authWss.handleUpgrade(request, socket, head, (ws) => {
				authWss.emit('connection', ws, request);
			});
		} else if (devWss && pathname === '/dev-subscriptions') {
			devWss.handleUpgrade(request, socket, head, (ws) => {
				devWss.emit('connection', ws, request);
			});
		} else {
			socket.destroy();
		}
	});
}

function extractConnectionToken(context: ConnectionContext): string | null {
	const params = context.connectionParams ?? {};
	const directToken = firstString(params['Access-Token'])
		?? firstString(params['access-token'])
		?? firstString(params['accessToken']);
	if (directToken) {
		return stripBearerPrefix(directToken);
	}

	const authorization = firstString(params['Authorization'])
		?? firstString(params['authorization']);
	if (authorization) {
		return stripBearerPrefix(authorization);
	}

	const headers = params['headers'];
	if (headers && typeof headers === 'object') {
		const headerMap = headers as Record<string, unknown>;
		const headerToken = firstString(headerMap['Access-Token'])
			?? firstString(headerMap['access-token'])
			?? firstString(headerMap['accessToken']);
		if (headerToken) {
			return stripBearerPrefix(headerToken);
		}

		const headerAuthorization = firstString(headerMap['Authorization'])
			?? firstString(headerMap['authorization']);
		if (headerAuthorization) {
			return stripBearerPrefix(headerAuthorization);
		}
	}

	return null;
}

function firstString(value: unknown): string | null {
	if (typeof value === 'string' && value.trim()) {
		return value.trim();
	}
	return null;
}

function stripBearerPrefix(value: string): string {
	return value.replace(/^Bearer\s+/i, '').trim();
}

function extractClientMetadata(context: ConnectionContext): ClientMetadata {
	const params = context.connectionParams ?? {};
	const nested = params.headers && typeof params.headers === 'object' ? params.headers as Record<string, unknown> : {};
	return clientMetadataFromHeaders({ ...nested, ...params });
}

function unknownClient(): ClientMetadata {
	return { platform: 'unknown', device: 'unknown', appVersion: 'unknown', deviceKey: 'unknown' };
}

function operationFromQuery(query?: string): string | null {
	if (!query) return null;
	return query.match(/(?:query|mutation|subscription)\s+([A-Za-z0-9_]+)/)?.[1] ?? null;
}

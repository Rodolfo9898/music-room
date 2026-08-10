import dotenv from 'dotenv';
import cookieParser from 'cookie-parser';
import cors from 'cors';
import express, { Request, Response } from 'express';
import { router } from './api/router';
import { Database } from './database/database';
import { ApolloServer } from '@apollo/server';
import { resolvers } from './web-socket/graphql';
import { ApolloServerPluginDrainHttpServer } from '@apollo/server/plugin/drainHttpServer';
import { typeDefs } from './web-socket/schema.graphql';
import * as http from 'node:http';
import { expressMiddleware } from '@as-integrations/express5';
import { AccountPreController } from './api/accounts/account.pre.controller';
import { makeExecutableSchema } from '@graphql-tools/schema';
import { httpLoggerMiddleware, apolloLoggerPlugin, clientMetadataFromHeaders } from './middleware/logger.middleware';
import { setupWebSocketServer, setupDevWebSocketServer, handleUpgrade } from './web-socket/subscription';
import swaggerUi from 'swagger-ui-express';
import { openapiSpec } from './docs/swagger';
import { globalRateLimit } from './middleware/rate-limit.middleware';

// load .env file
dotenv.config();

let initialized = false;

export async function startApp(listen: boolean = true) {
	if (initialized) {
		return null;
	}
	initialized = true;
	const app = express();

	// Connect to DB
	new Database();


	// MIDDLEWARES
	app.use(cookieParser());
	app.disable('x-powered-by');
	app.use(express.json({ limit: '64kb' }));
	app.use(express.urlencoded({extended: false, limit: '64kb'}));
	app.use('/public', express.static('public'));
	const allowedOrigins = (process.env.CORS_ORIGINS || '').split(',').map(origin => origin.trim()).filter(Boolean);
	app.use(cors({
		origin: allowedOrigins.length === 0 ? true : (origin, callback) => callback(null, !origin || allowedOrigins.includes(origin)),
		credentials: true,
	}));
	app.use((_req, res, next) => {
		res.setHeader('X-Content-Type-Options', 'nosniff');
		res.setHeader('X-Frame-Options', 'DENY');
		res.setHeader('Referrer-Policy', 'no-referrer');
		next();
	});
	app.use(globalRateLimit);
	app.use(httpLoggerMiddleware);


	// Live REST API docs
	app.get('/docs/openapi.json', (_req: Request, res: Response) => { res.json(openapiSpec); });
	app.use('/docs', swaggerUi.serveFiles(openapiSpec), swaggerUi.setup(openapiSpec));

	// Route Middlewares
	app.get('/', (req: Request, res: Response) => res.send('App V1.0 is working'));
	app.use('/', router);
	const PORT = Number(process.env.PORT);

	// TEST DATABASE CONNECTION
	await Database.testConnection();


	const httpServer = http.createServer(app);

	// Build shared schema for both HTTP and WebSocket servers
	const schema = makeExecutableSchema({ typeDefs, resolvers });

	// WebSocket server for subscriptions (JWT auth in handshake)
	const { webSocketServer: authWss } = setupWebSocketServer(httpServer, schema);

	// Dev WebSocket server (no auth) — only when DEV=true
	let devWss: InstanceType<typeof import('ws').WebSocketServer> | undefined;
	if (process.env.DEV === 'true') {
		devWss = setupDevWebSocketServer(httpServer, schema).devWebSocketServer;
		console.log('Dev WebSocket server enabled at /dev-subscriptions');
	}

	// Route WebSocket upgrades to the correct server
	handleUpgrade(httpServer, authWss, devWss);

	// Websocket graphql part
	const server = new ApolloServer({
		schema,
		plugins: [
			ApolloServerPluginDrainHttpServer({ httpServer }),
			apolloLoggerPlugin,
		],
	});
	// Note you must call `start()` on the `ApolloServer`
	// instance before passing the instance to `expressMiddleware`
	await server.start();


	app.use(
		'/ws',
		cors<cors.CorsRequest>(),
		express.json(),
		// Same context shape as the WebSocket transport (SubscriptionContext).
		// No token → user: null; resolvers enforce auth via requireUser(), which
		// keeps schema introspection (Apollo Sandbox) available.
		expressMiddleware(server, {
			context: async ({req}) => {
				const token = req.header('Access-Token') || req.cookies?.token;
				const account = token ? await AccountPreController.getAccount(token) : null;
				return {
					user: account ? { id: Number(account.id) } : null,
					joinedRoomIds: new Set<number>(),
					client: clientMetadataFromHeaders(req.headers as Record<string, unknown>),
				};
			},
		})
	);
	app.use((_req: Request, res: Response) => {
		res.status(404).json({ success: false, message: 'Page Not Found' });
	});

	if (listen) {
		httpServer.listen({port: PORT});
	}

	return { httpServer, apolloServer: server };
}

export function loadConfig() {
	global.config = {
		emailPassword: process.env.EMAILPASS,
		jwtSecret: process.env.JWT_SECRET,
		mariaDBHost: process.env.DB_HOST,
		mariaDBPort: process.env.DB_PORT,
		mariaDBUser: process.env.DB_USER,
		mariaDBPassword: process.env.DB_PASS,
		mariaDBName: process.env.DB_NAME || 'MusicRoom',
		postHogKey: process.env.POSTHOG_KEY,
		publicUrl: process.env.PUBLIC_URL
	}
}

function loadConfigAndStart() {
	loadConfig();
	startApp().then();
}


// Only auto-start when run directly, so tests can import startApp(false).
if (require.main === module) {
	loadConfigAndStart();
}

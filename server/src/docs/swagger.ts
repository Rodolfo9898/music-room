import swaggerJsdoc from 'swagger-jsdoc';
import path from 'path';

// Builds the OpenAPI spec at startup from the @openapi JSDoc blocks in the
// routers. Served by app.ts at GET /docs (Swagger UI) and /docs/openapi.json.
// GraphQL is self-documenting via Apollo Sandbox at GET /ws.
export const openapiSpec = swaggerJsdoc({
	definition: {
		openapi: '3.0.3',
		info: {
			title: 'Music Room REST API',
			version: '1.0.0',
			description: [
				'REST API of the Music Room server.',
				'',
				'Authentication uses a JWT passed either in the `Access-Token` header or in a `token` cookie.',
				'JSON endpoints consistently return `{ success, data }` or `{ success: false, message, error? }`.',
				'',
				'The GraphQL API (rooms, realtime playlists, subscriptions) is explorable at `GET /ws` (dev).',
			].join('\n'),
		},
		servers: [
			{ url: 'http://localhost:8080', description: 'Local dev server' },
		],
		tags: [
			{ name: 'Accounts', description: 'Signup, login, email confirmation, password reset, profile' },
			{ name: 'Musics', description: 'Music catalog and audio streaming' },
			{ name: 'Playlists', description: 'User playlists (REST part; realtime editing lives in GraphQL)' },
		],
		components: {
			securitySchemes: {
				accessTokenHeader: {
					type: 'apiKey', in: 'header', name: 'Access-Token',
					description: 'Short-lived JWT issued by the login endpoints.',
				},
				cookieAuth: {
					type: 'apiKey', in: 'cookie', name: 'token',
					description: 'Same JWT, sent as a cookie. The header takes precedence when both are present.',
				},
			},
			responses: {
				AuthError: {
					description: 'Missing, revoked, invalid, or expired token',
					content: { 'application/json': { schema: { $ref: '#/components/schemas/ErrorResponse' } } },
				},
			},
			schemas: {
				LoginRequest: {
					type: 'object',
					required: ['email', 'password'],
					properties: {
						email: { type: 'string', format: 'email', example: 'user@example.com' },
						password: { type: 'string', format: 'password', example: 'securePassword123' },
					},
				},
				GoogleLoginRequest: {
					type: 'object',
					required: ['idToken'],
					properties: {
						idToken: { type: 'string', description: 'Google ID token obtained from Google Sign-In on the client.' },
					},
				},
				SignupRequest: {
					type: 'object',
					required: ['email', 'password'],
					properties: {
						email: { type: 'string', format: 'email', example: 'newuser@example.com' },
						password: { type: 'string', format: 'password', example: 'securePassword123' },
						displayName: { type: 'string', description: 'Public profile name (lowercased and trimmed by the server).', example: 'john_doe' },
					},
				},
				AuthPayload: {
					type: 'object',
					required: ['token', 'accountId', 'email', 'displayName'],
					properties: {
						token: { type: 'string', description: 'JWT to send back via the `Access-Token` header or `token` cookie.' },
						accountId: { type: 'integer', example: 42 },
						email: { type: 'string', format: 'email' },
						displayName: { type: 'string' },
					},
				},
				SignupResponse: {
					type: 'object',
					required: ['accountId', 'email', 'displayName', 'message'],
					properties: {
						accountId: { type: 'integer' },
						email: { type: 'string', format: 'email' },
						displayName: { type: 'string' },
						message: { type: 'string', example: 'check your email to confirm your account' },
					},
				},
				ErrorResponse: {
					type: 'object',
					required: ['success', 'message'],
					properties: {
						success: { type: 'boolean', example: false },
						message: { type: 'string', example: 'Invalid music id' },
					},
				},
				Music: {
					type: 'object',
					properties: {
						id: { type: 'integer' },
						title: { type: 'string' },
						artist_id: { type: 'integer' },
						genre_id: { type: 'integer' },
						file_path: { type: 'string' },
						duration: { type: 'integer', description: 'Duration in seconds.' },
						streamUrl: { type: 'string', description: 'Relative URL of the audio stream for this track.', example: '/musics/7/stream' },
					},
				},
				MusicSearchResult: {
					allOf: [
						{ $ref: '#/components/schemas/Music' },
						{ type: 'object', properties: { artist_name: { type: 'string' } } },
					],
				},
				Playlist: {
					type: 'object',
					properties: {
						id: { type: 'integer' },
						name: { type: 'string' },
						owner_id: { type: 'integer' },
						is_public: { type: 'boolean' },
						edit_policy: { type: 'string', enum: ['EVERYONE', 'COLLABORATORS'] },
						version: { type: 'integer' },
						created_at: { type: 'string' },
						updated_at: { type: 'string' },
						track_count: { type: 'integer' },
						music_ids: { type: 'array', items: { type: 'integer' } },
					},
				},
			},
		},
	},
	// Resolved from cwd (= server/), which holds for npm run dev / build_app.
	apis: [path.join(process.cwd(), 'src/api/**/*.router.ts')],
}) as object;

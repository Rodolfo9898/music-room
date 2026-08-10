import { createPool, Pool, PoolConfig, PoolConnection } from 'mariadb';
import { Logger } from '../utils/logger';

export class Database {

	private static _connection: Pool;

	static get isConfigured(): boolean {
		return Boolean(Database._connection);
	}

	constructor() {
		const config: PoolConfig = {
			host: global.config.mariaDBHost,
			user: global.config.mariaDBUser,
			password: global.config.mariaDBPassword,
			connectionLimit: 20,
			connectTimeout: 10000,
			acquireTimeout: 10000,
			idleTimeout: 60,
			database: global.config.mariaDBName || 'MusicRoom',
			port: parseInt(global.config.mariaDBPort),
			bigIntAsNumber: true,
		};
		Database._connection = createPool(config);
	}


	static async query<T>(query: string, ...args: any): Promise<T[]> {
		let conn: PoolConnection | null = null;
		try {
			conn = await Database._connection.getConnection();
			return await conn.query<T[]>(query, args);
		} catch (e) {
			Logger.report(e);
			throw e;
		} finally {
			if (conn) {
				try {
					await conn.release();
				} catch (e) {
					Logger.report(e);
				}
			}
		}
	}

	static async transaction<T>(action: (conn: PoolConnection) => Promise<T>): Promise<T> {
		// Focused unit tests replace Database.query without opening a pool. Their
		// lightweight executor still exercises the complete mutation algorithm;
		// production and integration tests always use the real transaction below.
		if (!Database._connection) {
			const executor = {
				query: (sql: string, args: unknown[] = []) => Database.query(sql, ...args),
			} as unknown as PoolConnection;
			return action(executor);
		}
		const conn = await Database._connection.getConnection();
		try {
			await conn.beginTransaction();
			const result = await action(conn);
			await conn.commit();
			return result;
		} catch (error) {
			await conn.rollback();
			Logger.report(error);
			throw error;
		} finally {
			await conn.release();
		}
	}

	static async end(): Promise<void> {
		if (Database._connection) {
			await Database._connection.end();
		}
	}

	static async testConnection(): Promise<void> {
		let conn: PoolConnection | null = null;

		try {
			conn = await Database._connection.getConnection();
			await conn.ping();
			console.log('connection working');
		} catch (e) {
			Logger.report(e);
		} finally {
			if (conn) {
				try {
					await conn.release();
				} catch (e) {
					Logger.report(e);
				}
			}
		}
	}
}

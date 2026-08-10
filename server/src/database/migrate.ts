import dotenv from 'dotenv';
import fs from 'node:fs';
import path from 'node:path';
import { createConnection, Connection } from 'mariadb';

// Standalone migration runner: `npm run db:migrate` (ts-node).
// Uses its own connection instead of Database.query, which swallows errors —
// a failed migration must be loud and stop the run.

dotenv.config();

const MIGRATIONS_DIR = path.resolve(__dirname, 'migrations');

async function migrate(): Promise<void> {
	let conn: Connection | null = null;
	try {
		conn = await createConnection({
			host: process.env.DB_HOST || '127.0.0.1',
			port: parseInt(process.env.DB_PORT || '3306'),
			user: process.env.DB_USER,
			password: process.env.DB_PASS,
			database: process.env.DB_NAME || 'MusicRoom',
			multipleStatements: true,
			connectTimeout: 10000,
		});

		await conn.query(`
			CREATE TABLE IF NOT EXISTS schema_migrations (
				id         VARCHAR(255) PRIMARY KEY,
				applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
		`);

		const applied: { id: string }[] = await conn.query('SELECT id FROM schema_migrations');
		const appliedIds = new Set(applied.map(row => row.id));

		const files = fs.readdirSync(MIGRATIONS_DIR)
			.filter(file => file.endsWith('.sql'))
			.sort();

		let appliedCount = 0;
		for (const file of files) {
			if (appliedIds.has(file)) {
				continue;
			}
			const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
			try {
				await conn.query(sql);
			} catch (e) {
				console.error(`Migration failed: ${file}`);
				throw e;
			}
			await conn.query('INSERT INTO schema_migrations (id) VALUES (?)', [file]);
			console.log(`Applied ${file}`);
			appliedCount++;
		}

		if (appliedCount === 0) {
			console.log('Nothing to apply, database is up to date');
		} else {
			console.log(`Applied ${appliedCount} migration(s)`);
		}
	} finally {
		if (conn) {
			await conn.end();
		}
	}
}

migrate().catch(e => {
	console.error(e);
	process.exit(1);
});

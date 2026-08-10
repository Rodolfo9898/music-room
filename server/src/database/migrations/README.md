# Migrations — quick guide

## Run migrations

```sh
cd server && npm run db:migrate   # uses the DB_* values from .env
```

The runner applies the `*.sql` files in this folder in order, and records the applied ones in the `schema_migrations` table — re-running the command never applies the same migration twice.

Local database: start it first with `docker compose up -d --wait` (or `make db-up`), with `.env` pointing at `127.0.0.1`.

## Add a migration

1. Create the next file in order: `003-my-change.sql` (number + short name).
2. Write **idempotent** SQL (safe to re-run without errors):
   - `CREATE TABLE IF NOT EXISTS ...`
   - `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`
   - `INSERT IGNORE ...`
3. Run `npm run db:migrate` locally and verify.
4. Commit. Every team member (and the OVH server) applies the migration with the same command.

## Current files

| File | Contents |
| --- | --- |
| `001-base-schema.sql` | Full structure (copied from the OVH database) |
| `002-seed-catalog.sql` | Seed data: 14 artists, 10 genres, 14 musics |
| `005-multi-vote.sql` | Widens `vote_event_votes` PK so a user can vote for multiple tracks per event |

⚠️ Never edit a migration that others have already applied — create a new one instead.

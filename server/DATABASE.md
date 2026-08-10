# Database setup

MariaDB is initialized exclusively by the ordered migrations in
`src/database/migrations`. They are idempotent and recorded in
`schema_migrations`; do not apply ad-hoc SQL files.

From the repository root:

```sh
make setup
```

For production operation of database + backend services, use the runbook in
[`docs/PRODUCTION.md`](RUN.md).

Or start MariaDB and migrate explicitly:

```sh
make db-up
make db-migrate
```

Connection settings are read from the ignored `server/.env`. Copy
`server/.env-example`, provide strong local values, and keep it untracked.
Compose-first local usage expects `DB_HOST=mariadb`. For a remote database host,
set `DB_HOST`/`DB_PORT`/credentials accordingly and run backend with
`make run-server REMOTE_DB=1`.
`npm run db:migrate` applies all pending migrations and the initial catalog
seed. `make db-reset` removes the Docker database volume and reconstructs it
from those migrations.

The schema covers accounts and privacy tiers, rotating sessions, friends,
registered devices, mobile action logs, ordered collaborative playlists, live
rooms, and track-voting events. Playlist mutations use an InnoDB transaction,
row lock, and optimistic version; votes use a unique `(event_id, user_id)` key
inside a transaction so one user can hold exactly one vote per event.

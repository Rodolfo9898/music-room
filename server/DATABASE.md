# Database setup

MariaDB is initialized exclusively by the ordered migrations in
`src/database/migrations`. They are idempotent and recorded in
`schema_migrations`; do not apply ad-hoc SQL files.

From the repository root:

```sh
make setup
```

Or start MariaDB and migrate explicitly:

```sh
make db-up
make db-migrate
```

Connection settings are read from the ignored `server/.env`. Copy
`server/.env-example`, provide strong local values, and keep it untracked.
`npm run db:migrate` applies all pending migrations and the initial catalog
seed. `make db-reset` removes the Docker database volume and reconstructs it
from those migrations.

The schema covers accounts and privacy tiers, rotating sessions, friends,
registered devices, mobile action logs, ordered collaborative playlists, live
rooms, and track-voting events. Playlist mutations use an InnoDB transaction,
row lock, and optimistic version; votes use a unique `(event_id, user_id)` key
inside a transaction so one user can hold exactly one vote per event.

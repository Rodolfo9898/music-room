# Production runbook (MariaDB + backend API)

This runbook covers production operation for:

- MariaDB (`mariadb` service)
- Node.js backend API (`backend` service)

It does **not** cover hosting the Flutter app in production. Keep app runtime in
the local/mobile workflow described in the root `README.md`.

## 1) Prerequisites

1. Docker Engine and Docker Compose plugin installed on the host.
2. A checked-out repository copy on the host.
3. Ports available:
   - `8080` (backend API)

## 2) Create and secure `server/.env`

`server/.env` is ignored by git and is the single source of runtime settings for
both `mariadb` and `backend` in `docker-compose.yml`.

Create it from the example:

```sh
cp ./.env-example server/.env
```

Set at least the following before first start:

- `JWT_SECRET`: long random value
- `DB_USER`, `DB_PASS`, `DB_NAME`
- `MARIADB_ROOT_PASSWORD`, `MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD`
- `PUBLIC_URL`: public API base URL
- `PORT=8080`
- `DB_HOST=mariadb` when running backend in compose

Keep `.env` untracked and rotate secrets through your deployment process.

## 3) First boot (ordered)

From repository root:

```sh
make musics # or unzip the musics.zip into server/musics
make db-up
make db-migrate
make backend-up
```

What each step does:

- `make musics`: extracts `server/musics.zip` into `server/musics/`
- `make db-up`: starts MariaDB and waits for healthy state
- `make db-migrate`: applies all pending migrations + default seed
- `make backend-up`: builds/starts backend (and ensures DB dependency)

## 4) Verify runtime health

1. Check containers:

   ```sh
   docker compose ps
   ```

2. Check API response:

   ```sh
   curl -fsS http://127.0.0.1:8080/ >/dev/null
   ```

3. Check API docs:

   ```sh
   curl -fsS http://127.0.0.1:8080/docs >/dev/null
   ```

## 5) Daily operations

### Restart services

```sh
docker compose restart mariadb backend
```

### Pull code + rebuild backend

```sh
git pull
make backend-up
make db-migrate
```

### Stop services gracefully

```sh
make project-down
```

## 6) Backups and restore basics

Use `mysqldump` for logical backups and keep dumps off-host.

Example backup:

```sh
docker compose exec mariadb sh -lc 'mysqldump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' > music-room-backup.sql
```

Example restore (into an empty/recreated DB):

```sh
docker compose exec -T mariadb sh -lc 'mysql -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' < music-room-backup.sql
```

Do not run `make db-reset` in production; it removes the DB volume.

## 7) App runtime scope boundary

For Android/mobile development and testing, continue using:

```sh
make run-project
```

or:

```sh
make run-app
```

Those are local/dev flows and are not part of production API+DB hosting.

## 8) Troubleshooting

- **`mariadb` not healthy**
  - inspect logs: `docker compose logs mariadb`
  - verify DB env values in `server/.env` (user/password/database)
- **Migration failed**
  - inspect: `docker compose run --rm backend npm run db:migrate`
  - resolve schema/data issue, then rerun migration
- **Backend healthcheck failing**
  - inspect logs: `docker compose logs backend`
  - ensure `DB_HOST=mariadb` and DB is healthy
- **Port conflicts (`8080`)**
  - free port or remap in `docker-compose.yml` and keep clients/proxy aligned

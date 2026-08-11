# Music Room

Flutter Android/web client plus a Node.js, GraphQL/WebSocket, and MariaDB
backend for shared playlists, live rooms, and track-voting events.

## Env config

Create the `server/.env` and `app/.env` files from the respective `.env-example` file and set the required values.

## Run server and DB

Use [server/RUN.md](server/RUN.md) for the full runbook (env preparation,
migrations, startup, health checks, update/restart, and shutdown).

Quick start: Do steps 1, 2 and 3 of the server runbook.

## Run the app

Use [app/RUN.md](app/RUN.md) for the full app runbook (Flutter setup,
configuration, and platform-specific run flows).

Quick start: Do steps 1 to 5 of the app runbook.


## Run the tests

Use [server/RUN.md](server/RUN.md) and [app/integration_test/README.md](app/integration_test/README.md)
for the complete test runbook and environment prerequisites.

If you prefer root-level Make commands, list available targets with `make help`
and use the test-related target names from your local setup.

Or run directly in each project:
- `cd server && npm test`
- `cd app && flutter test`
- `cd app && flutter test integration_test`

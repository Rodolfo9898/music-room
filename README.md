# Music Room

Flutter Android/web client plus a Node.js, GraphQL/WebSocket, and MariaDB
backend for shared playlists, live rooms, and track-voting events.

## Run locally

Install Docker, Flutter, the Android SDK, and create the `MusicRoom_API_36`
emulator. Then:

```sh
make setup
make run-project
```

`make setup` creates ignored local environment files from their examples when
missing; fill the JWT/database values in `server/.env` and optional Google OAuth
client IDs in `app/.env`. `make run-project` builds/starts MariaDB and the
backend, boots the emulator, waits for Android, and runs Flutter against
`10.0.2.2:8080`.

Useful checks are `make test-server`, `make test-integration`, and, from `app`,
`flutter analyze && flutter test`. API documentation is served at
`http://localhost:8080/docs`; practical GraphQL examples and operation names are
in [docs/API.md](docs/API.md). Database setup is documented in
[server/DATABASE.md](server/DATABASE.md).

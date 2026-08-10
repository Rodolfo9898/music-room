# Music Room API reference

The canonical local URL is `http://localhost:8080`. Interactive OpenAPI is at
`GET /docs`, the JSON contract at `GET /docs/openapi.json`, and Apollo's
GraphQL explorer at `GET /ws`. Mobile clients configure the host with the
`MUSIC_ROOM_SERVER` Dart define. All JSON REST responses use either
`{"success":true,"data":...}` or
`{"success":false,"message":"...","error":"optional-code"}`. The email
confirmation and password reset browser pages intentionally return HTML.

Authentication uses the short-lived JWT in `Access-Token`. Login also returns
a one-use refresh token; send it to `POST /accounts/refresh`. Refresh rotation
invalidates the prior token. `POST /accounts/logout` revokes the server-side
session.

## Account REST operations

| Method and path | Purpose |
|---|---|
| `POST /accounts/signup` | Create email account and send confirmation |
| `POST /accounts/login`, `/accounts/login/google` | Authenticate |
| `POST /accounts/refresh`, `/accounts/logout` | Rotate or revoke session |
| `POST /accounts/forgot-password` | Send one-hour reset link |
| `GET /accounts/me`, `PATCH /accounts/me`, `DELETE /accounts/me` | Read/edit/delete self |
| `POST /accounts/me/google` | Link Google account |
| `PATCH /accounts/me/preferences` | Replace genre preferences |
| `GET /accounts/users/:id/profile` | Privacy-filtered user profile |
| `GET/POST /accounts/me/friends` | List/request friends |
| `POST /accounts/me/friends/:id/accept`, `DELETE .../:id` | Accept/remove friend |
| `GET/POST /accounts/me/devices` | List/register devices |
| `PATCH/DELETE /accounts/me/devices/:id` | Change/remove device permission |
| `POST/DELETE /accounts/me/devices/:id/delegates/:friendId` | Grant/revoke a friend's control of a device |
| `GET /accounts/me/resources` | Friends, accessible playlists, devices |
| `GET /musics`, `GET /musics/search`, `GET /musics/:id/stream` | Catalog/audio |
| `/playlists` REST routes | Accessible playlists and track changes |

## GraphQL and WebSocket

Send GraphQL operations to `POST /ws`; realtime operations use
`ws://localhost:8080/subscriptions` with the `graphql-transport-ws` protocol.
Both transports accept `Access-Token`. The app additionally sends
`X-Client-Platform`, `X-Client-Device`, `X-App-Version`, and `X-Device-Key`.

The `me` query returns the authenticated account id; `musics` and
`searchMusics(query)` mirror the REST catalog/search endpoints for GraphQL
clients.

Playlist discovery/editing uses `myPlaylists`, `searchPlaylists(query)`,
`playlist(id)`, `createPlaylist`, `addTrackToPlaylist`,
`removeTrackFromPlaylist`, `moveTrackInPlaylist`, `updatePlaylistVisibility`,
`updatePlaylistEditPolicy`, `invitePlaylistCollaborator`, and
`playlistUpdated(playlistId)`. Despite its historical name, `myPlaylists`
returns every playlist the authenticated user may access: public, owned, or
explicitly shared.

Track voting uses `voteEvents`, `searchVoteEvents(query)`, `voteEvent(id)`,
`createVoteEvent`, `deleteVoteEvent`, `inviteVoteEventUser`,
`removeVoteEventUser`, `suggestVoteTrack`, `voteForTrack`,
`voteEventsUpdated`, and `voteEventUpdated(id)`. Policies are `EVERYONE`,
`INVITED`, and `LOCATION_TIME`; the last policy requires a `location` text
value (resolved server-side into coordinates via OpenStreetMap Nominatim
geocoding), a radius, and an active start/end interval. The backend ranks tracks by vote count.
`voteForTrack` toggles a user's vote on a track atomically: calling it again
for the same track removes that vote, and a user may back any number of
different tracks in the same event simultaneously (`user_vote_music_ids`
lists all tracks the caller currently backs).
The event owner can send the current ranked music IDs to the authoritative live
room with `setQueue`; that mutation starts playback in vote order and publishes
the resulting room state to every connected member.

Room remote control uses `createRoom`, `joinRoom`, `leaveRoom`, `deleteRoom`,
`transferHost`, `addToQueue`, `setQueue`, `play`, `pause`, `next`, `previous`,
`seek`, `linkVoteEvent`, `unlinkVoteEvent`, `room(id)`, `rooms`, and the
`roomState(roomId)` and `rooms` subscriptions. The server's room state is
authoritative and clients subscribe to it. When an owner grants an accepted
friend control of the device hosting a room, the same control mutations are
authorized for that friend. `linkVoteEvent`/`unlinkVoteEvent` attach or detach
a vote event from a room so its ranked tracks can be sent to `setQueue`, and
`transferHost`/`deleteRoom` let the host hand off or tear down a room
explicitly (in addition to the automatic handoff/teardown on disconnect).
Track audio is streamed to room members via the `streamMusic(roomId)`
subscription as base64 `MusicChunk` payloads.

Full input and return-field definitions remain introspectable in Apollo and in
`server/src/web-socket/schema.graphql.ts`.

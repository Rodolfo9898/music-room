# E2E test suite

This directory contains end-to-end test suites for Music Room, driving the
real app UI through Flutter's official
[`integration_test`](https://docs.flutter.dev/testing/integration-tests)
package — no extra native tooling (e.g. Patrol) is required.

## `account_lifecycle_test.dart`

Covers the full account lifecycle:

1. **Signup** with a real email address
2. **Mail validation** — the suite fetches the real confirmation email over
   IMAP and "clicks" the link (an HTTP GET), just like a real user would
3. **Signin**
4. **Change profile settings** — display name and music genre preferences
5. **Delete profile**

## `playlist_lifecycle_test.dart`

Covers Playlist functionality, reusing the same signup/mail-validation/signin
setup (a fresh account is created and deleted per run):

1. **Create a playlist** from the "My playlists" screen
2. **Add a track** via the playlist's own in-screen "Add" search sheet
3. **Add a track to that playlist from the Search screen's "Add to
   playlist" sheet** (the second entry point into the same mutation)
4. **Create a brand-new playlist directly from the Search screen's "Add to
   playlist" sheet** (its inline "Create new playlist" form)
5. **Reorder tracks** by dragging a track's drag handle in the
   `SliverReorderableList`
6. **Toggle visibility** (public/private) and **edit policy**
   (everyone/collaborators-only)
7. **Invite a collaborator** (submission only — no second account is used to
   accept the invite; it self-invites the same test account since only one
   confirmed account is available in this environment)
8. **Remove tracks**, then **delete the profile** as cleanup, which relies on
   both playlists created during the run being deleted via cascade when the
   owning account is deleted (there is no standalone "delete playlist"
   mutation in the app yet)

This suite assumes the seeded music catalog from
`server/src/database/migrations/002-seed-catalog.sql` is present — it
specifically searches for and references "Gangnam Style" (id 5), "Hey
Brother" (id 2), and "Palladio" (id 6).

## `track_vote_lifecycle_test.dart`

Covers the Track Vote feature (subject V.2.1 "Music Track Vote"): visibility
management (public/private events), voting license management (EVERYONE /
INVITED / LOCATION_TIME), suggesting and voting for tracks, and the
"competition" problematics called out in the subject (a track that gets more
votes ranks higher; a user's vote is atomic and switching it doesn't double
count).

Unlike the other two suites, this one needs **two distinct accounts** to
properly exercise visibility/license enforcement (owner vs. an outside/
invited user), so it signs up a **second, dedicated real mailbox**
(`TestEnv.secondTestEmail`, defaulting to a project-only test address) on
the same mail server as the primary mailbox. Both accounts are deleted at
the end of the run.

1. **Signup/mail validation/signin** as the owner account.
2. **Public EVERYONE-policy event**: suggest two tracks, vote for one
   (verify it moves to the top of the ranking), then switch the vote to the
   other track (verify the switch is atomic — the previous choice loses its
   vote and the newly voted track takes the lead).
3. **Private INVITED-policy event**: the owner suggests a track without
   voting.
4. **LOCATION_TIME dropdown smoke check**: opens the create-event dialog,
   selects the `LOCATION_TIME` policy option to confirm it exists and is
   selectable, then cancels — this suite intentionally does **not** drive
   real device geolocation or handle OS permission prompts, to keep the run
   deterministic and CI-friendly.
5. Logs out, then **signs up a second (voter) account** and confirms:
   - the public event **is** discoverable (any user can find/vote on a
     public event);
   - the private event **is not** discoverable yet (only invited users can
     find a private event).
   - voting on the public event as the voter aggregates correctly alongside
     the owner's earlier vote (no double counting across users).
6. Logs back in as the **owner**, invites the voter's email to the private
   event, and confirms the success message.
7. Logs back in as the **voter**, confirms the private event is now
   discoverable and votable, and votes on it.
8. **Cleanup**: deletes the voter account, logs back in as the owner, and
   deletes the owner account too (cascades both voting events).

## Track Vote regression matrix (visibility × policy × time × location)

Three additional, focused suites cover every visibility/policy/time/location
*configuration* of a vote event (subject V.2.1's "voting license"), asserting
only the eligibility outcome (allowed / denied + exact reason) per
configuration rather than deep-diving into ranking/aggregation like
`track_vote_lifecycle_test.dart` does. Together they cover 16 flows:

**`track_vote_visibility_policy_regression_test.dart`** — PUBLIC/PRIVATE ×
EVERYONE/INVITED (the owner can always vote on their own event under any of
these 4 combinations), plus:
- a non-invited stranger can't discover *any* private event, regardless of
  policy (`NOT_VIEWABLE`);
- a non-invited stranger on a **public** INVITED event can see it (public
  events are always discoverable) but is denied voting (`NOT_INVITED`)
  until the owner invites them, after which they can vote.

**`track_vote_location_time_regression_test.dart`** — PUBLIC/PRIVATE ×
LOCATION_TIME, crossed with **inside/outside time window** × **inside/outside
location** (8 flows: `OUTSIDE_TIME_WINDOW` tested both past and future),
plus a `LOCATION_UNAVAILABLE` flow (device can't determine its position at
all, distinct from being simply out of the radius). Time windows are driven
through the real create-event date/time pickers, computed relative to
`DateTime.now()`. Device *location* can't be scripted portably across real
devices/emulators/CI, so this suite uses a small test-only seam instead:
`LocationTestOverride` (a static, nullable field in
`app/lib/views/track_vote.dart`, checked first inside
`requestCurrentLocation()`). It always defaults to `null`, so production
behavior and every other test are unaffected unless a test explicitly sets
it (via `integration_test/helpers/location_override.dart`) — real device
GPS/permission prompts are never exercised by this app code path outside of
this override. The event's own stored coordinates are still resolved via
the real Nominatim geocoding API server-side using a fixed, real landmark
(`"Eiffel Tower, Paris"`), consistent with this suite's "no mocks" policy
everywhere else.

**`track_vote_member_removal_regression_test.dart`** — invites a stranger to
a private INVITED event, has them vote, then has the owner remove them from
members: the vote is cleared immediately and the stranger loses view access
to the event again (`NOT_VIEWABLE`).

`WINDOW_NOT_CONFIGURED` / `LOCATION_NOT_CONFIGURED` are intentionally not
covered by UI-driven tests: the create-event form currently requires all 4
LOCATION_TIME fields together, so those two server-side guard reasons aren't
reachable through normal UI flow without weakening client-side validation.

`track_vote_visibility_policy_regression_test.dart` and
`track_vote_member_removal_regression_test.dart` need the second-mailbox
credentials (see below), like `track_vote_lifecycle_test.dart`;
`track_vote_location_time_regression_test.dart` only needs the primary
mailbox.


1. A running backend + database:
   ```sh
   make project-up
   ```
   `server/.env` must have a working `EMAILPASS` for `no-reply@vanderlynden.eu`
   (`MailService` uses it to actually send the confirmation email — this is
   the same credential used in normal operation, nothing test-specific).
2. A test mailbox to sign up with and to poll for the confirmation email
   (e.g. `music-room@vanderlynden.eu`, reachable over IMAP at
   `ssl0.ovh.net:993`).
3. A connected device/emulator/simulator (`flutter devices`), or `flutter test
   -d chrome` / a desktop target.

## Required configuration

None of the following are hardcoded or committed. Export them in your shell
before running the suite, or pass them inline:

| Variable             | Required | Notes                                              |
|-----------------------|----------|-----------------------------------------------------|
| `E2E_TEST_EMAIL`      | yes      | Signup + IMAP mailbox address                       |
| `E2E_IMAP_PASSWORD`   | yes      | IMAP password for that mailbox                      |
| `E2E_IMAP_HOST`       | no       | Defaults to `ssl0.ovh.net`                          |
| `E2E_IMAP_PORT`       | no       | Defaults to `993`                                   |
| `E2E_TEST_PASSWORD`   | no       | Defaults to a value satisfying the signup rules     |
| `E2E_SECOND_TEST_EMAIL`     | only for `track_vote_lifecycle_test.dart`, `track_vote_visibility_policy_regression_test.dart`, `track_vote_member_removal_regression_test.dart` | Defaults to the dedicated project test mailbox |
| `E2E_SECOND_TEST_PASSWORD`  | only for `track_vote_lifecycle_test.dart`, `track_vote_visibility_policy_regression_test.dart`, `track_vote_member_removal_regression_test.dart` | Signup/signin password for the second mailbox  |
| `E2E_SECOND_IMAP_PASSWORD`  | only for `track_vote_lifecycle_test.dart`, `track_vote_visibility_policy_regression_test.dart`, `track_vote_member_removal_regression_test.dart` | IMAP password for the second mailbox (same server as `E2E_IMAP_HOST`/`E2E_IMAP_PORT`) |

## Running

```sh
cd app
flutter test integration_test/account_lifecycle_test.dart \
  -d <device-id> \
  --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
  --dart-define=E2E_TEST_EMAIL="$E2E_TEST_EMAIL" \
  --dart-define=E2E_IMAP_PASSWORD="$E2E_IMAP_PASSWORD"
```

Or to run every suite in this directory (all six files):

```sh
cd app
flutter test integration_test/ \
  -d <device-id> \
  --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080 \
  --dart-define=E2E_TEST_EMAIL="$E2E_TEST_EMAIL" \
  --dart-define=E2E_IMAP_PASSWORD="$E2E_IMAP_PASSWORD"
```

Or simply:

```sh
make test-e2e DEVICE=<device-id>
```

(see the Makefile target — it wires the env vars above through automatically
and defaults `MUSIC_ROOM_SERVER` the same way `run-app` does for Android
emulators, and now runs every suite under `integration_test/`).

## Notes

- All suites reuse the **same shared inbox** across runs. Each run generates
  a unique display-name/playlist-name/event-name marker (based on the
  current timestamp) to avoid colliding with a previous run, and each
  **deletes the account(s) it created** as its final step, so no manual
  cleanup is needed. Every suite also purges any stale "Confirm your Music
  Room account" emails left in the inbox by a previous failed run before
  triggering a new signup, so it never consumes a stale link.
- `track_vote_lifecycle_test.dart` additionally requires a **second, dedicated
  real mailbox** (`E2E_SECOND_TEST_EMAIL`/`E2E_SECOND_TEST_PASSWORD`/
  `E2E_SECOND_IMAP_PASSWORD`) to create a second account for testing
  cross-user visibility/voting — it defaults to a project-only test address
  but always requires its own signup and IMAP passwords via `--dart-define`.
- None of the suites are wired into CI yet — they require real outbound SMTP
  (`EMAILPASS`) and IMAP credentials that aren't currently provisioned as CI
  secrets. Run them locally/on-demand (e.g. before releases) until that's set
  up.


# Ramp-up measurement

Measured again on 2026-08-03 with `server/test/load/ramp-up.js` against the Docker
Compose backend and MariaDB. Host: Intel Core Ultra 7 255H, 16 logical CPUs,
14 GiB RAM (5.9 GiB available at test time), Linux/Zorin. Containers had no
explicit CPU or memory limit.

Scenario: each simulated user starts concurrently and makes one request; half
download the OpenAPI contract and half execute the public GraphQL catalog query.
Stages increase without restarting the server. Pass thresholds are under 1%
HTTP errors and p95 below 1,000 ms.

| Concurrent users | Requests | Throughput | p50 | p95 | p99 | Errors |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 10 | 67.8 req/s | 78 ms | 98 ms | 98 ms | 0 |
| 25 | 25 | 296.2 req/s | 43 ms | 78 ms | 79 ms | 0 |
| 50 | 50 | 306.8 req/s | 81 ms | 150 ms | 154 ms | 0 |
| 100 | 100 | 393.6 req/s | 145 ms | 229 ms | 232 ms | 0 |

Conclusion: the demonstrated capacity is **at least 100 simultaneous users**
for this read mix on the stated machine, with 0% errors and 229 ms p95. This is
not a claim about internet latency, audio-stream bandwidth, or sustained write
traffic. The default per-IP limiter is 300 requests/minute; distributed clients
have independent buckets. Reproduce with:

```sh
docker compose up -d --build --wait
docker run --rm --network music-room_default \
  -v "$PWD/server:/app" -w /app \
  -e LOAD_BASE_URL=http://backend:8080 \
  -e LOAD_REQUESTS_PER_USER=1 node:22-bookworm-slim \
  node test/load/ramp-up.js
```

## Feature-specific ramp-up: the 3 graded services

The scenario above only exercises read traffic (static docs + a public GraphQL
query). To answer "how many users can simultaneously use your services" for
this project's actual write-heavy features, `server/test/load/feature-ramp-up.js`
(orchestrated by `server/test/load/run-feature-ramp-up.sh`, `make
test-load-features`) drives the real GraphQL mutations behind:

1. **Track voting** — `voteForTrack`: one public vote event/track is set up,
   then N distinct users concurrently vote for it.
2. **Playlist editing** — `addTrackToPlaylist`: N distinct users each get
   their own public playlist, then all concurrently add a track to it.
3. **Host change / remote-control delegation** — `transferHost`: N
   independent rooms are set up (host + a joined friend each), then every
   host concurrently hands control to their friend.

Fixture users/sessions are seeded directly in MariaDB (bypassing the
signup rate limit and email confirmation) so each stage can spin up up to 100
real, independently-authenticated accounts. Each `(scenario, concurrent-user
count)` combination is measured in its own throwaway container pinned to its
own static IP on the Compose network — the server's global rate limiter
buckets by client IP (300 requests/minute), and a single test-runner IP would
otherwise throttle itself where hundreds of real, distributed devices would
each have their own independent budget.

Measured on 2026-08-09 against the same Docker Compose backend + MariaDB, on
an Apple M3 Max, 16 logical CPUs, 64 GiB RAM (Docker Desktop VM allocated 16
CPUs / ~7.7 GiB), macOS, containers with no explicit CPU/memory limit. Pass
thresholds: under 1% HTTP/GraphQL errors and p95 below 1,000 ms.

**Track voting** (`voteForTrack`, all users voting for the same track in the
same public vote event):

| Concurrent users | Requests | Throughput | p50 | p95 | p99 | Errors |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 10 | 289.9 req/s | 24 ms | 34 ms | 34 ms | 0 |
| 25 | 25 | 817.2 req/s | 24 ms | 30 ms | 31 ms | 0 |
| 50 | 50 | 626.6 req/s | 63 ms | 79 ms | 80 ms | 0 |
| 100 | 100 | 660.8 req/s | 118 ms | 150 ms | 151 ms | 0 |

**Playlist editing** (`addTrackToPlaylist`, each user adding a track to their
own playlist):

| Concurrent users | Requests | Throughput | p50 | p95 | p99 | Errors |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 10 | 1,097.6 req/s | 8 ms | 9 ms | 9 ms | 0 |
| 25 | 25 | 1,287.7 req/s | 16 ms | 19 ms | 19 ms | 0 |
| 50 | 50 | 1,272.4 req/s | 33 ms | 39 ms | 39 ms | 0 |
| 100 | 100 | 1,651.7 req/s | 44 ms | 60 ms | 60 ms | 0 |

**Host change / remote-control delegation** (`transferHost`, each of N hosts
handing control to their own joined friend in their own room):

| Concurrent users (room pairs) | Requests | Throughput | p50 | p95 | p99 | Errors |
|---:|---:|---:|---:|---:|---:|---:|
| 10 | 10 | 1,400.1 req/s | 6 ms | 7 ms | 7 ms | 0 |
| 25 | 25 | 2,175.0 req/s | 10 ms | 11 ms | 11 ms | 0 |
| 50 | 50 | 1,757.4 req/s | 21 ms | 28 ms | 28 ms | 0 |
| 100 | 100 | 2,471.4 req/s | 30 ms | 40 ms | 40 ms | 0 |

Conclusion: all 3 features sustain **at least 100 simultaneous users** on the
stated hardware with 0% errors and p95 well under the 1,000 ms threshold (150
ms for track voting, the heaviest of the three since it triggers a DB write
plus a `voteEventUpdated` subscription fan-out on every vote). This load test
uncovered and fixed a real concurrency bug in `PlaylistDb.addTrack` (the
`INSERT ... SELECT` pattern for computing the next track position could throw
MariaDB error 1467, `ER_AUTOINC_READ_FAILED`, under concurrent writes to
different playlists); it now does the `SELECT` and `INSERT` as two statements
inside the same per-playlist transaction, which is race-free and no longer
hits that InnoDB limitation.

Reproduce with:

```sh
docker compose up -d --build --wait
make test-load-features
# or directly:
server/test/load/run-feature-ramp-up.sh 10,25,50,100
```


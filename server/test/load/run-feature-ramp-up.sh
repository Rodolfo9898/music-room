#!/usr/bin/env bash
# Ramp-up load test orchestrator for server/test/load/feature-ramp-up.js.
#
# Runs each (scenario, users) combination in its own throwaway Docker
# container attached to the Compose network, pinned to its own static IP
# (docker reuses the same free IP for back-to-back short-lived containers
# otherwise). A distinct IP per measurement gives each one its own bucket in
# the server's per-IP rate limiter (300 req/min, see
# middleware/rate-limit.middleware.ts) instead of every "virtual user"
# appearing to come from one test-runner IP — closer to how real distributed
# clients behave, and it means the measured numbers reflect the server's own
# capacity rather than an artifact of this test harness sharing one IP.
#
# Usage: server/test/load/run-feature-ramp-up.sh [stages] [backend-host:port]
#   stages          comma-separated concurrent-user counts (default: 10,25,50,100)
#   backend-host    Docker network hostname:port of the backend (default: backend:8080)
#
# Requires: docker compose stack up (mariadb + backend reachable on the
# "music-room_default" network), and server/.env populated (JWT_SECRET, DB_*).
set -euo pipefail

STAGES="${1:-10,25,50,100}"
BACKEND="${2:-backend:8080}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$SERVER_DIR/.env"
NETWORK="${LOAD_NETWORK:-music-room_default}"
IP_PREFIX="${LOAD_IP_PREFIX:-172.19.9}" # must be free within the compose network's subnet

if [ ! -f "$ENV_FILE" ]; then
	echo "Missing $ENV_FILE" >&2
	exit 1
fi

IFS=',' read -ra STAGE_LIST <<< "$STAGES"
RESULTS_FILE="$(mktemp)"
trap 'rm -f "$RESULTS_FILE"' EXIT

ip_octet=10
for scenario in vote playlist host; do
	for users in "${STAGE_LIST[@]}"; do
		echo "== scenario=$scenario users=$users (ip $IP_PREFIX.$ip_octet) ==" >&2
		docker run --rm --network "$NETWORK" --ip "$IP_PREFIX.$ip_octet" \
			-v "$SERVER_DIR:/app" -w /app \
			--env-file "$ENV_FILE" \
			-e LOAD_BASE_URL="http://$BACKEND" \
			-e DB_HOST=mariadb -e DB_PORT=3306 -e DB_USER=music_user -e DB_PASS=music_pass -e DB_NAME=MusicRoom \
			-e LOAD_SCENARIO="$scenario" -e LOAD_USERS="$users" \
			node:22-bookworm-slim node test/load/feature-ramp-up.js \
			| tee -a "$RESULTS_FILE"
		ip_octet=$((ip_octet + 1))
	done
done

echo "[" > "$SCRIPT_DIR/feature-ramp-up-results.json"
python3 - "$RESULTS_FILE" <<'PY' >> "$SCRIPT_DIR/feature-ramp-up-results.json"
import json, sys
text = open(sys.argv[1]).read()
decoder = json.JSONDecoder()
objects = []
idx = 0
text = text.strip()
while idx < len(text):
    while idx < len(text) and text[idx].isspace():
        idx += 1
    if idx >= len(text):
        break
    obj, end = decoder.raw_decode(text, idx)
    objects.append(obj)
    idx = end
print(",\n".join(json.dumps(o) for o in objects))
PY
echo "]" >> "$SCRIPT_DIR/feature-ramp-up-results.json"

echo "Combined results written to $SCRIPT_DIR/feature-ramp-up-results.json" >&2

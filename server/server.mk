.PHONY: install-server run-server backend-up db-up db-down db-reset db-migrate \
	musics test-server test-server-docker test-integration test-load test-load-features

REMOTE_DB ?= 0

install-server:
	cd server && npm install

run-server:
    ifeq ($(REMOTE_DB),1)
        docker compose run --rm --no-deps --service-ports backend npm run dev
    else
        docker compose up --build backend
    endif

backend-up: musics
	docker compose up -d --build --wait backend

db-up:
	docker compose up -d --wait mariadb

db-down:
	docker compose down

db-reset:
	docker compose down -v
	$(MAKE) db-up db-migrate

db-migrate:
	docker compose run --rm backend npm run db:migrate

# Extracts the MP3s, NFC-normalizing filenames so they match the seeded file_path values.
musics:
	@python3 -c "import os,unicodedata,zipfile; \
	z=zipfile.ZipFile('server/musics.zip'); os.makedirs('server/musics',exist_ok=True); \
	names=[i for i in z.infolist() if i.filename.lower().endswith('.mp3') and not i.filename.startswith('__MACOSX/')]; \
	[open(os.path.join('server/musics',unicodedata.normalize('NFC',os.path.basename(i.filename if i.flag_bits & 0x800 else i.filename.encode('cp437').decode('utf-8','replace')))),'wb').write(z.read(i)) for i in names]; \
	print('Extracted %d file(s) to server/musics/' % len(names))"

test-server:
	docker compose run --rm backend npm test

# Runs the unit tests in a disposable, plain `docker run` container instead of the
# docker-compose `backend` service — no image build, DB, or other services needed.
# node_modules are installed into a named volume (not the bind-mounted source tree)
# so native deps (e.g. bcrypt) are built for Linux and reused across runs.
test-server-docker:
	docker run --rm \
		-v "$(CURDIR)/server:/app" \
		-v music-room_server_node_modules:/app/node_modules \
		-w /app \
		node:22-bookworm-slim \
		sh -c "npm ci && npm test"

test-integration: project-up
	docker compose run --rm backend npm run test:integration

test-load: project-up
	docker run --rm --network music-room_default -v "$(CURDIR)/server:/app" -w /app \
		-e LOAD_BASE_URL=http://backend:8080 -e LOAD_REQUESTS_PER_USER=1 \
		node:22-bookworm-slim node test/load/ramp-up.js

# Measures the 3 graded features (track voting, playlist editing, host/remote-control
# delegation) instead of generic read traffic: see test/load/feature-ramp-up.js and
# test/load/run-feature-ramp-up.sh for details on why each (scenario, stage) runs in
# its own container with its own static IP.
test-load-features: project-up
	server/test/load/run-feature-ramp-up.sh

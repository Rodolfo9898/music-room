ANDROID_AVD ?= MusicRoom_API_36
ANDROID_DEVICE ?= emulator-5554
APP_BACKEND ?= 10.0.2.2:8080

include server/server.mk
include app/app.mk

.PHONY: help setup run-project project-up project-down install verify

help:
	@printf "Available targets:\n"
	@printf "  make setup            Full local setup: install, .env, local DB, migrations, musics\n"
	@printf "  make run-project      Start Docker backend/DB, Android emulator, and Flutter app\n"
	@printf "  make project-up       Build and start the Docker backend and database\n"
	@printf "  make project-down     Stop the Docker backend and database\n"
	@printf "  make backend-up       Build and start the Docker backend (and its database)\n"
	@printf "  make run-server       Run the Node/Express server\n"
	@printf "  make run-app          Choose a Flutter device/backend and run the app\n"
	@printf "  make install          Install server and Flutter dependencies\n"
	@printf "  make install-server   Install server dependencies\n"
	@printf "  make install-app      Install Flutter dependencies\n"
	@printf "  make check-devices    Show devices detected by Flutter and ADB\n"
	@printf "  make db-up            Start the local MariaDB container (docker compose)\n"
	@printf "  make db-down          Stop the local MariaDB container\n"
	@printf "  make db-reset         Wipe the local DB and re-apply migrations + seed\n"
	@printf "  make db-migrate       Apply pending migrations (incl. default seed)\n"
	@printf "  make musics           Extract server/musics.zip into server/musics/\n"
	@printf "  make test-server      Run server unit tests (no DB needed)\n"
	@printf "  make test-server-docker  Run server unit tests in a disposable Docker container (no compose/DB/build needed)\n"
	@printf "  make test-integration Start DB, migrate, and run integration tests\n"
	@printf "  make test-app         Analyze/test Flutter and build Android + web\n"
	@printf "  make test-app-docker   Run Flutter unit tests in a disposable Docker container (no local Flutter SDK needed)\n"
	@printf "  make test-e2e         Run the E2E suites (account lifecycle + playlist lifecycle + track vote lifecycle); requires DEVICE=<id> and E2E_TEST_EMAIL/E2E_IMAP_PASSWORD env vars, see app/integration_test/README.md\n"
	@printf "  make test-load        Run the reproducible Docker ramp-up test\n"
	@printf "  make test-load-features  Run the feature-specific ramp-up test (track vote, playlist, host delegation)\n"
	@printf "  make verify           Run server, integration, app, audit, and load gates\n"

setup: install
	@sh server/scripts/create-local-env.sh server/.env
	@test -f app/.env || (cp app/.env.example app/.env && printf "Created app/.env from app/.env.example\n")
	$(MAKE) db-up db-migrate musics

run-project: project-up
	@if ! adb devices | rg -q '^$(ANDROID_DEVICE)[[:space:]]'; then \
		printf "Launching Android emulator $(ANDROID_AVD)...\n"; \
		setsid -f emulator @"$(ANDROID_AVD)" -no-snapshot-load \
			>/tmp/music-room-emulator.log 2>&1; \
	fi
	@printf "Waiting for $(ANDROID_DEVICE) to finish booting...\n"
	@for attempt in $$(seq 1 60); do \
		if [ "$$(adb -s "$(ANDROID_DEVICE)" shell getprop sys.boot_completed 2>/dev/null)" = "1" ]; then \
			break; \
		fi; \
		if [ "$$attempt" = "60" ]; then \
			printf "Emulator did not boot within 120 seconds.\n"; \
			exit 1; \
		fi; \
		sleep 2; \
	done
	cd app && flutter run -d "$(ANDROID_DEVICE)" --dart-define-from-file=.env --dart-define=MUSIC_ROOM_SERVER="$(APP_BACKEND)"

project-up: musics
	docker compose up -d --build --wait

project-down:
	docker compose down

install: install-server install-app

verify: test-server test-integration test-app test-load test-load-features
	docker run --rm -v "$(CURDIR)/server:/app" -w /app node:22-bookworm-slim npm audit --audit-level=moderate

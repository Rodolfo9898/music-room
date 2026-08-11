FLUTTER_DOCKER_IMAGE ?= ghcr.io/cirruslabs/flutter:stable

.PHONY: install-app run-app check-devices test-app test-app-docker test-e2e

install-app:
	cd app && flutter pub get

run-app:
	@cd app && \
	flutter devices && \
	printf "\nEnter the Flutter device id to use: " && \
	read device && \
	printf "Enter backend host:port [192.168.68.54:8080]: " && \
	read backend && \
	backend=$${backend:-192.168.68.54:8080} && \
	flutter run -d "$$device" --dart-define=MUSIC_ROOM_SERVER="$$backend"

build:
	cd app && flutter build apk --debug --dart-define-from-file=.env --dart-define=MUSIC_ROOM_SERVER="$(APP_BACKEND)"
	cd app && flutter build web --release --dart-define-from-file=.env --dart-define=MUSIC_ROOM_SERVER=localhost:8080

check-devices:
	@printf "\nFlutter devices:\n"
	cd app && flutter devices
	@printf "\nADB devices:\n"
	adb devices -l

test-app:
	cd app && flutter analyze
	cd app && flutter test

# Runs the Flutter unit tests in a disposable Docker container instead of a
# locally installed Flutter SDK. The pub cache is kept in a named volume (not
# the bind-mounted source tree) so dependencies are reused across runs.
test-app-docker:
	docker run --rm \
		-v "$(CURDIR)/app:/app" \
		-v music-room_flutter_pub_cache:/root/.pub-cache \
		-w /app \
		$(FLUTTER_DOCKER_IMAGE) \
		sh -c "flutter pub get && flutter test"

# Exported (rather than textually substituted with $(...)) so recipe shells
# receive these via the environment (execve), not by having make splice their
# literal value into a double-quoted shell string. The latter would make the
# shell re-interpret any $, `, \, etc. *inside* the secret itself (e.g. an
# IMAP password containing "$something" would have "$something" expanded as
# an unset shell variable and silently vanish) before it ever reaches Flutter.
export E2E_TEST_EMAIL E2E_IMAP_PASSWORD E2E_IMAP_HOST E2E_TEST_PASSWORD
export E2E_SECOND_TEST_EMAIL E2E_SECOND_IMAP_PASSWORD

test-e2e: project-up
	@if [ -z "$(DEVICE)" ]; then \
		printf "DEVICE is required, e.g. make test-e2e DEVICE=<id>. Run 'make check-devices' to list options.\n"; \
		exit 1; \
	fi
	@cd app && \
		. ./scripts/export-env.sh .env && \
		if [ -z "$$E2E_TEST_EMAIL" ] || [ -z "$$E2E_IMAP_PASSWORD" ] || [ -z "$$E2E_SECOND_TEST_EMAIL" ] || [ -z "$$E2E_SECOND_IMAP_PASSWORD" ]; then \
			printf "E2E_TEST_EMAIL, E2E_IMAP_PASSWORD, E2E_SECOND_TEST_EMAIL, and E2E_SECOND_IMAP_PASSWORD must be set.\n"; \
			printf "Either add them to app/.env, or export them as real shell env vars first (never as 'make test-e2e VAR=value', see app/integration_test/README.md), e.g.:\n"; \
			printf "  export E2E_TEST_EMAIL=... E2E_IMAP_PASSWORD=... E2E_SECOND_TEST_EMAIL=... E2E_SECOND_IMAP_PASSWORD=...\n"; \
			printf "  make test-e2e DEVICE=<id>\n"; \
			printf "See app/integration_test/README.md for details.\n"; \
			exit 1; \
		fi && \
		flutter test integration_test/ \
			-d "$(DEVICE)" \
			--dart-define=MUSIC_ROOM_SERVER="$(APP_BACKEND)" \
			--dart-define-from-file=.env

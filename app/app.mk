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

check-devices:
	@printf "\nFlutter devices:\n"
	cd app && flutter devices
	@printf "\nADB devices:\n"
	adb devices -l

test-app:
	cd app && dart format --output=none --set-exit-if-changed lib test
	cd app && flutter analyze
	cd app && flutter test
	cd app && flutter build apk --debug --dart-define-from-file=.env --dart-define=MUSIC_ROOM_SERVER="$(APP_BACKEND)"
	cd app && flutter build web --release --dart-define-from-file=.env --dart-define=MUSIC_ROOM_SERVER=localhost:8080

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

test-e2e: project-up
	@if [ -z "$(E2E_TEST_EMAIL)" ] || [ -z "$(E2E_IMAP_PASSWORD)" ]; then \
		printf "E2E_TEST_EMAIL and E2E_IMAP_PASSWORD must be set, e.g.:\n"; \
		printf "  make test-e2e DEVICE=<id> E2E_TEST_EMAIL=... E2E_IMAP_PASSWORD=...\n"; \
		printf "See app/integration_test/README.md for details.\n"; \
		exit 1; \
	fi
	@if [ -z "$(DEVICE)" ]; then \
		printf "DEVICE is required, e.g. make test-e2e DEVICE=<id>. Run 'make check-devices' to list options.\n"; \
		exit 1; \
	fi
	cd app && flutter test integration_test/ \
		-d "$(DEVICE)" \
		--dart-define=MUSIC_ROOM_SERVER="$(APP_BACKEND)" \
		--dart-define=E2E_TEST_EMAIL="$(E2E_TEST_EMAIL)" \
		--dart-define=E2E_IMAP_PASSWORD="$(E2E_IMAP_PASSWORD)" \
		$(if $(E2E_IMAP_HOST),--dart-define=E2E_IMAP_HOST="$(E2E_IMAP_HOST)",) \
		$(if $(E2E_TEST_PASSWORD),--dart-define=E2E_TEST_PASSWORD="$(E2E_TEST_PASSWORD)",) \
		$(if $(E2E_SECOND_TEST_EMAIL),--dart-define=E2E_SECOND_TEST_EMAIL="$(E2E_SECOND_TEST_EMAIL)",) \
		$(if $(E2E_SECOND_IMAP_PASSWORD),--dart-define=E2E_SECOND_IMAP_PASSWORD="$(E2E_SECOND_IMAP_PASSWORD)",)

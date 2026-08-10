# Music Room App

Flutter mobile client for Music Room.

## Backend Configuration

The backend address is configurable at run/build time with `MUSIC_ROOM_SERVER`.
Use `host:port` without a protocol.

```sh
flutter run -d <device-id> --dart-define=MUSIC_ROOM_SERVER=192.168.68.54:8080
```

From the project root, `make run-app` prompts for both the Flutter device and the backend address.

## Docker (Flutter 3.44.7)

The app includes `app/dockerfile` for standalone one-off Docker usage (not wired to `docker-compose`).

### CI target images

Build web assets:

```sh
docker build -f app/dockerfile app --target ci-web \
  --build-arg MUSIC_ROOM_SERVER=localhost:8080
```

Build Android APK:

```sh
docker build -f app/dockerfile app --target ci-android \
  --build-arg MUSIC_ROOM_SERVER=10.0.2.2:8080
```

iOS note:
- `ci-ios` runs Flutter checks (`analyze` + `test`) in Linux.
- Producing iOS app binaries still requires macOS + Xcode.

```sh
docker build -f app/dockerfile app --target ci-ios
```

### Mobile runtime container (one-off)

Build the runtime image:

```sh
docker build -f app/dockerfile app --target mobile-runtime -t music-room-mobile-runtime
```

Run one-off mobile commands:

```sh
docker run --rm -it -v "$(pwd)/app:/workspace/app" music-room-mobile-runtime flutter doctor
docker run --rm -it -v "$(pwd)/app:/workspace/app" music-room-mobile-runtime flutter test
docker run --rm -it -v "$(pwd)/app:/workspace/app" music-room-mobile-runtime \
  flutter build apk --release --dart-define=MUSIC_ROOM_SERVER=10.0.2.2:8080
```

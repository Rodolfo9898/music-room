# App runbook (Flutter mobile + web)

This runbook covers local app setup and runtime for:

- Flutter app dependencies
- Device discovery
- Running on a selected device
- Running on Chrome (web)
- Building app artifacts

## 1) Prerequisites

1. Flutter SDK **3.44.7** (stable channel).
2. Repository checked out locally.
3. A running backend reachable by the app (`host:port`), for example `localhost:8080`.

Install Flutter from official instructions:

- https://docs.flutter.dev/get-started/install

Confirm your version:

```sh
flutter --version
```

The output should report Flutter `3.44.7`.

## 2) Go to app folder

From repository root:

```sh
cd app
```

## 3) Install dependencies

```sh
flutter pub get
```

## 4) List available devices

```sh
flutter devices
```

From repository root, you can also use:

```sh
make check-devices
```

## 5) Run the app

Set backend with `MUSIC_ROOM_SERVER` as `host:port` (no protocol).

### Run on a selected device

```sh
flutter run -d <device-id> --dart-define-from-file=.env
```

### Run on Chrome

```sh
flutter run -d chrome --dart-define-from-file=.env
```

From repository root, interactive device/backend selection is also available via:

```sh
make run-app
```

## 6) Build artifacts

### Build Android APK

```sh
flutter build apk --release --dart-define-from-file=.env
```

### Build web assets

```sh
flutter build web --release --dart-define-from-file=.env
```

## 7) Troubleshooting

- **Flutter version mismatch**
  - run `flutter --version`
  - if needed, switch/update Flutter to `3.44.7`
- **No device shown**
  - re-run `flutter devices`
  - for Android, verify emulator/phone connection with `adb devices -l`
- **Cannot reach backend from emulator/device**
  - verify `MUSIC_ROOM_SERVER` value and backend availability
  - use an address reachable from your selected device/emulator

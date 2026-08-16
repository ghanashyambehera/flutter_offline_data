# Flutter Offline Data Sync

## /Users/ghanashyambehera/fvm/versions/3.44.1

Offline-first Flutter app: create/update users locally with **sqflite**, queue mutations, and **auto-sync** to JSONPlaceholder via **Dio** when connectivity returns.

## Platforms

- Android
- iOS

## Architecture

```
UI → UserRepository → SQLite (users + sync_queue) + SyncEngine → Dio
                      ↑ ConnectivityService + app lifecycle
```

See [`docs/DESIGN.md`](docs/DESIGN.md) and [`docs/REQUIREMENTS_ANALYSIS.md`](docs/REQUIREMENTS_ANALYSIS.md).

## Features

- Offline create/update with immediate local UI
- Durable sync queue (FIFO + coalescing)
- Auto-sync on: reconnect, app start, app resume, save while online
- Sync status chips: Synced / Pending / Failed
- No manual Sync or Retry button

## API

- Base URL: `https://jsonplaceholder.typicode.com`
- `POST /users` — create
- `PUT /users/{id}` — update

## Project structure

```
lib/
  main.dart
  app.dart
  core/database/
  core/network/
  core/connectivity/
  features/users/
    data/
    domain/
    sync/
    presentation/
```

## Run

```bash
flutter pub get
flutter run
```

## Test

```bash
flutter test
flutter analyze
```

## Manual QA

1. Enable airplane mode → create a user → see **Pending**
2. Disable airplane mode → status becomes **Synced** automatically
3. Edit offline → coalesced queue → auto-sync on reconnect

JSONPlaceholder does not persist data; success is defined as HTTP 2xx + stored `server_id`.

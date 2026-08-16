# Prompt 01 — Project setup & dependencies

References: **DESIGN §3, §4** | **REQUIREMENTS §13, §14**

---

## Task

Create a new Flutter project (or scaffold `lib/` if empty) for the offline sync app.

## Read first

- `docs/DESIGN.md` — §3 module layout, §4 technology choices
- `docs/REQUIREMENTS_ANALYSIS.md` — §13 dependencies

## Requirements

1. **Package name:** sensible default (e.g. `flutter_offline_data`)
2. **Platforms:** Android + iOS
3. **Add dependencies** to `pubspec.yaml`:

   | Package | Purpose |
   |---------|---------|
   | `sqflite` | Local SQLite |
   | `path` | DB path helpers |
   | `path_provider` | App documents directory |
   | `dio` | HTTP client |
   | `connectivity_plus` | Connectivity stream |
   | `uuid` | `local_id` generation |

4. **Dev dependencies:** `flutter_test`, `sqflite_common_ffi` (for VM tests later)

5. **Create folder skeleton** per DESIGN §3:

   ```
   lib/
     main.dart
     app.dart
     core/database/
     core/network/
     core/connectivity/
     features/users/data/models/
     features/users/data/datasources/
     features/users/data/repositories/
     features/users/domain/entities/
     features/users/domain/repositories/
     features/users/sync/
     features/users/presentation/
   ```

6. **`main.dart`:** minimal `runApp` placeholder only — no business logic yet

7. **Constants file** (e.g. `core/network/api_config.dart`):
   - `baseUrl = 'https://jsonplaceholder.typicode.com'`
   - connect/receive timeout 15s

## Constraints

- Do **not** implement sync, DB, or UI beyond placeholder
- Do **not** add ReqRes or other API hosts
- Do **not** add manual sync packages (Workmanager, etc.) in v1

## Deliverables

- `pubspec.yaml` with dependencies resolved (`flutter pub get` succeeds)
- Empty/stub files matching folder layout
- `ApiConfig` with JSONPlaceholder base URL

## Done when

Project analyzes without errors and runs a blank MaterialApp home screen.

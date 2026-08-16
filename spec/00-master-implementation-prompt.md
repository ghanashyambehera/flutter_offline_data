# Master prompt — full offline sync app

Copy everything below the line into your AI coding agent. Attach `docs/REQUIREMENTS_ANALYSIS.md` and `docs/DESIGN.md`.

---

## Task

Implement a **Flutter** app for **offline-first User create/update** with **automatic sync**, following exactly:

- `docs/REQUIREMENTS_ANALYSIS.md` (requirements)
- `docs/DESIGN.md` (architecture, schema, algorithms)

Do **not** invent features outside those documents.

## Locked constraints

| Area | Rule |
|------|------|
| Local storage | **sqflite** only (`users` + `sync_queue` tables per DESIGN §6) |
| HTTP | **Dio** only |
| Remote | **JSONPlaceholder** `https://jsonplaceholder.typicode.com` — `POST /users`, `PUT /users/{id}` |
| Sync UX | **Auto-sync only** — triggers: connectivity restored, app start/resume, after local save while online. **No** Sync now button, **no** Retry button |
| Scope | User entity; create + update only. No delete, no GET list from server, no auth |

## Architecture (from DESIGN §2–3)

Implement layered structure:

```
UI → UserRepository → LocalDataSource (sqflite) + SyncEngine → Dio UserApi
                      ↑ ConnectivityService triggers SyncEngine.trySync()
```

- All create/update: validate → SQLite transaction (user row + queue row) → commit → optional `trySync()` if online
- UI reads **only** from local SQLite (never Dio directly)
- Single sync worker with mutex; reset `in_progress` → `pending` on startup (DESIGN §6.3)

## SQLite schema

Implement DESIGN §6.1–6.2:

- **`users`:** `local_id` (UUID PK), `server_id`, `name`, `email`, `job`, `sync_status`, timestamps, `last_error`
- **`sync_queue`:** FIFO queue with `operation` (`CREATE`/`UPDATE`), `payload_json`, `status`, `attempt_count`, `next_attempt_at`, etc.

Enable foreign keys; coalesce CREATE+UPDATE per DESIGN §7.2.

## Sync engine

Implement DESIGN §7.3–7.4:

- Process queue in `id` order; one item at a time
- CREATE → Dio POST; on 2xx store `server_id`, mark user `synced`, queue `done`
- UPDATE → Dio PUT with `server_id`
- Retryable errors: exponential backoff (2s, 4s, 8s, 16s, 32s), max 5 attempts
- Non-retryable 4xx → `failed` (terminal in v1)

## Connectivity

Implement DESIGN §8:

- `connectivity_plus` stream
- Offline → online triggers `trySync()`
- `AppLifecycleState.resumed` triggers `trySync()`
- Optional reachability ping via Dio

## UI (DESIGN §10)

- User list from local DB with sync chips: Synced / Pending / Failed
- Create/edit form works offline
- Offline banner when disconnected
- Show `last_error` on failed rows — **read-only**, no retry action

## Dependencies

`sqflite`, `path`, `path_provider`, `dio`, `connectivity_plus`, `uuid`

## Deliverables

1. Complete Flutter project under `lib/` matching DESIGN §3 folder layout
2. Runnable on iOS/Android simulator
3. Basic tests per DESIGN §14 (coalescing, offline, sync order) using `sqflite_common_ffi` where applicable

## Acceptance (REQUIREMENTS_ANALYSIS §15)

Verify:

1. Offline create → local row + pending status
2. Offline update → local fields + coalesced queue
3. Network restore → auto-sync without manual button
4. POST success → `server_id` + synced
5. PUT success → synced
6. Pending queue survives app kill and syncs after relaunch + online
7. Validation blocks invalid enqueue
8. Dio + sqflite only for persistence/API

## Out of scope

Delete user, server GET list, auth, Workmanager/background sync, manual Sync/Retry UI.

Implement now. Prefer clean, minimal code; match existing Flutter conventions if any.

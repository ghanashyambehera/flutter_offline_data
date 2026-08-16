# Detailed Design: Flutter Offline Data Sync

**Document type:** Technical design (no implementation)  
**Based on:** [REQUIREMENTS_ANALYSIS.md](./REQUIREMENTS_ANALYSIS.md)  
**Status:** Draft for review  
**Date:** 15 August 2026

This document specifies **how** a future Flutter implementation should be structured. It does **not** include application source code.

---

## 1. Design goals

1. **Offline-first writes:** UI always reads/writes SQLite; network is a side effect.
2. **Durable queue:** Mutations survive process death (`sqflite`).
3. **Auto-sync only:** Connectivity restore, app start/resume, and post-save-while-online drain the queue via **Dio**. No manual Sync control.
4. **Single pipeline:** Online and offline use the same create/update path (local commit → enqueue → processor).
5. **Clear layers:** UI, domain, local DB, queue, connectivity, remote API.

---

## 2. High-level architecture

```
┌─────────────────────────────────────────────────────────┐
│  UI (Forms, User list, offline banner, sync badges)     │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  UserRepository (domain façade)                         │
│  - createUser / updateUser / watchUsers                 │
│  - always writes SQLite + queue in one transaction      │
└─────────────┬───────────────────────────┬───────────────┘
              │                           │
              ▼                           ▼
┌─────────────────────┐     ┌─────────────────────────────┐
│  LocalDataSource    │     │  SyncEngine                 │
│  sqflite            │     │  - drain queue              │
│  users + sync_queue │     │  - coalesce                 │
└─────────────────────┘     │  - call UserApi (Dio)       │
                            │  - update local + queue     │
                            └──────────────┬──────────────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    ▼                      ▼                      ▼
         ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
         │ Connectivity     │   │ Dio UserApi      │   │ Retry / backoff  │
         │ Monitor          │   │ POST/PUT sample  │   │ mutex            │
         └──────────────────┘   └──────────────────┘   └──────────────────┘
```

**Data flow (create or update):**

1. Validate input (domain rules).
2. Open SQLite transaction.
3. Upsert `users` row (`pending_create` / `pending_update`).
4. Insert or coalesce `sync_queue` row (`pending`).
5. Commit; UI observes table/stream and refreshes.
6. If connectivity says online, `SyncEngine.trySync()` (non-blocking).
7. Processor sends Dio request; on 2xx updates `users` (`synced`, `server_id`) and marks queue `done`.

---

## 3. Recommended Flutter module layout (future code)

```
lib/
  main.dart
  app.dart
  core/
    database/
      app_database.dart          # openDatabase, version, migrations
      tables.dart                # SQL CREATE statements
    network/
      dio_client.dart            # base URL, timeouts, interceptors
      api_exception.dart
    connectivity/
      connectivity_service.dart  # stream + isOnline
  features/
    users/
      data/
        models/
          user_local.dart
          user_dto.dart
          sync_queue_item.dart
        datasources/
          user_local_datasource.dart
          user_remote_datasource.dart
        repositories/
          user_repository_impl.dart
      domain/
        entities/user.dart
        repositories/user_repository.dart
      sync/
        sync_engine.dart
        sync_policy.dart         # coalesce, retry classification
      presentation/
        user_list_page.dart
        user_form_page.dart
```

State management is not mandated; **Provider, Riverpod, or Bloc** can sit on `UserRepository` + `ConnectivityService`. Design constraint: UI must not call Dio or sqflite directly.

---

## 4. Technology choices

| Concern | Choice | Rationale |
|---------|--------|-----------|
| Local DB | `sqflite` | Requirement; relational, transactional, durable. |
| HTTP | `dio` | Interceptors, timeouts, typed errors. |
| Connectivity | `connectivity_plus` | OS-level interface changes. |
| Reachability (optional) | HEAD/GET via Dio or `internet_connection_checker_plus` | Reduces captive-portal false “online”. |
| IDs | UUID v4 string for `local_id` | Stable before server id exists. |
| JSON | `dart:convert` in datasources | Keep Dio `Map<String, dynamic>`. |

**Suggested pubspec (future):**

- `sqflite`
- `path` / `path_provider`
- `dio`
- `connectivity_plus`
- `uuid`

---

## 5. Sample API design

### 5.1 Client configuration

JSONPlaceholder is the **locked** v1 remote. Do not use ReqRes or another sample host.

| Setting | Value |
|---------|--------|
| Base URL | `https://jsonplaceholder.typicode.com` |
| Connect timeout | 15s |
| Receive timeout | 15s |
| Headers | `Content-Type: application/json`, `Accept: application/json` |
| Extra header | `X-Client-Request-Id: {local_id}` (idempotency hint) |

**Environment:** `ApiConfig.baseUrl` injectable so production can replace the host without changing the sync engine.

### 5.2 Endpoints

#### Create user

- **Method / path:** `POST /users`
- **Request body:**

```json
{
  "name": "Jane Doe",
  "email": "jane@example.com",
  "job": "Engineer",
  "clientRequestId": "550e8400-e29b-41d4-a716-446655440000"
}
```

- **Success:** HTTP 200/201. Body MUST include `id` (number or string). Other fields echoed if present.
- **Mapping:** `id` → `users.server_id` (store as TEXT to support both numeric and string APIs).

#### Update user

- **Method / path:** `PUT /users/{serverId}`
- **Request body:** same fields as create (full resource). `clientRequestId` optional.
- **Success:** HTTP 200. Merge response into local row.

#### Out of scope

- `GET /users`, `DELETE /users/{id}` — not required for v1 sync (local list is source of UI).

### 5.3 DTO mapping

| Local column | JSON key |
|--------------|----------|
| `name` | `name` |
| `email` | `email` |
| `job` | `job` |
| `local_id` | `clientRequestId` (request only) |
| `server_id` | `id` (response / path) |

JSONPlaceholder may ignore extra fields and may not persist. **Sync success is defined as 2xx + parseable `id` on create.** Document this in QA notes.

### 5.4 HTTP error classification (`sync_policy`)

| Condition | Class | Action |
|-----------|-------|--------|
| Socket / Dio connection timeout / `DioExceptionType.connectionError` | Retryable | Backoff; keep `pending` |
| HTTP 408, 429, 5xx | Retryable | Honour `Retry-After` if present; else backoff |
| HTTP 400, 401, 403, 404, 422 | Non-retryable | `failed`; store `last_error` |
| HTTP 409 | Non-retryable in v1 | `failed` (no merge UI) |
| Parse error on 2xx (missing `id` on create) | Non-retryable | `failed` |

---

## 6. SQLite schema (sqflite)

**Database name:** `offline_sync.db`  
**Version:** `1`

### 6.1 Table `users`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `local_id` | TEXT | PK | UUID generated on device |
| `server_id` | TEXT | NULL, UNIQUE | Set after successful POST |
| `name` | TEXT | NOT NULL | |
| `email` | TEXT | NOT NULL | |
| `job` | TEXT | NULL | |
| `sync_status` | TEXT | NOT NULL | `pending_create` / `pending_update` / `synced` / `failed` |
| `created_at` | INTEGER | NOT NULL | epoch ms |
| `updated_at` | INTEGER | NOT NULL | epoch ms |
| `last_error` | TEXT | NULL | Last sync error message |

Indexes: `idx_users_sync_status` on `sync_status`; `idx_users_server_id` on `server_id`.

### 6.2 Table `sync_queue`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK AUTOINCREMENT | FIFO order |
| `entity_type` | TEXT | NOT NULL | `user` |
| `operation` | TEXT | NOT NULL | `CREATE` / `UPDATE` |
| `local_id` | TEXT | NOT NULL | FK logical to `users.local_id` |
| `server_id` | TEXT | NULL | Copied when known |
| `payload_json` | TEXT | NOT NULL | Latest field snapshot |
| `status` | TEXT | NOT NULL | `pending` / `in_progress` / `done` / `failed` |
| `attempt_count` | INTEGER | NOT NULL DEFAULT 0 | |
| `next_attempt_at` | INTEGER | NULL | epoch ms; backoff gate |
| `last_error` | TEXT | NULL | |
| `created_at` | INTEGER | NOT NULL | |
| `updated_at` | INTEGER | NOT NULL | |

Indexes: `idx_queue_status` on `status`; `idx_queue_local_id` on `local_id`.

Foreign key: `local_id` REFERENCES `users(local_id)` ON DELETE CASCADE (enable `PRAGMA foreign_keys = ON`).

### 6.3 Crash recovery

On database open / SyncEngine start:

```
UPDATE sync_queue SET status = 'pending', updated_at = ? WHERE status = 'in_progress';
```

Prevents a killed process from leaving items stuck.

### 6.4 Migrations

v1: create both tables. Future versions increment `version` and run `ALTER TABLE` in `onUpgrade`.

---

## 7. Sync queue operations

### 7.1 Enqueue — Create

**Transaction:**

1. `INSERT` user: `sync_status = pending_create`, `server_id = NULL`.
2. `INSERT` queue: `operation = CREATE`, `payload_json` = current fields, `status = pending`.

### 7.2 Enqueue — Update

**Transaction, coalescing policy (FR-Q5, FR-Q6):**

1. Load user by `local_id`; apply new fields; set `updated_at`.
2. If `server_id IS NULL` (never created remotely):
   - Find existing `pending`/`in_progress` CREATE for `local_id`.
   - **Update that row’s `payload_json`** to the latest fields.
   - Do **not** insert UPDATE.
   - User status stays `pending_create`.
3. If `server_id` is set:
   - Set user `sync_status = pending_update`.
   - If a `pending` UPDATE exists for this `local_id`, **replace `payload_json`**.
   - Else `INSERT` UPDATE with `server_id`.

Do not enqueue if validation fails (BR-4).

### 7.3 Processor algorithm (`SyncEngine.trySync`)

**Mutex:** boolean `_running`; if true, return. Re-check queue when finished (writes during drain).

```
if !connectivity.isOnline: return
acquire mutex
reset in_progress → pending
loop:
  item = SELECT * FROM sync_queue
         WHERE status = 'pending'
         AND (next_attempt_at IS NULL OR next_attempt_at <= now)
         ORDER BY id ASC
         LIMIT 1
  -- Auto-sync only: this loop is invoked solely by connectivity / lifecycle / post-save.
  -- No UI "Sync now" or per-row Retry. After MAX attempts the item is 'failed' and is not selected.
  if no item: break
  if item.operation == UPDATE AND item.server_id is null:
     // should not happen if coalescing works; skip/fail
  set status = in_progress
  try:
    if CREATE: response = dio.post('/users', data: payload)
               serverId = parse id
               UPDATE users SET server_id, sync_status='synced', last_error=NULL
               UPDATE later UPDATE rows for local_id SET server_id = serverId (if any slipped in)
    if UPDATE: dio.put('/users/$serverId', data: payload)
               UPDATE users SET fields from response, sync_status='synced'
    set queue status = done  (or DELETE)
  catch retryable:
    attempt_count++
    if attempt_count >= 5: status=failed, users.sync_status=failed
    else: status=pending, next_attempt_at = now + backoff(attempt_count)
  catch non-retryable:
    status=failed, users.sync_status=failed, last_error=message
release mutex
```

**Per-record ordering:** FIFO `id` plus coalescing means CREATE is always the first item for a new user. Do not process UPDATE for `local_id` if a CREATE for that `local_id` is still not `done`.

**Backoff:** `2^attempt` seconds, capped at 32s (NFR-5).

**Done items:** `DELETE FROM sync_queue WHERE status = 'done'` after success (keeps table small). Failed rows remain.

### 7.4 Auto-sync triggers

| Trigger | Action |
|---------|--------|
| `connectivity_plus` stream: none → wifi/mobile | `trySync()` |
| App `AppLifecycleState.resumed` | `trySync()` |
| After local create/update commit | `trySync()` if currently online |
| Cold start after DB open | `trySync()` |

There is **no** manual “Sync now” and **no** per-row Retry button. All drains use the same `trySync()` from the triggers above. After max attempts, items stay `failed` until a later auto-sync eligible retry (retryable + `attempt_count` reset policy: on new offline→online transition, increment is preserved; items that already hit MAX stay failed for v1).

### 7.5 Sequence — offline create, then online

```
User            Repository          SQLite           Connectivity      SyncEngine         Dio
 |                  |                  |                  |                 |              |
 |--create--------->|                  |                  |                 |              |
 |                  |--BEGIN tx------->|                  |                 |              |
 |                  |--insert user---->|                  |                 |              |
 |                  |--insert queue--->|                  |                 |              |
 |                  |--COMMIT--------->|                  |                 |              |
 |<--show pending---|                  |                  |                 |              |
 |                  |                  |                  |--online-------->|              |
 |                  |                  |<--load queue-----|                 |              |
 |                  |                  |                  |                 |--POST /users>|
 |                  |                  |<--update user----|                 |<--201+id-----|
 |                  |                  |<--delete queue---|                 |              |
 |<--show synced----|                  |                  |                 |              |
```

### 7.6 Sequence — edit while CREATE still queued

```
updateUser → UPDATE users fields
          → UPDATE sync_queue.payload_json WHERE local_id AND operation=CREATE AND status=pending
          → no second queue row
```

---

## 8. Connectivity design

### 8.1 `ConnectivityService`

- Subscribe to `Connectivity().onConnectivityChanged`.
- Map `none` → offline; `wifi` | `mobile` | `ethernet` → candidate online.
- Debounce 300–500 ms to avoid flap during handoff.
- Optional second check: Dio `GET /users/1` or HEAD base URL with 3s timeout. If it fails, stay “offline for sync” but UI can still say “limited connectivity”.

### 8.2 Signals to UI

- `Stream<bool> isOnline` for banner (FR-UI3).
- SyncEngine listens to the same stream (FR-N2).

### 8.3 What not to do

- Do not use only a one-shot check at button press.
- Do not fail queue items as `failed` when offline (FR-N5).

---

## 9. Domain model (logical)

### 9.1 `User` entity

- `localId: String`
- `serverId: String?`
- `name: String`
- `email: String`
- `job: String?`
- `syncStatus: SyncStatus`
- `updatedAt: DateTime`
- `lastError: String?`

### 9.2 `UserRepository` API

| Method | Behaviour |
|--------|-----------|
| `Stream<List<User>> watchUsers()` | Query `users ORDER BY updated_at DESC` (poll or `Drift`-style; with sqflite, expose a change notifier after writes). |
| `Future<User> createUser(...)` | Validate + tx insert user + CREATE queue + trySync. |
| `Future<User> updateUser(localId, ...)` | Validate + tx update + coalesce queue + trySync. |
(No `retryFailed` UI API in v1 — auto-sync only.)

sqflite has no built-in table watchers: design a small `DatabaseChangeBus` that `watchUsers` listens to after each commit.

---

## 10. Presentation design (requirements mapping)

| Screen | Behaviour |
|--------|-----------|
| User list | Tiles from local DB; chip: Synced / Pending / Failed; subtitle email. |
| Create/Edit form | Same form; save calls repository; works offline. |
| App bar / banner | “Offline — changes will sync automatically”. |
| Failed | Show `last_error` only (no Retry / Sync button). |

Do not block the form on Dio.

---

## 11. Concurrency and locking

1. **DB:** all user+queue mutations in `db.transaction`.
2. **Sync:** one isolate/thread is enough; Flutter UI isolate + mutex is sufficient for v1 (no compute isolate required).
3. **UI vs sync:** SyncEngine updates rows; UI refreshes via change bus. Avoid long-lived `in_progress` without recovery (section 6.3).
4. **Dio:** do not share a cancelled token across unrelated items; new token per request, cancel on app dispose optional.

---

## 12. Idempotency and duplicates

| Risk | Mitigation |
|------|------------|
| POST succeeds, response lost, retry POST | Send `clientRequestId`; production API should upsert. Sample API may create duplicates — accept for sample; document. Optional v1: if create fails parse but 2xx, still store body. |
| Double SyncEngine | Mutex `_running`. |
| Two UPDATE payloads | Coalesce to latest JSON. |

---

## 13. Security and configuration

- Sample API: no secrets.
- Production: Dio interceptor adds `Authorization`; store token in secure storage (out of scope v1).
- SQL: parameterized queries only (`?` placeholders).
- Log payloads without PII in production if required later; v1 sample may log for debugging.

---

## 14. Testing strategy (for implementation phase)

| Layer | Tests |
|-------|--------|
| Coalescing | CREATE then UPDATE → one queue CREATE with latest JSON. |
| Processor | Mock Dio; assert POST then PUT order when server_id appears. |
| Offline | Mock connectivity offline; no Dio calls; rows pending. |
| Online restore | Emit connectivity event; Dio called. |
| Crash | Insert `in_progress`; engine start resets to `pending`. |
| Validation | Empty name → no queue row. |
| Retry | 500 then 200; attempt_count and eventual synced. |
| Widget | List shows pending chip (optional). |

Use `sqflite_common_ffi` for VM unit tests.

---

## 15. Observability

Log events (debug):

- `queue_enqueued` operation, local_id
- `sync_started` / `sync_item` / `sync_success` / `sync_retry` / `sync_failed`
- HTTP method, path, status code, attempt

No analytics vendor required in v1.

---

## 16. Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| JSONPlaceholder does not persist | QA confusion | Document in QA notes; still treat 2xx + `id` as success. Host stays JSONPlaceholder. |
| Duplicate POST | Extra server users | Idempotency key; mutex; in_progress recovery |
| Connectivity false positive | Failed attempts | Reachability ping; retryable errors |
| Queue growth | Disk | Delete `done`; cap failed with UI retry |
| Main-thread DB | Jank | `sqflite` already uses background; keep transactions short |

---

## 17. Implementation phases (when coding is approved)

Not part of this documentation delivery; listed for planning.

| Phase | Work |
|-------|------|
| 1 | sqflite schema, local CRUD, change bus |
| 2 | Queue enqueue + coalescing |
| 3 | Dio client + DTO mapping |
| 4 | SyncEngine + retry policy |
| 5 | Connectivity auto-sync + lifecycle |
| 6 | UI list/form/status |
| 7 | Tests and QA against sample API |

**Current phase: documents only.**

---

## 18. Requirements traceability (design)

| Requirement | Design section |
|-------------|----------------|
| FR-L1–L6 | §6 Schema, §3 LocalDataSource |
| FR-C1–C5 | §7.1, §7.5 |
| FR-U1–U4 | §7.2 |
| FR-Q1–Q7 | §6.2, §7 |
| FR-N1–N5 | §8 |
| FR-S1–S8 | §5, §7.3–7.4 |
| FR-UI1–UI4 | §10 |
| NFR-5 | §7.3 backoff |
| EC-3 | §6.3 |

---

## 19. Locked product decisions

- Entity: User; operations: create + update.
- Remote: **JSONPlaceholder** `POST /users`, `PUT /users/{id}` only.
- Sync: **auto-sync only** (connectivity, launch/resume, post-save while online). No Sync now, no Retry button.
- Coalescing CREATE+UPDATE; LWW via latest local payload.
- No background isolate/workmanager in v1.
- No delete, no GET list sync, no auth.

If remaining open questions (delete, GET list, auth, background jobs) change, update schema, API paths, and processor before coding.

---

## 20. Document history

| Version | Date | Notes |
|---------|------|--------|
| 0.1 | 2026-08-15 | Detailed design derived from requirements analysis; no implementation. |
| 0.2 | 2026-08-15 | JSONPlaceholder locked; auto-sync only (no manual Sync / Retry). |

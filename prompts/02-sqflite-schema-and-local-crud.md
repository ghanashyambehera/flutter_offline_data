# Prompt 02 — sqflite schema & local CRUD

References: **DESIGN §6, §9** | **REQUIREMENTS FR-L1–L6, FR-UI1**

---

## Task

Implement SQLite layer: schema, migrations, local user CRUD, and a change notification mechanism for the UI.

## Read first

- `docs/DESIGN.md` — §6 SQLite schema, §6.3 crash recovery stub, §9 domain model
- `docs/REQUIREMENTS_ANALYSIS.md` — §8.1 local storage, §9 sync statuses, §11 validation (BR-4)

## Schema (DESIGN §6)

### Table `users`

Columns: `local_id` (TEXT PK), `server_id` (TEXT NULL UNIQUE), `name`, `email`, `job`, `sync_status`, `created_at`, `updated_at`, `last_error`

Indexes: `sync_status`, `server_id`

### Table `sync_queue`

Implement table creation only in this phase (full queue logic in prompt 03). Columns per DESIGN §6.2.

### Database

- File: `offline_sync.db`, version `1`
- `PRAGMA foreign_keys = ON`
- `onCreate`: run CREATE TABLE statements from `core/database/tables.dart`
- `onUpgrade`: placeholder for future migrations

## Models

Create in `features/users/data/models/`:

- `user_local.dart` — map ↔ `users` row
- `sync_queue_item.dart` — map ↔ `sync_queue` row (used in next phase)

Create `features/users/domain/entities/user.dart` with `SyncStatus` enum:
`pendingCreate`, `pendingUpdate`, `synced`, `failed`

## LocalDataSource

`features/users/data/datasources/user_local_datasource.dart`:

| Method | Behaviour |
|--------|-----------|
| `insertUser` | Insert with generated UUID `local_id`, `sync_status = pending_create` |
| `updateUserFields` | Update name/email/job, `updated_at` |
| `getUserByLocalId` | Single row |
| `getAllUsers` | ORDER BY `updated_at DESC` |
| `watchUsers` / change bus | Notify listeners after writes (DESIGN §9.2) |

Use **parameterized queries** only (DESIGN §13).

## Validation (local only)

Before insert/update:

- `name`: required, non-empty, max 100 chars
- `email`: required, valid format
- `job`: optional, max 100 chars

Throw domain-friendly validation errors; do not write DB on failure.

## Crash recovery (prepare)

On DB open, run (DESIGN §6.3):

```sql
UPDATE sync_queue SET status = 'pending', updated_at = ? WHERE status = 'in_progress';
```

Safe even if queue is empty.

## Deliverables

- `app_database.dart`, `tables.dart`
- `UserLocal`, `User` entity, `UserLocalDataSource`
- Simple `DatabaseChangeBus` or equivalent for UI refresh
- Unit test: insert user → read back with correct `sync_status`

## Out of scope this phase

- Sync queue enqueue/coalescing
- Dio / SyncEngine
- UI screens (stub repository OK)

## Done when

You can insert and update users in SQLite programmatically; schema matches DESIGN §6.

# Prompt 03 — Sync queue enqueue & coalescing

References: **DESIGN §7.1–7.2** | **REQUIREMENTS FR-C1–C5, FR-U1–U4, FR-Q1–Q7, BR-1–BR-5**

---

## Task

Extend local writes so every create/update runs in a **single SQLite transaction** that updates both `users` and `sync_queue`, with **coalescing** per DESIGN §7.2.

## Read first

- `docs/DESIGN.md` — §7.1 Enqueue Create, §7.2 Enqueue Update (coalescing)
- `docs/REQUIREMENTS_ANALYSIS.md` — §8.2–8.4, §11 business rules

## UserRepository (domain façade)

`features/users/data/repositories/user_repository_impl.dart` implementing `UserRepository`:

| Method | Transaction steps |
|--------|---------------------|
| `createUser` | 1) INSERT user `pending_create` 2) INSERT queue `CREATE`, `status=pending`, `payload_json` = fields |
| `updateUser` | See coalescing rules below |

After commit: notify change bus. Do **not** call SyncEngine yet (next prompts).

## Coalescing rules (critical)

### Case A — user has no `server_id` (never synced)

- Update user fields; keep `sync_status = pending_create`
- Find existing queue row: same `local_id`, `operation=CREATE`, `status` in (`pending`, `in_progress`)
- **Update `payload_json`** to latest fields — do **not** insert UPDATE row

### Case B — user has `server_id`

- Set user `sync_status = pending_update`
- If pending UPDATE exists for `local_id`: replace `payload_json`
- Else INSERT queue `UPDATE` with `server_id` and payload

### Payload JSON shape

```json
{
  "name": "...",
  "email": "...",
  "job": "...",
  "clientRequestId": "<local_id>"
}
```

## Queue item fields

On enqueue: `entity_type=user`, `attempt_count=0`, `next_attempt_at=null`, `created_at`/`updated_at` now.

## Tests (required)

Using `sqflite_common_ffi`:

1. **Create offline:** 1 user row + 1 CREATE queue row
2. **Create then edit before sync:** still 1 CREATE queue row; payload has latest email/name
3. **Update synced user:** 1 UPDATE queue row with `server_id`
4. **Validation failure:** no queue row inserted

## Deliverables

- `UserRepository` + impl with transactional create/update
- Queue helper methods on LocalDataSource or dedicated `SyncQueueDataSource`
- Unit tests for coalescing

## Out of scope

- Processing queue / Dio calls
- Manual Sync or Retry UI/API

## Done when

Repository create/update always leaves DB in consistent user+queue state per DESIGN §7.1–7.2.

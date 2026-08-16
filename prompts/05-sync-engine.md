# Prompt 05 — SyncEngine (queue processor)

References: **DESIGN §7.3–7.6** | **REQUIREMENTS FR-S4–S8, FR-Q*, NFR-5, EC-3**

---

## Task

Implement `SyncEngine` that drains `sync_queue` using `UserRemoteDataSource`, updates local state, and applies retry/backoff. **Auto-sync only** — no manual trigger API for UI.

## Read first

- `docs/DESIGN.md` — §7.3 Processor algorithm, §7.5–7.6 sequences, §12 idempotency
- `docs/REQUIREMENTS_ANALYSIS.md` — §9 state model, §12 edge cases

## SyncEngine API

```dart
class SyncEngine {
  Future<void> trySync(); // no-op if offline or already running
}
```

## Algorithm (DESIGN §7.3)

1. If not online → return (connectivity injected)
2. Acquire mutex `_running`; if busy → return
3. Reset `in_progress` → `pending` (also on app start via DB open)
4. Loop:
   - Select next item: `status = pending`, `next_attempt_at <= now`, ORDER BY `id`, LIMIT 1
   - Skip UPDATE if `server_id` is null (coalescing should prevent this)
   - Set `in_progress`
   - **CREATE:** POST → set `users.server_id`, `sync_status=synced`, clear `last_error`, queue → `done` (delete row)
   - **UPDATE:** PUT → merge response, `sync_status=synced`, queue → `done`
   - On retryable error: increment `attempt_count`, set `next_attempt_at` with backoff `2^attempt` seconds (cap 32s), `status=pending`
   - On max attempts (5) or non-retryable: `status=failed`, user `sync_status=failed`, store `last_error`
5. Release mutex; if queue still has pending, optionally loop once more

## Wire UserRepository

After create/update commit, call `syncEngine.trySync()` **only if** connectivity reports online (DESIGN §7.4).

## Ordering

Do not process UPDATE for `local_id` while a CREATE for same `local_id` is not `done`.

## Deliverables

- `features/users/sync/sync_engine.dart`
- `features/users/sync/sync_policy.dart` (complete)
- Integration with repository + remote + local datasources
- Unit tests with mocked Dio:
  - CREATE success updates `server_id`
  - Retry on 500 then success
  - 404 → failed, no infinite retry
  - Mutex prevents concurrent drain

## Constraints

- **No** `retryFailed()` public method for UI
- **No** manual Sync button wiring

## Done when

Calling `trySync()` while online processes entire queue in FIFO order per DESIGN.

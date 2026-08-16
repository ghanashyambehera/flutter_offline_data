# Prompt 08 — Tests & QA checklist

References: **DESIGN §14–15** | **REQUIREMENTS §15 acceptance criteria, §12 edge cases**

---

## Task

Add automated tests and a QA checklist validating the implementation against the docs.

## Read first

- `docs/DESIGN.md` — §14 Testing strategy, §15 Observability
- `docs/REQUIREMENTS_ANALYSIS.md` — §15 Acceptance criteria, §12 Edge cases

## Unit / integration tests

Use `sqflite_common_ffi` for DB tests; mock Dio for remote.

| Test file | Coverage |
|-----------|----------|
| `sync_coalescing_test.dart` | CREATE + local edit → one queue row, latest payload |
| `sync_engine_test.dart` | POST then PUT order; retry 500; 404 → failed |
| `offline_create_test.dart` | No Dio calls when offline flag false |
| `connectivity_trigger_test.dart` | online transition calls trySync (mock) |
| `crash_recovery_test.dart` | `in_progress` reset to `pending` on engine start |
| `validation_test.dart` | empty name → no queue row |

## Widget tests (optional but recommended)

- List shows Pending chip for unsynced user
- Offline banner when `isOnline = false`

## QA manual checklist

Create `docs/QA_CHECKLIST.md` with steps:

### AC-1 Offline create
1. Enable airplane mode
2. Create user “Alice”
3. Expect: list shows Alice, status Pending
4. Expect: no crash; data in SQLite

### AC-2 Offline update
1. Edit Alice email offline
2. Expect: list updated immediately, still Pending

### AC-3 Auto-sync on reconnect
1. Disable airplane mode
2. Wait ≤ 30s
3. Expect: status Synced **without** tapping Sync (there is none)

### AC-4 App kill persistence
1. Create user offline
2. Force-stop app
3. Relaunch, go online
4. Expect: auto-sync completes

### AC-5 Failed state
1. Mock or use invalid server id for UPDATE → 404
2. Expect: Failed chip + `last_error` visible
3. Expect: **no** Retry button

### AC-6 JSONPlaceholder note
Document: API does not persist; success = HTTP 2xx + local `server_id` stored.

## Logging (debug)

Add debug logs per DESIGN §15:

- `queue_enqueued`, `sync_started`, `sync_success`, `sync_retry`, `sync_failed`

## Deliverables

- Test files under `test/`
- `docs/QA_CHECKLIST.md`
- All tests pass: `flutter test`

## Done when

Automated tests cover coalescing, sync order, offline guard, and crash recovery; QA doc maps to REQUIREMENTS §15.

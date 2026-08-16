# Prompt 06 — Connectivity & auto-sync triggers

References: **DESIGN §8, §7.4** | **REQUIREMENTS FR-N1–N5, FR-S4–S5, G3–G4**

---

## Task

Implement connectivity monitoring and wire **automatic** `SyncEngine.trySync()` triggers. No manual Sync control.

## Read first

- `docs/DESIGN.md` — §8 Connectivity design, §7.4 Auto-sync triggers
- `docs/REQUIREMENTS_ANALYSIS.md` — §8.5 connectivity, decision D-2 (auto-sync only)

## ConnectivityService

`core/connectivity/connectivity_service.dart`:

- Use `connectivity_plus` → `Stream<bool> isOnline`
- Map `ConnectivityResult.none` → false; wifi/mobile/ethernet → true
- Debounce 300–500 ms on stream
- Optional: lightweight Dio HEAD/GET to base URL; if fails, treat as offline-for-sync

## Auto-sync triggers (all call `syncEngine.trySync()`)

| Trigger | Where |
|---------|--------|
| Offline → online | Listen to `isOnline` stream in app bootstrap |
| App cold start | After DB open, if online |
| App resumed | `WidgetsBindingObserver` → `AppLifecycleState.resumed` |
| After local save | UserRepository after commit, if online |

## App wiring

In `app.dart` or a `SyncCoordinator`:

- Register lifecycle observer
- Subscribe to connectivity on init
- Dispose subscriptions on teardown

## UI signal (minimal)

Expose `isOnline` to presentation layer for offline banner (full UI in prompt 07).

## Deliverables

- `ConnectivityService`
- `SyncCoordinator` or equivalent wiring in `main.dart` / `app.dart`
- Verify: toggle airplane mode → queue drains without user action

## Constraints

- Do **not** add Sync now button
- Do **not** add Workmanager / background sync
- v1: foreground + resume only (REQUIREMENTS OQ-3 default)

## Done when

All four triggers from DESIGN §7.4 invoke `trySync()` and respect offline guard.

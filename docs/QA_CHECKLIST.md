# QA Checklist — Flutter Offline Data Sync

Manual verification against [REQUIREMENTS_ANALYSIS.md](./REQUIREMENTS_ANALYSIS.md) §15 and [DESIGN.md](./DESIGN.md).

**Locked behaviour:** JSONPlaceholder API, auto-sync only (no Sync / Retry buttons).

---

## AC-1 Offline create

1. Enable airplane mode (or disable Wi‑Fi/cellular).
2. Open the app → tap **+** → create user **Alice** (`alice@example.com`).
3. **Expect:** Alice appears in the list with **Pending** chip.
4. **Expect:** No crash; data stored locally.

## AC-2 Offline update

1. While still offline, tap Alice → change email → save.
2. **Expect:** List shows new email immediately.
3. **Expect:** Status remains **Pending**.

## AC-3 Auto-sync on reconnect

1. Disable airplane mode / restore network.
2. Wait up to 30 seconds.
3. **Expect:** Alice status becomes **Synced** automatically.
4. **Expect:** No Sync button in the app bar or elsewhere.

## AC-4 App kill persistence

1. Airplane mode ON → create user **Bob**.
2. Force-stop the app (swipe away / stop from settings).
3. Relaunch app → restore network.
4. **Expect:** Bob syncs to **Synced** without manual action.

## AC-5 Failed state (optional)

1. Edit a synced user while online (or after sync).
2. If an update fails with a non-retryable error (e.g. rare 404 on sample API):
3. **Expect:** **Failed** chip and error subtitle on the row.
4. **Expect:** No Retry button — auto-sync only.

## AC-6 JSONPlaceholder note

- JSONPlaceholder returns **2xx** but does **not** persist data on the server.
- App treats **HTTP 2xx + parseable `id` on POST** as success and stores `server_id` locally.
- A server GET would not return created users — this is expected for the sample API.

---

## Automated checks

```bash
flutter analyze
flutter test
```

## Reference docs

| Doc | Purpose |
|-----|---------|
| [REQUIREMENTS_ANALYSIS.md](./REQUIREMENTS_ANALYSIS.md) | What to build |
| [DESIGN.md](./DESIGN.md) | How it is built |
| [../prompts/README.md](../prompts/README.md) | Implementation prompts (phases 01–08) |

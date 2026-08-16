# Requirements Analysis: Flutter Offline Data Sync

**Document type:** Requirements analysis (no implementation)  
**Product:** Flutter mobile app with offline-first user create/update and automatic sync  
**Audience:** Product, engineering, QA  
**Status:** Draft for review  
**Date:** 15 August 2026

---

## 1. Purpose

This document captures **what** the system must do, **why**, and **what is in/out of scope**. It is the source of truth for the companion design document.

The app must let a user **create and update user records** while offline, persist them locally with **SQLite (sqflite)**, enqueue those changes in a **sync queue**, detect **network connectivity**, and **automatically sync** pending operations to a remote REST API via **Dio** when the device is online.

**This analysis does not include source code or implementation.** Implementation is a later phase.

---

## 2. Problem statement

Mobile networks are unreliable. Users still need to:

- Create a new user record
- Update an existing user record
- See their local data immediately (optimistic local write)
- Have those changes reach the server when connectivity returns, via auto-sync only (no manual Sync)

Without an offline model, create/update either fails or is lost. A naive “retry the last API call” is insufficient: multiple operations can accumulate, order matters, and local vs server IDs must be reconciled.

---

## 3. Goals and non-goals

### 3.1 Goals

| ID | Goal |
|----|------|
| G1 | Persist user create/update locally so the UI works with no internet. |
| G2 | Queue each pending mutation (create/update) for later sync. |
| G3 | Detect connectivity (online / offline / restored). |
| G4 | Auto-sync the queue when connectivity is restored and when the app is already online. |
| G5 | Call remote APIs with Dio (sample create/update endpoints). |
| G6 | Use sqflite as the only local database. |
| G7 | Make sync behaviour deterministic, observable, and recoverable after app kill/restart. |

### 3.2 Non-goals (this phase)

| ID | Non-goal |
|----|----------|
| NG1 | Implementing Dart/Flutter code, widgets, or packages in this repo (docs only). |
| NG2 | Delete-user sync, bulk import, file/image upload. |
| NG3 | Multi-user accounts, login, OAuth, refresh-token flows (sample API is unauthenticated unless noted). |
| NG4 | Real-time sync (WebSocket / Firebase). |
| NG5 | End-to-end encryption of local DB. |
| NG6 | Conflict UI for two devices editing the same record (strategy is specified; UI for merge is out of scope). |
| NG7 | Pagination, search, and server-side filtering of the user list (optional later). |

---

## 4. Stakeholders and users

| Role | Need |
|------|------|
| End user | Create/update users offline; data appears after reconnect without extra steps. |
| App developer | Clear contracts for DB, queue, API, and connectivity. |
| QA | Testable acceptance criteria for online, offline, and flaky network. |

---

## 5. Assumptions (please confirm)

These assumptions are used so analysis and design can proceed. Flag any that are wrong.

| ID | Assumption |
|----|------------|
| A1 | **Entity in scope is `User` only** (name, email, job/title-style fields). |
| A2 | **Operations in scope: Create and Update.** Read from local DB is required for UI; **Delete is out of scope**. |
| A3 | **Single device / single local database** (no multi-device merge UI). |
| A4 | **Sample API is JSONPlaceholder** (`https://jsonplaceholder.typicode.com`). Production would swap base URL and auth. |
| A5 | **Conflict policy: last-write-wins (LWW)** using local `updated_at` vs server `updatedAt` when both exist; if the sample API has no timestamps, **server response after successful PUT overwrites local**. |
| A6 | **Optimistic UI:** local write succeeds immediately; sync is asynchronous. |
| A7 | **Queue is FIFO** per record where possible; global queue is processed in insertion order. |
| A8 | **Connectivity:** treat “has network interface + can reach API host” as online; airplane mode / no Wi‑Fi / no cellular is offline. |
| A9 | **App lifecycle:** pending queue must survive process death (persisted in SQLite, not memory-only). |
| A10 | **Flutter target:** iOS and Android; sqflite + Dio + a connectivity package. |
| A11 | **No background OS sync job required in v1** (sync while app is in foreground or resumed). Optional: workmanager later. |
| A12 | **IDs:** local records may use a temporary UUID until the server returns a permanent `id`; queue items must track that mapping. |

If any of A1–A12 should change, the design document must be updated before implementation.

---

## 6. Scope

### 6.1 In scope

1. Local user table (sqflite).
2. Sync queue table (sqflite).
3. Connectivity monitoring and “became online” trigger.
4. Auto-sync worker that drains the queue using Dio.
5. Sample REST contracts for **POST (create)** and **PUT (update)**.
6. Local-first create/update flows and status on each record/queue item.
7. Error handling, retries with backoff, and dead-letter / failed status.
8. Requirements for logging/observability at a product level (not a specific logging SDK).

### 6.2 Out of scope

- Actual Flutter implementation and tests in this documentation phase.
- Authentication, authorization, and HTTPS pinning (noted as future).
- Server-side implementation (we consume a sample API).
- Admin dashboards.

---

## 7. User stories

| ID | Story | Priority |
|----|--------|----------|
| US-1 | As a user, I can create a user while offline and see it in the local list immediately. | Must |
| US-2 | As a user, I can edit a locally stored user while offline and see the new values immediately. | Must |
| US-3 | As a user, when internet returns, pending creates/updates sync automatically without tapping Sync. | Must |
| US-4 | As a user, I can see whether a record is synced, pending, or failed. | Must |
| US-5 | As a user, if sync fails due to a retryable error, the system retries automatically with backoff and attempt limits. There is no manual Sync control. | Must |
| US-6 | As a user, after I kill and reopen the app, unsynced changes are still there and will sync when online. | Must |
| US-7 | As a user, if I am already online, create/update still writes locally first then syncs (same path). | Must |
| US-8 | As a developer, I can point Dio at a sample base URL and swap it later. | Must |
| US-9 | As a user, I am not blocked from using the app solely because the last sync failed. | Should |
| US-10 | As a user, I get a non-blocking indication when the device is offline. | Should |

---

## 8. Functional requirements

### 8.1 Local storage (sqflite)

| ID | Requirement |
|----|-------------|
| FR-L1 | The app SHALL persist users in SQLite via **sqflite**. |
| FR-L2 | The app SHALL persist the sync queue in SQLite (same database, separate table). |
| FR-L3 | Local schema SHALL include: local primary key, optional server id, user fields, sync status, timestamps. |
| FR-L4 | All local writes SHALL be transactional where a user row and a queue row are created/updated together. |
| FR-L5 | The database SHALL be created/migrated on first launch (versioned schema). |
| FR-L6 | SharedPreferences or in-memory lists SHALL NOT be the source of truth for users or the queue. |

### 8.2 User create (offline-capable)

| ID | Requirement |
|----|-------------|
| FR-C1 | Create SHALL insert a local user with status `pending_create` (or equivalent). |
| FR-C2 | Create SHALL enqueue a queue item: operation `CREATE`, payload = user fields, `local_id`. |
| FR-C3 | Create SHALL NOT require network success to complete the UI action. |
| FR-C4 | After successful server create, local row SHALL store server `id` and status `synced`. |
| FR-C5 | The corresponding queue item SHALL be marked `done` or deleted. |

### 8.3 User update (offline-capable)

| ID | Requirement |
|----|-------------|
| FR-U1 | Update SHALL apply field changes to the local user immediately. |
| FR-U2 | Update SHALL enqueue operation `UPDATE` with payload and identifiers (`local_id` and `server_id` if known). |
| FR-U3 | If the user was never synced (`pending_create`), an update SHALL either: (a) mutate the existing CREATE payload, or (b) enqueue UPDATE after CREATE — **chosen policy: coalesce** (see FR-Q5). |
| FR-U4 | After successful server update, local row SHALL match server response and status `synced`. |

### 8.4 Sync queue

| ID | Requirement |
|----|-------------|
| FR-Q1 | The system SHALL maintain a durable FIFO sync queue. |
| FR-Q2 | Each item SHALL store: id, operation type, entity type (`user`), local_id, server_id (nullable), JSON payload, status, attempt_count, last_error, created_at, updated_at. |
| FR-Q3 | Queue processor SHALL process one item at a time (no parallel mutations on the same record). |
| FR-Q4 | Global processing MAY skip a blocked item and continue with the next **unrelated** local_id; items for the **same** local_id MUST stay ordered. |
| FR-Q5 | **Coalescing:** CREATE then UPDATE(s) on the same unsynced local_id SHALL result in a single CREATE with the latest payload (no extra CREATE). After server id exists, further edits SHALL be UPDATE only. |
| FR-Q6 | Duplicate identical pending UPDATEs for the same local_id SHOULD be coalesced to the latest payload. |
| FR-Q7 | Queue items in `done` MAY be deleted; `failed` items SHALL remain for inspection. v1 has no user discard or manual retry. |

### 8.5 Connectivity

| ID | Requirement |
|----|-------------|
| FR-N1 | The app SHALL observe connectivity changes (Wi‑Fi, cellular, none). |
| FR-N2 | Transition from offline → online SHALL trigger auto-sync if the queue is non-empty. |
| FR-N3 | App start / resume while online SHALL trigger auto-sync if the queue is non-empty. |
| FR-N4 | “Online” for sync SHALL mean connectivity package reports connected **and** Dio can complete a request (or a lightweight reachability check). False positives (captive portal) SHALL be treated as sync failure and retried. |
| FR-N5 | While offline, the processor SHALL not mark items as permanently failed solely due to lack of network. |

### 8.6 Auto-sync and API (Dio)

| ID | Requirement |
|----|-------------|
| FR-S1 | Network I/O SHALL use **Dio**. |
| FR-S2 | CREATE SHALL map to JSONPlaceholder `POST /users`. |
| FR-S3 | UPDATE SHALL map to JSONPlaceholder `PUT /users/{id}`. |
| FR-S4 | Auto-sync SHALL run without an explicit user tap when FR-N2 or FR-N3 applies, and after a successful local create/update while already online. |
| FR-S5 | The product SHALL NOT provide a manual “Sync now” (or equivalent) control. Queue drain is auto-sync only. |
| FR-S6 | HTTP 2xx SHALL be treated as success; 4xx (except 408/429) SHALL be non-retryable after logging; 5xx, timeouts, and connection errors SHALL be retryable. |
| FR-S7 | Retryable items SHALL use exponential backoff with a max attempt count (see NFRs). |
| FR-S8 | Only one sync worker SHALL run at a time (mutex / flag). |

### 8.7 UI / UX (requirements only)

| ID | Requirement |
|----|-------------|
| FR-UI1 | User list SHALL read from local SQLite. |
| FR-UI2 | Each row SHOULD show sync state: synced / pending / failed. |
| FR-UI3 | Offline banner or icon SHOULD appear when disconnected. |
| FR-UI4 | Create/update forms SHALL work offline. |

### 8.8 Sample API (functional contract)

The design uses **JSONPlaceholder** so developers can run the flow without a custom backend. Production may replace host and DTO names; v1 SHALL NOT use ReqRes or another sample host.

**Base URL (locked):** `https://jsonplaceholder.typicode.com`

| Operation | Method | Path | Notes |
|-----------|--------|------|--------|
| Create user | `POST` | `/users` | Body: JSON user fields. Response includes `id`. |
| Update user | `PUT` | `/users/{id}` | Path `id` is server id. Body: full or partial user JSON. |

**Create request body (canonical fields for this product):**

```json
{
  "name": "Jane Doe",
  "email": "jane@example.com",
  "job": "Engineer"
}
```

**Create success response (illustrative):**

```json
{
  "id": 11,
  "name": "Jane Doe",
  "email": "jane@example.com",
  "job": "Engineer"
}
```

**Update request:** same fields; URL includes server `id`.

**Requirement FR-API1:** Mapping from local columns ↔ JSON keys SHALL be documented in the design and isolated in a DTO/mapper layer.

**Requirement FR-API2:** Sample API may not persist data (JSONPlaceholder). The app SHALL still treat 2xx + returned `id` as success for local status. QA notes MUST state that a second GET might not return the created user.

---

## 9. Sync state model

### 9.1 User record statuses

| Status | Meaning |
|--------|---------|
| `synced` | Local data matches last successful server write. |
| `pending_create` | Local-only; never created on server. |
| `pending_update` | Has server id (or will after create); local changes not yet confirmed. |
| `failed` | Exhausted retries or non-retryable error; user/dev can inspect `last_error`. |

### 9.2 Queue item statuses

| Status | Meaning |
|--------|---------|
| `pending` | Waiting to be sent. |
| `in_progress` | Currently being processed (must reset to `pending` if app killed mid-flight). |
| `done` | Successfully applied on server. |
| `failed` | Terminal after max attempts or a non-retryable error. Recovery is a later auto-sync cycle only if the engine re-queues retryable items; no manual Sync. |

### 9.3 State transitions (user)

```
[new] --> pending_create --(POST 2xx)--> synced
pending_create --(local edit)--> pending_create (payload coalesced)
synced --(local edit)--> pending_update --(PUT 2xx)--> synced
any pending --(non-retryable or max retries)--> failed
(failed is terminal in v1; no manual retry transition)
```

---

## 10. Non-functional requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-1 | Reliability | Queue and users survive app kill, OS memory reclaim, and reboot (SQLite on disk). |
| NFR-2 | Consistency | User row + queue row updates for one action are atomic (single SQLite transaction). |
| NFR-3 | Performance | Local create/update returns to UI in < 200 ms on mid-range devices (excluding keyboard). |
| NFR-4 | Performance | Sync of 50 queued items should complete in a reasonable time on a normal network (order of seconds, not minutes), sequential processing. |
| NFR-5 | Retry | Exponential backoff: e.g. 2s, 4s, 8s, 16s, 32s; max 5 attempts per item then `failed`. |
| NFR-6 | Concurrency | Single sync worker; UI writes must not corrupt queue (transactions + worker lock). |
| NFR-7 | Observability | Log operation, local_id, http status, attempt count (no passwords; sample API has none). |
| NFR-8 | Maintainability | DB, queue, connectivity, and Dio layers are separable (see design). |
| NFR-9 | Security | Production: HTTPS only; no secrets in source. v1 sample API is public. |
| NFR-10 | Compatibility | Flutter 3.x; Android + iOS; sqflite, dio, connectivity_plus (or equivalent). |

---

## 11. Business rules

| ID | Rule |
|----|------|
| BR-1 | Local data is shown even if sync is pending or failed. |
| BR-2 | Do not POST create twice for the same local_id after a successful create (idempotency via local mapping of server id). |
| BR-3 | Do not PUT update until a server id exists; if only CREATE is pending, fold updates into CREATE payload. |
| BR-4 | Empty name or invalid email SHALL fail local validation and SHALL NOT enqueue. |
| BR-5 | Auto-sync is the **only** sync trigger path (connectivity restored, app start/resume, post-save while online). No manual Sync button. |

**Validation (v1):**

- `name`: required, non-empty, max 100 chars  
- `email`: required, basic email format  
- `job`: optional, max 100 chars  

---

## 12. Edge cases and error handling

| ID | Scenario | Expected behaviour |
|----|----------|-------------------|
| EC-1 | Airplane mode during create | Local save + queue; no HTTP; status pending. |
| EC-2 | Connectivity restored | Auto-sync starts; CREATE then any remaining UPDATEs. |
| EC-3 | App killed during `in_progress` | On next launch, `in_progress` → `pending`; retry (may duplicate if server already applied — see EC-4). |
| EC-4 | Duplicate create after timeout | Prefer idempotency key in payload (`client_request_id` = local UUID). Sample API may ignore it; design still sends it for production-ready contract. |
| EC-5 | PUT before POST completes | Forbidden by coalescing / per-local_id ordering. |
| EC-6 | 404 on update | Mark failed (record missing on sample API is common); do not infinite retry. |
| EC-7 | 500 / timeout | Retry with backoff; remain pending. |
| EC-8 | Captive portal (connected, no API) | Treat as retryable network error. |
| EC-9 | Rapid successive edits | Coalesce to latest payload. |
| EC-10 | Empty queue, come online | No-op; no error. |
| EC-11 | Invalid local data | Block enqueue; show validation error. |
| EC-12 | Schema upgrade | Migration required; v1 starts at version 1. |

---

## 13. Dependencies (libraries — specified, not implemented)

| Library | Role |
|---------|------|
| `sqflite` | Local SQLite persistence. |
| `path` / `path_provider` | DB file location. |
| `dio` | HTTP client for create/update. |
| `connectivity_plus` | Connectivity change stream (recommended). Optional extra: `internet_connection_checker_plus` for true reachability. |

Platform permissions: Android internet permission (default in Flutter); no special SQLite permission.

---

## 14. Constraints

- Documentation phase only: **do not implement** these operations in this phase.
- Sample API may be read-only / fake persistence; success is HTTP-level.
- No custom backend in v1.
- Flutter implementation later must follow the design document.

---

## 15. Acceptance criteria (for a future implementation)

The feature is accepted when:

1. Offline create stores a user in SQLite and shows it in the list with pending status.
2. Offline update changes local fields and queue payload without network.
3. Turning network off → on starts sync automatically; there is no manual sync button.
4. Successful POST stores server `id` and marks the user synced.
5. Successful PUT updates local fields from the response and marks synced.
6. Queue is empty (or only `done`/`failed` as designed) after successful drain.
7. Killing the app with pending items, relaunching, and going online still syncs.
8. Validation errors never create queue items.
9. Connectivity indicator reflects offline/online.
10. Dio is the only HTTP client for these APIs; sqflite is the only DB.

---

## 16. Traceability (stories → requirements)

| Story | Requirements |
|-------|----------------|
| US-1 | FR-C1–C3, FR-L1, FR-UI1, FR-UI4 |
| US-2 | FR-U1–U3, FR-Q5 |
| US-3 | FR-N2, FR-S4, FR-S5 |
| US-4 | FR-UI2, user statuses |
| US-5 | FR-S5, FR-S6, FR-S7, NFR-5 |
| US-6 | FR-L2, NFR-1, EC-3 |
| US-7 | FR-C3, FR-S4, FR-N3 |
| US-8 | FR-S1, FR-API1 |
| US-9 | BR-1 |
| US-10 | FR-UI3, FR-N1 |

---

## 17. Decisions and remaining open questions

### Decided

| ID | Decision |
|----|----------|
| D-1 | Sample API host is **JSONPlaceholder** (`https://jsonplaceholder.typicode.com`), `POST /users` and `PUT /users/{id}`. |
| D-2 | **Auto-sync only.** No manual “Sync now” (or equivalent) in the product. |

### Still open

| ID | Question | Default if unanswered |
|----|----------|------------------------|
| OQ-3 | Background sync when app is killed? | v1: no; sync on launch/resume/connectivity. |
| OQ-4 | Delete user in a later phase? | Yes, as a new queue operation `DELETE`. |
| OQ-5 | Auth header for production? | Bearer token interceptor; not in v1 sample. |
| OQ-6 | Pull-to-refresh GET list from server? | Out of scope v1 (local list only). |

---

## 18. Success metrics (post-implementation)

- Percentage of queue items that reach `done` within 60 seconds of reconnect.
- Number of duplicate server creates per local_id (target: 0 with idempotency).
- Crash-free local write rate.

---

## 19. Glossary

| Term | Definition |
|------|------------|
| Offline | Device cannot complete API calls (no network or unreachable host). |
| Sync queue | Durable list of mutations to apply on the server. |
| Coalescing | Combining multiple local edits into one queue payload. |
| Local id | UUID/integer primary key generated on device. |
| Server id | Identifier returned by POST create. |
| Auto-sync | Queue drain triggered by connectivity/app lifecycle, not only by a button. |

---

## 20. Document history

| Version | Date | Notes |
|---------|------|--------|
| 0.1 | 2026-08-15 | Initial requirements analysis; implementation explicitly out of scope. |
| 0.2 | 2026-08-15 | Locked JSONPlaceholder; auto-sync only (no manual Sync). |

**Related document:** [DESIGN.md](./DESIGN.md)

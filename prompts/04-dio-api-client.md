# Prompt 04 — Dio API client (JSONPlaceholder)

References: **DESIGN §5** | **REQUIREMENTS FR-S1–S3, FR-API1–FR-API2, §8.8**

---

## Task

Implement remote user API using **Dio** against **JSONPlaceholder** only.

## Read first

- `docs/DESIGN.md` — §5 Sample API design, §5.4 HTTP error classification
- `docs/REQUIREMENTS_ANALYSIS.md` — §8.8 sample API contract

## Locked API

| Operation | HTTP | Path |
|-----------|------|------|
| Create | POST | `/users` |
| Update | PUT | `/users/{serverId}` |

**Base URL:** `https://jsonplaceholder.typicode.com`

**Headers:** `Content-Type: application/json`, `Accept: application/json`, `X-Client-Request-Id: {local_id}`

## Files

```
core/network/dio_client.dart       # singleton/factory Dio with ApiConfig
core/network/api_exception.dart    # typed errors
features/users/data/models/user_dto.dart
features/users/data/datasources/user_remote_datasource.dart
```

## UserRemoteDataSource

| Method | Input | Output |
|--------|-------|--------|
| `createUser` | payload map | parsed `serverId` + response map |
| `updateUser` | `serverId`, payload map | response map |

## DTO mapping (DESIGN §5.3)

| Local | JSON |
|-------|------|
| name, email, job | same keys |
| local_id | `clientRequestId` in body |
| server id from response | `id` field (int or string → store as TEXT) |

## Error classification (`sync_policy.dart` stub)

Classify Dio errors for later SyncEngine:

- **Retryable:** connection timeout, connection error, 408, 429, 5xx
- **Non-retryable:** 400, 401, 403, 404, 422, 409; missing `id` on 2xx create

Export `SyncErrorClass { retryable, nonRetryable }` helper.

## Notes

JSONPlaceholder may not persist data — still treat **2xx + parseable `id` on POST** as success (REQUIREMENTS FR-API2). Document in code comment.

## Tests

- Mock Dio adapter: POST returns `{ "id": 11, ... }` → `serverId == "11"`
- PUT returns 200 → success
- 404 → non-retryable classification

## Deliverables

- Working `UserRemoteDataSource` with Dio
- `SyncPolicy` error classifier (no engine yet)

## Out of scope

- SyncEngine queue drain
- UI

## Done when

Remote datasource can create/update against JSONPlaceholder (or mock) with correct URLs and mapping.

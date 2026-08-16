# Prompt 07 — UI (list, form, status)

References: **DESIGN §10** | **REQUIREMENTS FR-UI1–UI4, US-1–US-4, US-10**

---

## Task

Build presentation layer: user list, create/edit form, sync status chips, offline banner. Read/write **only** through `UserRepository`.

## Read first

- `docs/DESIGN.md` — §10 Presentation design
- `docs/REQUIREMENTS_ANALYSIS.md` — §8.7 UI requirements, §9 statuses

## Screens

### User list (`user_list_page.dart`)

- Stream/list from `watchUsers()`
- Each tile: name, email, sync chip:
  - **Synced** — green/grey
  - **Pending** — amber (`pending_create` / `pending_update`)
  - **Failed** — red; show `last_error` as subtitle (read-only)
- FAB → navigate to create form
- Tap row → edit form

### Create / edit form (`user_form_page.dart`)

- Fields: name, email, job (optional)
- Save → `createUser` or `updateUser`
- Works offline (no blocking spinner on Dio)
- Show inline validation errors

### Offline banner

- When `!isOnline`: persistent banner e.g. “Offline — changes will sync automatically”
- Hide when online

## State management

Use Provider, Riverpod, or Bloc — not mandated. Inject:

- `UserRepository`
- `ConnectivityService` (or `isOnline` stream)

## Explicit exclusions

- **No** AppBar “Sync” action
- **No** “Retry” on failed rows
- **No** pull-to-refresh from JSONPlaceholder GET list

## Deliverables

- `user_list_page.dart`, `user_form_page.dart`
- Navigation from `app.dart` home
- Polished but minimal Material 3 styling

## Acceptance checks

1. Create user in airplane mode → appears in list as Pending
2. Turn network on → chip becomes Synced (JSONPlaceholder POST)
3. Edit offline → Pending → auto-sync on reconnect
4. Offline banner visible when disconnected

## Done when

Full create/update UX works offline-first with status visibility per REQUIREMENTS §15 items 1–4, 7–9.

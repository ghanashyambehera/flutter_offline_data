# Implementation Prompts — Flutter Offline Data Sync

Use these prompts to implement the app **phase by phase**. Each prompt references the authoritative docs:

| Document | Path | Role |
|----------|------|------|
| Requirements analysis | [`../docs/REQUIREMENTS_ANALYSIS.md`](../docs/REQUIREMENTS_ANALYSIS.md) | **What** to build |
| Detailed design | [`../docs/DESIGN.md`](../docs/DESIGN.md) | **How** to build it |

## Locked decisions (do not change in prompts)

- **Remote API:** JSONPlaceholder — `https://jsonplaceholder.typicode.com`
  - Create: `POST /users`
  - Update: `PUT /users/{id}`
- **Sync:** Auto-sync only (no Sync now, no Retry button)
- **Local DB:** sqflite only
- **HTTP:** Dio only
- **Entity:** User (create + update); no delete, no GET list sync in v1

## How to use

1. Attach or paste **`docs/REQUIREMENTS_ANALYSIS.md`** and **`docs/DESIGN.md`** into the chat (or ensure the agent can read them).
2. Run prompts **in order** (00 → 08). Later phases depend on earlier ones.
3. After each phase, verify deliverables before moving on.
4. Use **`00-master-implementation-prompt.md`** for a single end-to-end session if you prefer one large task.

## Prompt index

| # | File | Phase | Outcome |
|---|------|-------|---------|
| 00 | [00-master-implementation-prompt.md](./00-master-implementation-prompt.md) | All | Full app in one prompt |
| 01 | [01-project-setup.md](./01-project-setup.md) | Setup | Flutter project + dependencies |
| 02 | [02-sqflite-schema-and-local-crud.md](./02-sqflite-schema-and-local-crud.md) | 1 | Database, models, local CRUD |
| 03 | [03-sync-queue-and-coalescing.md](./03-sync-queue-and-coalescing.md) | 2 | Queue enqueue + coalescing |
| 04 | [04-dio-api-client.md](./04-dio-api-client.md) | 3 | Dio + JSONPlaceholder DTOs |
| 05 | [05-sync-engine.md](./05-sync-engine.md) | 4 | Queue processor, retry, mutex |
| 06 | [06-connectivity-auto-sync.md](./06-connectivity-auto-sync.md) | 5 | Connectivity + lifecycle triggers |
| 07 | [07-ui-presentation.md](./07-ui-presentation.md) | 6 | List, form, offline banner, badges |
| 08 | [08-tests-and-qa.md](./08-tests-and-qa.md) | 7 | Unit/widget tests + QA checklist |

## Traceability

Design implementation phases (§17) map to prompts 01–08. Requirements acceptance criteria (REQUIREMENTS_ANALYSIS §15) are included in prompts 05–08.

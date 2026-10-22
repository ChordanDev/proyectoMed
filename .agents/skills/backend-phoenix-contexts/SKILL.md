---
name: backend-phoenix-contexts
description: "Trigger: backend architecture, Phoenix contexts, Elixir modular monolith, Ecto, BackendWeb controllers or LiveViews. Apply Phoenix context interface and web-layer invariants."
license: Apache-2.0
metadata:
  author: ChordanDev
  version: "2.0"
---

## Activation Contract

Load this skill when:

- Creating or modifying backend modules under `backend/lib/backend/` or `backend/lib/backend_web/`.
- Working with domain capabilities, Ecto schemas, migrations, queries, API endpoints, or LiveView pages.
- Integrating external services or AI providers across external seams.

Do not load for purely frontend web tasks.

## Hard Rules

- The backend is a modular monolith structured around Phoenix Contexts acting as deep modules for high Leverage (ADR-007 #92 and its amendment).
- Four public context interfaces, one module each:
  - `Backend.Stations` (`backend/lib/backend/stations.ex`): sessions, conversation, Station AI, impressos, grading, the Educational Result and its history, per-session usage.
  - `Backend.Accounts` (`backend/lib/backend/accounts.ex`): users with roles `admin` and `student`, terms acceptance, account deletion, device-login tokens.
  - `Backend.Billing` (`backend/lib/backend/billing.ex`): RevenueCat webhook (signature, idempotency), entitlement and plan, quota check.
  - `Backend.Content` (`backend/lib/backend/content.ex`): cases, case revisions, the case format parser, `pending -> approved | disapproved` transitions, published Station versions.
- Internal implementation modules reside strictly under `backend/lib/backend/<context>/`. Callers outside a context use only its public module. Do NOT add a fifth context without an ADR.
- Dependencies point one way, with no cycles: `Stations` may call `Content`, `Billing` and `Accounts`; `Billing` may call `Accounts`; `Content` and `Accounts` call no other context.
- Persistence is Postgres through Ecto (`Backend.Repo`, ADR-014 #346). Only contexts use `Backend.Repo` and own their schemas; `BackendWeb` never calls the Repo or a schema module directly.
- `BackendWeb` controllers, LiveViews (ADR-015 #347), plugs, and channels MUST only call public context modules; never reach into internal implementation modules directly.
- Keep `BackendWeb` thin: restrict it to request decoding, parameter validation, routing, delegating to a public context, and rendering HTML or serializing JSON. Validation rules, status transitions and revisions live in the contexts.
- Learner-facing LiveView copy is Brazilian Portuguese (pt-BR).
- Introduce behaviours and adapters ONLY at external variable seams (e.g. third-party LLM providers, speech services, RevenueCat). Never create speculative abstractions or adapters for internal implementations.
- Do not introduce umbrella apps or full hexagonal architecture without a new accepted ADR.
- Colocate tests: context tests in `backend/test/backend/` (`Backend.DataCase` when they touch the database), controller tests in `backend/test/backend_web/controllers/` and LiveView tests in `backend/test/backend_web/live/` (`BackendWeb.ConnCase` with `Phoenix.LiveViewTest`). Every test runs inside the Ecto SQL sandbox.

## Decision Gates

| Need | Destination | Pattern |
| --- | --- | --- |
| HTTP request routing & JSON serialization | `backend/lib/backend_web/controllers/` | Thin controller delegating to a public context. |
| Browser page (account, billing, admin) | `backend/lib/backend_web/live/` | Thin LiveView delegating to a public context. |
| Public domain operations | `backend/lib/backend/<context>.ex` | Public interface module providing Depth and Leverage. |
| Internal domain implementation, schemas and queries | `backend/lib/backend/<context>/` | Internal modules encapsulated behind the context. |
| Database schema change | `backend/priv/repo/migrations/` | Ecto migration; `mix test` migrates the test database. |
| External provider with variable integration | External seam | Define Elixir behaviour and concrete adapter modules. |
| Internal single-purpose logic | Internal module | Direct implementation without speculative adapter. |

## Execution Steps

1. Pick the owning context from the Hard Rules and expose the capability through its public module only.
2. Encapsulate business logic, state, schemas, and queries in internal modules under `backend/lib/backend/<context>/`.
3. If an external service seam varies, define a clear behaviour and adapter module (e.g. `Backend.Stations.StationAI.OpenAIAdapter`).
4. Implement thin controllers in `backend_web/controllers/` or thin LiveViews in `backend_web/live/` delegating directly to the public context.
5. Write corresponding tests under `backend/test/backend/` and `backend/test/backend_web/`.
6. Run test suite: `mix test` inside `backend/` (needs a local Postgres; it creates and migrates the test database).

## Output Contract

Return:

- File paths created or modified under `backend/`.
- Confirmation that `BackendWeb` remains thin and calls only public context modules, never the Repo or internal modules.
- Verification test results.

## References

- `AGENTS.md` — Project architecture invariants and skill registration.
- `docs/agents/domain.md` — Repository domain docs and ADR conventions.

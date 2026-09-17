---
name: backend-phoenix-contexts
description: "Trigger: backend architecture, Phoenix contexts, Elixir modular monolith, BackendWeb controllers. Apply Phoenix context interface and web-layer invariants."
license: Apache-2.0
metadata:
  author: ChordanDev
  version: "1.0"
---

## Activation Contract

Load this skill when:

- Creating or modifying backend modules under `backend/lib/backend/` or `backend/lib/backend_web/`.
- Working with domain capabilities, schemas, queries, or API endpoints.
- Integrating external services or AI providers across external seams.

Do not load for purely frontend web tasks.

## Hard Rules

- The backend is a modular monolith structured around Phoenix Contexts acting as deep modules for high Leverage.
- Maintain ONE domain context interface: `Backend.Stations` (`backend/lib/backend/stations.ex`) is the public interface module for clinical stations, conversations, packages, evaluations, and station AI.
- Internal implementation modules reside strictly under `backend/lib/backend/stations/` (e.g. Conversation, Station Package loader, Evaluator, Station AI). Do NOT introduce separate top-level Phoenix Contexts for these internal implementations.
- `BackendWeb` controllers, plugs, and channels MUST only call the public interface module `Backend.Stations`; never reach into internal implementation modules directly.
- Keep `BackendWeb` thin: restrict it to request decoding, parameter validation, routing, delegating to `Backend.Stations`, and serializing JSON responses.
- Introduce behaviours and adapters ONLY at external variable seams (e.g. third-party LLM providers or speech services). Never create speculative abstractions or adapters for internal implementations.
- Do not introduce umbrella apps or full hexagonal architecture without a new accepted ADR.
- Colocate tests: context tests in `backend/test/backend/` and web controller tests in `backend/test/backend_web/controllers/`.

## Decision Gates

| Need | Destination | Pattern |
| --- | --- | --- |
| HTTP request routing & JSON serialization | `backend/lib/backend_web/` | Thin controller delegating to `Backend.Stations`. |
| Public domain operations | `backend/lib/backend/stations.ex` | Public interface module providing Depth and Leverage. |
| Internal domain implementation | `backend/lib/backend/stations/` | Internal modules encapsulated behind `Backend.Stations`. |
| External provider with variable integration | External seam | Define Elixir behaviour and concrete adapter modules. |
| Internal single-purpose logic | Internal module | Direct implementation without speculative adapter. |

## Execution Steps

1. Expose public domain capabilities exclusively through the `Backend.Stations` interface module.
2. Encapsulate business logic, state, and data loading in internal modules under `backend/lib/backend/stations/`.
3. If an external service seam varies, define a clear behaviour and adapter module (e.g. `Backend.Stations.StationAI.OpenAIAdapter`).
4. Implement thin controllers in `backend_web/controllers/` delegating directly to `Backend.Stations`.
5. Write corresponding tests under `backend/test/backend/` and `backend/test/backend_web/`.
6. Run test suite: `mix test` inside `backend/`.

## Output Contract

Return:

- File paths created or modified under `backend/`.
- Confirmation that `BackendWeb` remains thin and calls only the public `Backend.Stations` interface module.
- Verification test results.

## References

- `AGENTS.md` — Project architecture invariants and skill registration.
- `docs/agents/domain.md` — Repository domain docs and ADR conventions.

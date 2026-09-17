---
name: frontend-feature-first
description: "Trigger: frontend architecture, Vite SPA, web feature slices, web components. Apply feature-first structure and dependency invariants under web/src."
license: Apache-2.0
metadata:
  author: ChordanDev
  version: "1.0"
---

## Activation Contract

Load this skill when:

- Creating or reorganizing web application code under `web/src/`.
- Adding new feature slices, views, components, state hooks, or API clients.
- Deciding whether code belongs in `features/` or `shared/`.

Do not load for purely backend Elixir/Phoenix tasks.

## Hard Rules

- Strictly enforce unidirectional dependency flow: `app -> features -> shared`.
- `shared` MUST NOT import from `features` or `app`.
- A feature MUST NOT import internal implementation modules from sibling features; communicate only through public interfaces or shared primitives.
- Colocate tests: place unit and component tests beside the code they verify or in immediate `__tests__` subdirectories within that module. Run tests via `npm --prefix web test`.
- Maximize Locality: keep code inside the feature until two distinct features require identical behavior. Share only after real reuse to avoid shallow premature abstractions.
- Keep `web/src/App.tsx` thin: root application shell delegates view composition and business logic to feature modules (e.g. `web/src/features/station/`).

## Decision Gates

| Question | Destination | Rule |
| --- | --- | --- |
| Root shell, top-level providers, or routing? | `web/src/App.tsx` or `web/src/app/` | Thin layer delegating to feature module. |
| Vertical domain slice (e.g. clinical station)? | `web/src/features/<feature>/` (e.g. `web/src/features/station/`) | Colocate UI, state, hooks, API, and tests for Locality. |
| Reused across 2+ distinct features without domain coupling? | `web/src/shared/` | Generic UI primitives, formatting, base HTTP client. |
| Single-feature helper or component? | Keep in owning feature module | Preserve Locality; do not promote to `shared`. |

## Execution Steps

1. Identify the feature slice for the requested capability under `web/src/features/<feature>/`.
2. Encapsulate state, components, and API calls within the feature module to ensure Depth.
3. Colocate tests alongside the implementation (e.g., `StationView.test.tsx`).
4. Wire entrypoints in `web/src/App.tsx` or `web/src/app/`, ensuring unidirectional flow `app -> features -> shared`.
5. Verify changes with focused test runs: `npm --prefix web test`.

## Output Contract

Return:

- File paths created or modified under `web/src/`.
- Confirmation that unidirectional dependency flow `app -> features -> shared` is preserved.
- Verification test results.

## References

- `AGENTS.md` — Repository architecture invariants and skill registration.
- `docs/agents/domain.md` — Repository domain docs and ADR conventions.

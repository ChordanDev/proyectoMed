# 329 — Postgres and Phoenix LiveView in the backend

Issue: #329 (parent spec #326). Branch: `feat/329-postgres-liveview` → PR base `feat/326-production-launch`.

## Objective

Prefactor the backend so the next slices can store data and serve LiveView pages, with no visible behaviour change: Ecto and a Repo on Postgres, migrations wired, a sandboxed test database in the test script and the GitHub workflow, and Phoenix LiveView with a minimal layout and one placeholder page.

## Why

ADR-014 (#346) moves learner data to Postgres (Neon in production) through Ecto, and ADR-015 (#347) serves the account, billing and admin web as LiveView in `BackendWeb`. The Accounts (#331) and admin panel (#344) slices need both in place.

## Constraints

- Dev and test default to a local Postgres (`localhost:5432`, OS user, no password); `DATABASE_URL` overrides dev and is required in prod. No credentials are committed.
- `scripts/test.sh` stays the single test entry point: `mix test` creates and migrates the test database itself (mix alias), so the external local CI script keeps working unchanged.
- Every existing JSON API route and the frozen `web/` SPA stay untouched.
- LiveView pages stay thin (ADR-007 amendment on #92): they call public contexts only.
- Learner-facing copy in pt-BR; artifacts in English.

## Checklist

- [x] T1 — Ecto Repo on Postgres: `Backend.Repo`, dev/test/runtime config, `priv/repo/migrations`, `Backend.DataCase` and sandbox in `ConnCase`, `test` mix alias, Postgres service in the workflow, README env vars.
- [x] T2 — LiveView and assets: `phoenix_live_view`, esbuild and Tailwind as Phoenix 1.8 generates them, session and `/live` socket, root layout, placeholder `/admin` LiveView in pt-BR.
- [ ] T3 — Architecture docs: `AGENTS.md` and the `backend-phoenix-contexts` skill reflect the ADR-007 amendment (Accounts, Billing, Content contexts; `BackendWeb` serves LiveView).

## Routing

All tasks: delegated direct (this worker is the single bounded writer for the issue).

## Acceptance criteria

- The backend boots against Postgres from an env URL and runs migrations.
- The full test suite runs with a sandboxed test database and stays green.
- LiveView renders a placeholder page in development.
- No secret is committed; README documents the new env vars.

## Checks

- Focused: `mix test <file>` per task (RED then GREEN).
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`) must print `LOCAL CI PASSED`.

## Progress

- T1 done (delegated direct). RED: `test/backend/repo_test.exs` failed to compile (`Backend.DataCase` missing); `test/backend/config/database_config_test.exs` 2/7 against the previous `runtime.exs`. GREEN: 3/3 and 7/7; the two runtime config tests that read `:prod` now supply a `DATABASE_URL`. Full ExUnit and E2E (4/4, dev boot without a `backend_dev` database) green.
- T1 commit: `6efd2b7`.
- T2 done (delegated direct). RED: `test/backend_web/live/admin_live_test.exs` failed to compile (no `/admin` route, no `Phoenix.LiveViewTest`). GREEN: 1/1. Assets copied from a Phoenix 1.8.13 generator run (`mix phx.new backend --app backend --module Backend`), including daisyUI and Heroicons so `phx.gen.auth` (#331) finds the components it expects. Build output is ignored by `backend/priv/static/.gitignore`. `mix assets.build` and `PORT=4134 mix phx.server` serve `/admin` (200, CSS 200); `/` still answers `{"status":"ok"}`.

## Next step

T3.

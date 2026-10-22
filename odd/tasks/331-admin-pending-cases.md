# 331 — Show pending cases to an admin in the case panel

Issue: #331 (parent spec #326). Branch: `feat/331-admin-pending-cases` → PR base `feat/326-production-launch`.

## Objective

A pending case row inserted into the `cases` table (as n8n will do: area, theme, Markdown) appears in a LiveView admin panel that only admins can open. The list shows number, area, theme and status, filters by status and area, and a pending case shows its located parser errors at the top.

## Why

Doctor review is the critical path of the launch (#326, ADR-015 #347). n8n generates cases and inserts them as pending rows; doctors need a place to find them and see at once whether a case can be published as is.

## Constraints

- Accounts via `phx.gen.auth` (Phoenix 1.8, LiveView variant) inside `Backend.Accounts`, with roles `admin` and `student` (ADR-014 #346). No public sign-up path in this issue: admins are provisioned by a mix task (student sign-up is #336).
- Content context `Backend.Content` owns the `cases` table (ADR-007 #92 amendment). `Content` and `Accounts` call no other context.
- Parser errors come from `Backend.Stations.parse_case/1` (#330). The LiveView composes `Content` and `Stations`; `Content` never calls `Stations`.
- `BackendWeb` stays thin and never calls the Repo (architecture test).
- Panel copy in pt-BR. Local Postgres only; never Neon.
- Planning heuristic: about 400 authored changed lines per task (T1 is larger because `phx.gen.auth` output is generated).

## Checklist

- [x] T1 — Accounts: `phx.gen.auth` LiveView variant with an `admin`/`student` role, registration removed, admin provisioning through `priv/repo/seeds.exs` (the allowed edit surfaces exclude `lib/mix/tasks`), admin-only `/admin` (anonymous → login, student → redirected).
- [x] T2 — Content: `cases` migration (identity `number`, area, theme, markdown, status pending/approved/disapproved, DB-defaulted timestamps), `Backend.Content` list/filter/get, n8n insert contract in `docs/case-format`.
- [x] T3 — Admin case panel: list with number, area, theme, status and status/area filters; case page with the located parser errors at the top; decision on computing errors on read documented.
- [x] T4 — Screenshots of the list and of an invalid case (seeded admin, `PORT=4135`, `MIX_ENV=dev`), PR.

## Routing

All tasks: delegated direct (this worker is the single bounded writer for the issue; 2+ non-trivial files per task).

## Acceptance criteria

- Inserting a valid pending row makes it appear in the list with its sequential number.
- Inserting an invalid row shows its located parser errors.
- Only admin users can open the panel; others are redirected.
- Filtering by status and area works.

## Checks

- Focused: `mix test test/backend/accounts_test.exs test/backend/content_test.exs test/backend_web/live`.
- Full: local CI script (backend tests, web typecheck/lint, format, compile warnings, credo strict, dialyzer).

## Progress

- T1 (Accounts): ran `mix phx.gen.auth Accounts User users --live`; added `role` (`admin`/`student`, DB check constraint, never cast), `Accounts.create_admin/1`, `Accounts.admin?/1`, admin provisioning in `priv/repo/seeds.exs` (`ADMIN_EMAIL`/`ADMIN_PASSWORD`), `require_admin_user` plug and `:require_admin` on_mount on `/admin`; removed the public registration page and route; mailer moved to `Backend.Accounts.Mailer` (Swoosh local adapter, `/dev/mailbox` in dev); generated copy translated to pt-BR. RED — 13/14 new role/seed/access tests failed (undefined `create_admin/1`, `admin?/1`, no role, `/admin` open to anyone); GREEN — 14/14, full backend suite 1926/1926 (MIX_TEST_PARTITION=_issue331). Credo strict clean, compile warnings-as-errors clean. One run showed a flaky failure in `Backend.LLMProviderConfigTest` (env-var test, passed alone and in two reruns; unrelated).

- T1 commit: 9a9cc53.
- T2 (Content): migration `create_cases` (`number` `GENERATED ALWAYS AS IDENTITY`, `status` check constraint, UTC `timezone('utc', now())` timestamp defaults), `Backend.Content.Case`, `Backend.Content` (`list_cases/1` with status/area filters, `list_areas/0`, `get_case!/1`, `get_case_by_number/1`, `statuses/0`); n8n insert contract and the compute-on-read decision in `docs/case-format/README.md`. RED — 12/12 new Content tests failed (no table, no module); GREEN — 12/12 (plus a UTC assertion), full backend suite 1938/1938.

- T2 commit: 2f3174f.
- T3 (panel, commit 0e4b27c + this docs commit): `BackendWeb.AdminCaseLive.Index` (`/admin`, filters as URL params through `push_patch`) and `BackendWeb.AdminCaseLive.Show` (`/admin/cases/:number`: errors from `Backend.Stations.parse_case/1` at the top, each linked to its numbered line, then the Markdown with numbered lines); the #329 placeholder `AdminLive` is removed. Compute-on-read rationale is in `docs/case-format/README.md` and the Show moduledoc. RED — 10/10 new panel tests failed (no route/module); GREEN — 10/10, all LiveView tests 39/39. Parser messages stay in English (they come from #330); the surrounding copy is pt-BR.

- T3 commits: 0e4b27c, b6ef296.
- T4 (checks and evidence): local CI script — LOCAL CI PASSED: web unit 337/337, backend ExUnit 1947/1947, E2E 4/4, typecheck, lint, format, compile warnings-as-errors, credo strict, dialyzer 0 errors. Two earlier CI runs failed only web vitest timeouts with ~1 050 000 ms durations (the machine was suspended mid-run; no web files changed); the third run passed. Screenshots (seeded admin `medica@example.com`, isolated dev database `backend_dev_issue331`, `PORT=4135`, `MIX_ENV=dev`, Firefox headless `-no-remote` with a throwaway profile): case list with four statuses, invalid case 2 with four located errors at the top. The flash toast overlaps the generated top menu (cosmetic, follow-up).

## Next step

Push and open the PR against `feat/326-production-launch`; review follow-ups.

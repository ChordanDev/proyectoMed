# 333 — Approve or disapprove a case and publish it to the station catalog

Issue: #333 (parent spec #326). Branch: `feat/333-approve-case-catalog` → PR base `feat/326-production-launch`. Delivery strategy: `ask-on-risk`. Test runner: `(cd backend && MIX_TEST_PARTITION=_issue333 mix test)`.

## Specs

- **S1** (Issue #333 verbatim): "Approve publishes the case as an immutable Station version, only when it has no parser errors, records who approved it and when, and makes it appear in GET /stations (id, area, theme, actors). Disapprove hides it. Editing an approved case and approving again creates a new version."
  - Check: `MIX_TEST_PARTITION=_issue333 mix test test/backend/content_test.exs test/backend_web/controllers/station_controller_test.exs test/backend_web/live/admin_case_live_test.exs`
- **S2** (Issue #333 AC1 verbatim): "Approve is disabled while errors exist"
  - Check: `MIX_TEST_PARTITION=_issue333 mix test test/backend_web/live/admin_case_live_test.exs test/backend/content_test.exs`
- **S3** (Issue #333 AC2 verbatim): "An approved case appears in the catalog API; a disapproved one does not"
  - Check: `MIX_TEST_PARTITION=_issue333 mix test test/backend_web/controllers/station_controller_test.exs`
- **S4** (Issue #333 AC3 verbatim): "Re-approving after an edit creates a new immutable version; the previous version stays readable"
  - Check: `MIX_TEST_PARTITION=_issue333 mix test test/backend/content_test.exs test/backend_web/controllers/station_controller_test.exs`
- **S5** (Issue #333 AC4 verbatim): "Approver and timestamp are stored"
  - Check: `MIX_TEST_PARTITION=_issue333 mix test test/backend/content_test.exs test/backend_web/live/admin_case_live_test.exs`
- **S6** (Architectural & Repo Invariants):
  - `Backend.Content` calls no other context (`Backend.Stations.parse_case/1` is called by `BackendWeb.AdminCaseLive.Show` or `Backend.Stations`, never by `Backend.Content`).
  - `BackendWeb` stays thin and never calls `Backend.Repo` or internal modules directly (`Backend.ArchitectureTest`).
  - Admin-only foreign keys to `users` (`cases.approved_by_id`, `station_versions.approved_by_id`) use `on_delete: :nilify_all`, keep an email snapshot (`approved_by_email`), and are listed in `Backend.Accounts.AccountDeletionTest`.
  - n8n insert contract (`INSERT INTO cases (area, theme, markdown)`) remains untouched.

## Tasks

- [x] T1 — S1, S2, S4, S5, S6 — delegated (`gentle-ai-worker`, context backstop) — Content context & DB migration: `cases` approval metadata (`approved_by_id`, `approved_by_email`, `approved_at`), `station_versions` table and `Backend.Content.StationVersion` schema, `Content.approve_case/3`, `Content.disapprove_case/1`, `Content.get_station_version!/1`, `Content.get_station_version/1`, `Content.list_station_versions/1`, `Content.list_published_stations/0`, `Stations.list_catalog_stations/0`, `AccountDeletionTest` admin-only FK update, `docs/case-format/README.md`, and `test/backend/content_test.exs`. Commit `b3eb60f` (RED 9/9 fail -> GREEN 39/39 pass).
- [x] T2 — S1, S2, S3, S4, S5, S6 — delegated (`gentle-ai-worker`, context backstop) — Web layer (Admin LiveView + Catalog HTTP API): approve/disapprove actions and approver display in `BackendWeb.AdminCaseLive.Show` and `BackendWeb.AdminCaseLive.Index`, `GET /stations` and `GET /api/stations` catalog route in `BackendWeb.Router` and `BackendWeb.StationController`, LiveView tests in `test/backend_web/live/admin_case_live_test.exs`, and controller tests in `test/backend_web/controllers/station_controller_test.exs`. Commit `439c069` (RED 9/9 fail -> GREEN 127/127 pass).
- [x] T3 — S1, S2, S3, S4, S5, S6 — inline — Full verification, differential check, and closure. Full backend suite 2048/2048 passed, dialyzer 0 errors, credo strict 0 issues.
- [x] R1 — DATA-001, tx-resilience-02 — inline — Jorge advisory review fixes (`gemini-3.8-flash`): approval idempotency and disapproval metadata cleanup. Commit `de908ab`. ExUnit 2049/2049 passed, dialyzer 0 errors, credo clean. PR comment posted.
- [x] R2 — S5, S6 — delegated (bounded writer) — Independent verification fixes: catalog identity is the case number (`id`, plus `version` and display-only `slug`), `GET /stations` documented in `docs/unreal-station-client.md`, `case_revision_id` semantics documented. Commit `687cda3`. ExUnit 2051/2051 passed, dialyzer 0 errors, credo clean.

## Log

- **L1** (2026-10-22, user request verbatim):
  - "la issue 333 no está hecha?"
  - "dale"
- **L2** (2026-10-22, exploration & routing):
  - Created branch `feat/333-approve-case-catalog` from `origin/feat/326-production-launch` (`33a6853`).
  - Verified context boundaries: `Backend.Content` calls no other context; `Backend.Stations` may call `Backend.Content`; `BackendWeb` controllers only call `Backend.Stations` (enforced by `test/backend/architecture_test.exs`), while `AdminCaseLive` calls `Backend.Content` and `Backend.Stations.parse_case/1`.
  - Context backstop fired at 157k tokens; T1 and T2 are routed to `gentle-ai-worker` sequentially (T2 depends on T1's context functions).
- **L3** (2026-10-22, T1 completed):
  - `b3eb60f`: Added migration `20261022130000_create_station_versions.exs`, `Backend.Content.StationVersion`, `Case.approve_changeset/2`, `Case.disapprove_changeset/1`, `Content.approve_case/3`, `Content.disapprove_case/1`, `Content.get_station_version!/1`, `Content.get_station_version/1`, `Content.list_station_versions/1`, `Content.list_published_stations/0`, and `Stations.list_catalog_stations/0`.
  - Updated `Backend.Accounts.AccountDeletionTest` admin-only foreign keys (`cases.approved_by_id`, `station_versions.approved_by_id`).
  - RED: 9 failures (`Backend.Content.approve_case/3` undefined). GREEN: 39/39 passed, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` clean.
  - Note on commit slice hook: `origin/main` has 106k lines because `feat/326-production-launch` branches from `develop` per `AGENTS.md` Git workflow; actual diff against `origin/feat/326-production-launch` is 558 lines (including tests and docs).
- **L4** (2026-10-22, T2 completed):
  - `439c069`: Added `GET /stations` and `GET /api/stations` in `BackendWeb.Router` and `BackendWeb.StationController.index/2`, `#case-approve` (disabled when format errors exist) and `#case-disapprove` (visible when not disapproved) in `BackendWeb.AdminCaseLive.Show`, `#case-approval` and `#case-station-versions` display on case page, and `Aprovado por` column on `BackendWeb.AdminCaseLive.Index`.
  - RED: 9 failures. GREEN: 127/127 focused tests passed, `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` clean.
  - Slice scope against `origin/feat/326-production-launch`: single PR (`b3eb60f`, `439c069`).
- **L5** (2026-10-22, T3 completed):
  - Full backend suite (`MIX_TEST_PARTITION=_issue333 mix test`): 2048 passed, 0 failures.
  - `mix dialyzer`: 0 errors.
  - `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`: all clean.
- **L6** (2026-10-22, Jorge review fixes R1):
  - Jorge review run with `antigravity/gemini-3.8-flash`.
  - Addressed `DATA-001` (cleared approval fields on disapproval in `Case.disapprove_changeset/1` and guarded UI display with `status == :approved`).
  - Addressed `tx-resilience-02` (idempotent no-op for already-approved cases with unchanged markdown in `Content.approve_case/3`, added `phx-disable-with` to `#case-approve`).
  - RED observed: 4 test failures across `content_test.exs` and `admin_case_live_test.exs`.
  - GREEN: Commit `de908ab`. Full backend suite 2049/2049 passed, dialyzer 0 errors, credo strict 0 issues.
  - Pushed to `origin feat/333-approve-case-catalog` and posted resolution comment on PR #372.
- **L7** (2026-10-25, independent verification fixes R2):
  - Finding 1 (catalog identity): `Stations.to_catalog_station` exposed `"id" => version.station_id` (the `[ESTAÇÃO]` slug, which can repeat across cases) while `Content.list_published_stations/0` dedups on `c.number`. Now `"id"` is the case number (integer), `"version"` is `version_number`, and `"slug"` keeps the `[ESTAÇÃO]` id for display only; `list_published_stations/0` preloads `case`.
  - Finding 2 (docs): new section "Station catalog (`GET /stations`)" in `docs/unreal-station-client.md` (routes, public `:api` auth until #337, response shape and example, fields, ordering, latest approved version per case); `docs/case-format/README.md` links to it.
  - Finding 3 (naming): documented in the `StationVersion` moduledoc and the case-format README that `case_revision_id` references the revision holding the replaced Markdown; the approved text is `StationVersion.markdown`. No rename.
  - RED observed: 4 failures (`content_test.exs` x2, `station_controller_test.exs` x2) on the new id/slug/version assertions, including two approved cases sharing one slug. GREEN: commit `687cda3`.
  - Gates (`MIX_TEST_PARTITION=_fix372`): `mix format --check-formatted` clean, `mix compile --force --warnings-as-errors` clean, `mix credo --strict` no issues, `mix test` 2051 passed, `mix dialyzer` 0 errors.

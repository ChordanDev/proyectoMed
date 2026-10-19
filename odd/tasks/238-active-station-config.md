# 238 — Select the active station by configuration

Issue: #238 (parent #237). Branch `feat/238-active-station-config` from parent branch `feat/237-clinician-demo-readiness` (at develop 7bfb4cd). Worktree `../proyectoMed-238`. The child PR targets the parent branch with `Refs #238`; the parent keeps a Draft PR to `develop`.

## Objective

Choose the active station at boot through a runtime setting (for example `ACTIVE_STATION_ID`), so acute-appendicitis runs without a local code edit. The default stays `chest-pain-initial-assessment`.

## Why

`@active_station_id` in `backend/lib/backend/stations/station_loader.ex:12` is a compile-time attribute. The #215, #228 and #235 live checks each needed an uncommitted edit, and the clinician demo (#237) must not.

## Constraints

- An unknown id or an invalid package fails at boot with an error that names the id.
- Test fixtures and the qualification harness keep working.
- `Backend.Stations` stays the public interface. No speculative abstraction.

## Tasks

- [x] T1 Runtime setting read in `config/runtime.exs`, loader uses it, boot error for an unknown id, tests, README entry next to `JEV_ADAPTER` / `RUBRIC_RESOLVER`.
- [ ] T2 Manual check: boot with `ACTIVE_STATION_ID=acute-appendicitis` and `curl /api/stations/active`.

## Routing

- T1: delegated direct (one writer; config, loader, tests and README).
- T2: parent inline (bounded command).

## Checks

- `cd backend && mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test`
- Full local CI before the PR (mirrors `pr-validation.yml`).

## Progress

- Created 2026-10-19.
- T1 done in `6b9f79f` (route: delegated direct, one writer).
  - Setting: `ACTIVE_STATION_ID` (trimmed) in `config/runtime.exs`, `dev` and `prod` only, into `:active_station_id`; default `chest-pain-initial-assessment` in `config/config.exs`. `test` ignores the variable so the suite always starts from the default.
  - Loader resolves the id at boot, accepts only `[a-z0-9-]+`, and raises with the id named for a malformed id, an unknown id, or an invalid package (existing loader messages now include the quoted id).
  - Tests: `backend/test/backend/active_station_config_test.exs` (restarts the supervised loader and checks `Backend.Stations.get_active_station/0`; reads `runtime.exs` through `Config.Reader` for `:dev`, `:prod` and `:test`).
  - RED: new file 3/13 passed, 10 failed (no selection, no id validation). GREEN: 13/13 plus loader tests 20/20.
  - Checks: `mix format --check-formatted` ok; `mix compile --warnings-as-errors` ok; `mix credo --strict` no issues; `mix test` 1099 passed (twice).

## Next step

T2.

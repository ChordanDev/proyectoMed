# E2E approving Jev adapter

## Objective

Make the process-level E2E suite pass on `feat/125-jev-evaluation` after merging
`develop` (PR #112), so parent PR #142 can merge with `bash scripts/test.sh` green.

## Problem

`develop` brought the process-level E2E suite (`web/src/integration/`). On this
branch every non-template patient reply goes through `CandidateGate`, and the only
Jev adapter in the application is `DisabledAdapter`, which fails closed. The active
package has no approved templates, so every learner message returns 502 in a real
Phoenix process. ExUnit passes because it injects adapters in-process; the E2E
harness boots Phoenix in a separate process and cannot.

Observed on the merged tree (`a0add27`): 167 web unit and 825 ExUnit tests pass;
2 of 4 E2E tests fail (stale `version: "1.0.0"` expectation; 502 on `sendMessage`).

## Decision

User chose a deterministic approving Jev adapter for E2E only (2026-10-08), over
asserting fail-closed behavior, to keep the full learner-loop coverage required by
#31. Connecting a real provider stays under #183 and is out of scope.

## Constraints

- The adapter must not exist in `prod`: compiled only for `dev` and `test`, and the
  environment switch must be ignored when `config_env()` is `:prod`.
- Default adapter stays `DisabledAdapter`; fail-closed behavior is unchanged.
- `scripts/test.sh` keeps its three-phase contract (`tests/scripts/test_red.sh`).
- No real provider calls, no secrets, no transcript logging.

## Tasks

- [x] T1 (delegated writer; trigger: 2+ non-trivial files across backend and web)
  Add the E2E-only approving Jev adapter, its non-prod environment switch, wire
  the harness to enable it, and update E2E expectations to the v2 behavior.
  Document it in `README.md`.

## Acceptance criteria

- `bash scripts/test.sh` passes: web unit, ExUnit, and all 4 E2E tests.
- The adapter module is absent from a `prod` compile, or the limitation is reported.
- Typecheck, lint, `mix format --check-formatted`, `mix compile
  --warnings-as-errors`, `mix credo --strict`, and `tests/scripts/test_red.sh` pass.

## Progress

- Merge of `develop` committed as `a0add27`.
- T1 committed as `a9bd5c4` (route: delegated writer). Test-first evidence: RED
  was the E2E run on `a0add27` (2 of 4 failed: stale `1.0.0` expectation; 502 on
  `sendMessage`), confirmed before editing; GREEN below.

## Adapter behavior (T1)

`Backend.E2ESupport.ApprovingJevAdapter` reads no text and performs no I/O.
`decide_patient/1` verifies every candidate. `decide_rubric/1` and
`decide_rubric_batch/1` award a criterion its last authored class (the reserved
`uncertain` excluded) citing the first learner evidence item, with every authored
action `performed` on that citation; without learner evidence everything is
`uncertain` and nothing is cited. The caller still validates each citation.

## Verification evidence (T1, on `a9bd5c4`)

- `bash scripts/test.sh`: exit 0; web unit 167 passed, ExUnit 835 passed (825 +
  10 new adapter tests), E2E 4 of 4 passed.
- `npm --prefix web run typecheck`, `npm --prefix web run lint`: exit 0.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict` (no issues): exit 0.
- `bash tests/scripts/test_red.sh`: 4 passed, 0 failed.
- `MIX_ENV=prod mix compile` succeeded; no
  `Elixir.Backend.E2ESupport.ApprovingJevAdapter.beam` under `_build/prod`
  (present under `_build/dev` and `_build/test`). With the variable set, `prod`
  still resolves `DisabledAdapter`; `dev` resolves the approving adapter.

## Known limitation

`backend/.formatter.exs` and `backend/.credo.exs` do not include
`e2e_support/`, so the repository-wide format and Credo checks do not cover the
adapter file. Both pass when run on the file explicitly. Extending those globs
was outside the authorized edit surface of T1.

## Next step

None for T1. Decide whether to add `e2e_support/` to the formatter and Credo
inputs.

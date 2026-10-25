# #381 Deterministic case-number tests

Objective: make the case-number assertions in `content_test.exs` and `admin_case_live_test.exs` independent of async test interleaving.
Branch: `test/381-deterministic-case-numbers` (base `feat/326-production-launch`). Delivery: single PR. Runner: `mix test` (`MIX_TEST_PARTITION=_issue381`).

## Specs

- S1: "Make these tests deterministic: assert relative ordering or the number returned by the insert instead of absolute values, or run the few tests that need absolute numbers without `async`."
- S2: "The two files pass 20 consecutive full-suite runs with random seeds."
- S3: "No test asserts an absolute `cases.number` it did not read back from the insert."
- Constraint: tests-only change; `lib/` is not touched.

## Tasks

- [x] T1 (S1, S3) - replace the `number + 1` assertions with strictly increasing ordering in both files. Route: inline (small, ~13 lines). Commit: `3ed7186`. RED: base seeds 14, 17 (of 0-19) and 32, 33, 40, 54 (of 20-59) failed one test each. GREEN: seeds 0-59 all 61/61.
- [x] T2 (S2) - prove determinism: 20 seeded runs of the two files plus one full suite and local CI. Route: inline. Evidence: L4, L5.

## Log

- L1 (2026-10-25, issue #381): "`content_test.exs` and `admin_case_live_test.exs` assert sequential case numbers (`cases.number` is a Postgres identity column) while running `async: true`. The identity sequence is shared across concurrent sandboxed tests and is not rolled back, so the expected numbers depend on test interleaving and the suites fail intermittently."
- L2: analysis. Only two assertions derive an absolute number not read back from an insert: `second.number == first.number + 1` (content_test.exs:46) and `next == number + 1` (admin_case_live_test.exs:45). A concurrent test calling `nextval` between the two inserts makes both fail. Every other assertion uses the number returned by its own insert, and rows of other tests are invisible inside the sandbox, so list ordering and lookups (`number + 1000`, `/admin/cases/999999`) stay deterministic.
- L3: RED on base `dd6226d`: 20 runs (seeds 0-19) gave 2 failing runs; 40 more (seeds 20-59) gave 4, each one of the two targeted tests (`content_test.exs:46` left 4290 right 4289; `admin_case_live_test.exs:45` left 4893 right 4892).
- L4: GREEN after T1: 60 runs (seeds 0-59) of the two files all 61 passed; full suite `mix test` 2177 passed (`MIX_TEST_PARTITION=_issue381`). Commit `3ed7186`.
- L5: local CI (`local_ci.sh`, `MIX_TEST_PARTITION=_issue381`) on `3ed7186`: LOCAL CI PASSED. Web unit 337 passed (16 files), ExUnit 2177 passed, process E2E 4 passed, format, compile with warnings as errors, Credo strict and Dialyzer clean. GitHub Actions is blocked by billing. Next step: PR to `feat/326-production-launch`.

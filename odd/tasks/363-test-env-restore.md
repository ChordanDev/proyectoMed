# Test env restore (#363)

Objective: test `on_exit` restores of `:backend` application env delete a key that was unset instead of storing `nil`. Branch `test/363-test-env-restore` from `feat/326-production-launch`; single PR; runner `mix test` in `backend/` (`MIX_TEST_PARTITION=_issue363`). Tests only: no `lib/` changes.

## Why

`Application.get_env(:backend, key, default)` falls back to `default` only when the key is absent, not when it holds `nil`. Restores like `Application.put_env(:backend, key, previous)` with `previous = Application.get_env(:backend, key)` turn an unset key into an explicit `nil`, so `Backend.LLMProviderConfigTest` failed depending on test order (CI run 39782953920, PR #362).

## Specs

- S1: "After any test, a key that was absent before it is absent again."
- S2: "The failure is reproduced deterministically before the fix (leaking test, then `llm_provider_config_test.exs`)."
- S3: "Every restore listed above deletes the key when the previous value was `nil`." Extended by the task to every unsafe `Application.put_env(:backend, key, previous)` restore across `backend/test`, found with `rg`, not only the files the issue lists.
- S4: A small test-support helper restores app env by deleting the key when it was unset (`Application.delete_env`) and putting it back otherwise.
- S5: A probe proves that no `:backend` key ends the suite as an explicit `nil` it did not start as.
- S6: "`mix test` passes in `backend/`." and local CI prints `LOCAL CI PASSED`.
- Constraint: "No production code changes."

## Tasks

| ID | Specs | Route | Status | Commit |
|----|-------|-------|--------|--------|
| T1 | S4 | inline | done | 9841e6f (RED: 5 tests UndefinedFunctionError; GREEN: 5 passed) |
| T2 | S1-S5 | inline | done | this commit (RED/GREEN in L3-L5) |
| T3 | S6 | inline | pending | |

- T1: `Backend.AppEnvHelpers` in `test/support` (`snapshot/1`, `restore/2`, `leaked_nils/2`) with its unit test. T2 adds `snapshot/2`/`restore/3` for another application (`:swoosh`).
- T2: after-suite guard in `test/test_helper.exs` that fails the run when a key ends as an explicit `nil` it did not start as; migrate every unsafe restore to the helper.
- T3: full suite, repeated randomized seeds, local CI.

Route evidence: one understood change in test code only, no writer trigger (no parallel units, no context backstop); parent works inline.

## Log

- L1 (2026-10-25, user request relayed by the workflow): "sí, sigue en pie" — implement issue #363 as a tests-only change.
- L2: Deterministic reproduction (S2): a `mix run` script requiring `station_controller_test.exs`, running it, then requiring `llm_provider_config_test.exs` and running it. `:station_ai_adapter` reads `:error` before, `{:ok, nil}` after the leaking module, and the LLM test fails with `left: nil` (17 tests, 1 failure). `mix test` with both files always ran `LLMProviderConfigTest` first, so file order alone could not reproduce it.
- L3: Unsafe restores found with `rg` (a `get_env/2` snapshot put back with `put_env/3` and no nil branch): `station_controller_test.exs` (`:voice_mode`, `:station_ai_adapter`), `stations_test.exs` (`:jev_decision_default_deadline_ms` x2), `client_ip_test.exs` (`ClientIP`), `support/rate_limit_helpers.ex` (`BackendWeb.RateLimit`), `registration_mail_failure_test.exs` (`Backend.Accounts.Mailer`), `usage_prices_test.exs` (`Prices`), `mailer_config_test.exs` (`:swoosh, :api_client`). Restores already nil-safe (local `restore_env(key, nil) -> delete_env` helpers, `if is_nil` branches, `fetch_env`/`fetch_env!` snapshots) were left as they are.
- L4: RED for the guard: `mix test station_controller_test.exs:835` (addressee describe alone) exits 1 with "tests left these :backend app env keys as an explicit nil: [:station_ai_adapter]". The full suite passed the end-of-suite guard before the fix because a later restore deleted the key, so a scratch per-test formatter probe (outside the repo) recorded, for seeds 1-3 with `--max-cases 1`, `:station_ai_adapter` first leaked by the addressee describe.
- L5: GREEN: addressee describe alone exits 0; the `mix run` reproduction reads `:error` after the leaking module and the LLM test passes (17 tests, 0 failures); per-test probe seeds 1-3 record no leaked key (`%{}`); three randomized full runs (seeds 779362, 854903, 965242) give 2348 passed, exit 0; each of the 134 test files run alone fires no guard.

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
| T1 | S4 | inline | pending | |
| T2 | S1-S3, S5 | inline | pending | |
| T3 | S6 | inline | pending | |

- T1: `Backend.AppEnvHelpers` in `test/support` (`snapshot/1`, `restore/2`, `leaked_nils/1`) with its unit test.
- T2: after-suite guard in `test/test_helper.exs` that fails the run when a key ends as an explicit `nil` it did not start as; migrate every unsafe restore to the helper.
- T3: full suite, repeated randomized seeds, local CI.

Route evidence: one understood change in test code only, no writer trigger (no parallel units, no context backstop); parent works inline.

## Log

- L1 (2026-10-25, user request relayed by the workflow): "sí, sigue en pie" — implement issue #363 as a tests-only change.
- L2: Deterministic reproduction (S2): a `mix run` script requiring `station_controller_test.exs`, running it, then requiring `llm_provider_config_test.exs` and running it. `:station_ai_adapter` reads `:error` before, `{:ok, nil}` after the leaking module, and the LLM test fails with `left: nil` (17 tests, 1 failure). `mix test` with both files always ran `LLMProviderConfigTest` first, so file order alone could not reproduce it.

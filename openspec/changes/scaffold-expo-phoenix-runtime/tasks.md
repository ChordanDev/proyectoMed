# Tasks: Scaffold Expo Phoenix Runtime

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | 1,000–1,500 (generated scaffold included) |
| Review budget | 800 lines |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3 → PR 4 |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Safety scripts and RED harness | PR 1 | `bash tests/scripts/scaffold_red.sh` | Fake generator/Git scenarios | `scripts/`, `tests/scripts/` |
| 2 | Expo runtime and smoke test | PR 2 | `npm --prefix mobile test` | `npm --prefix mobile start` / Expo Go | `mobile/` |
| 3 | Phoenix JSON runtime and smoke test | PR 3 | `mix --cd backend test` | `mix --cd backend phx.server`; `GET /` | `backend/` |
| 4 | Root wiring, guidance, verification | PR 4 | `scripts/test.sh` | Root test and documented manual checks | `README.md`, `.gitignore`, `openspec/config.yaml` |

## Phase 1: Safety Harness

- [x] 1.1 RED: create `tests/scripts/scaffold_red.sh`: `git -C` returning another repo fails; relative and absolute script invocations resolve the same expected root.
- [x] 1.2 RED: add fake-command cases in `tests/scripts/scaffold_red.sh` for no preflight mutation, target/version refusal, failure propagation, next-generator suppression, partial preservation, and retry refusal.
- [x] 1.3 RED: create `tests/scripts/test_red.sh` proving `scripts/test.sh` runs mobile before backend and returns the first non-zero fake-suite status.

## Phase 2: Deterministic Scaffold and Runtimes

- [x] 2.1 Create executable `scripts/scaffold.sh`; normalize Git/script roots, preflight absent targets and pinned tools, run Expo then Phoenix only, and preserve partial outputs on failure.
- [x] 2.2 Generate `mobile/` only through `scripts/scaffold.sh`; retain the blank TypeScript Expo app, lockfile, no `ios/` or `android/`, and commit `mobile/__tests__/App.smoke.test.tsx`.
- [x] 2.3 Update `mobile/package.json` with exact Node `26.5.0`, npm `11.17.0`, Expo `~57.0.18`, and Jest/RNTL test wiring.
- [x] 2.4 Generate API-only `backend/`; add `HealthController`, JSON `GET /`, `health_controller_test.exs`, `.tool-versions`, compatible Elixir, Phoenix `~> 1.8.13`, and its lockfile without excluded layers.

## Phase 3: Root Test Integration

- [x] 3.1 Create executable `scripts/test.sh` with cwd-independent root resolution, fixed mobile Jest then Phoenix ExUnit commands, and first-failure propagation.
- [x] 3.2 Make `tests/scripts/scaffold_red.sh` and `tests/scripts/test_red.sh` pass without network access or real generators.
- [x] 3.3 Run isolated mobile and backend smoke suites; verify backend root returns JSON 200 and excluded Ecto/HTML/LiveView/EEx dependencies remain absent.

## Phase 4: Guidance and Verification

- [x] 4.1 Update `.gitignore`, `README.md`, and `openspec/config.yaml` for caches/build artifacts, pinned setup/run/test commands, CocoaPods limitation, available harnesses, and `strict_tdd: false`.
- [x] 4.2 Run `scripts/test.sh`; manual Expo Go startup deferred to a follow-up lane because device + Wi-Fi access is unavailable in the current environment, while live `GET /` was confirmed (HTTP 200 JSON). Unavailable checks are recorded here rather than masked as `#12` behavior.

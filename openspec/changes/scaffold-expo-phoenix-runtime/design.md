# Design: Scaffold Expo Phoenix Runtime

## Technical Approach

Future apply work generates pinned Expo and Phoenix projects, then adds only the specified API placeholder, smoke tests, and test harness. Generators run only through `scripts/scaffold.sh`, which completes repository, target, command, and version preflight before invoking:

```sh
CI=1 npx --yes create-expo-app@4.0.0 "$root/mobile" --template expo-template-blank-typescript@57.0.20 --no-install --no-agents-md --yes
mix phx.new "$root/backend" --app backend --module Backend --no-html --no-ecto --no-assets --no-gettext --no-mailer --no-dashboard --no-install --no-agents-md --no-version-check
```

This design correction generates no code or dependencies.

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Published pinned TypeScript template | Generated bulk, but reproducible | Use published `expo-template-blank-typescript@57.0.20`; the JavaScript `expo-template-blank` package cannot satisfy the TypeScript requirement. |
| Dedicated scaffold boundary | Adds a script and RED suite | Put preflight, root authority, generator order, and partial-output policy in `scripts/scaffold.sh` so safety is testable. |
| POSIX test orchestrator | Sequential, not parallel | Keep cwd-independent `scripts/test.sh` to preserve the first failure without a monorepo manager. |
| Minimal JSON controller | One handwritten backend seam | Add `GET /` returning `{"status":"ok"}` because API-only Phoenix generates no root route. |
| Managed Expo only | No local native iOS build | Never create or commit `mobile/ios/` or `mobile/android/`, preserving Expo Go scope. |

## Data Flow

`caller` → `scripts/scaffold.sh` → normalize/verify root → preflight → Expo → Phoenix. Failure stops the chain. Tests use `scripts/test.sh` → Jest → ExUnit. Runtime uses `GET /` → API pipeline → `HealthController.index/2` → JSON 200.

## File Changes

| File | Action | Description |
|---|---|---|
| `mobile/**` | Create | Generated blank TypeScript app; lockfile and Jest/RNTL wiring. |
| `mobile/package.json` | Modify | Declare exact Node 26.5.0 and npm 11.17.0 engines, Expo `~57.0.18`, and test scripts. |
| `mobile/__tests__/App.smoke.test.tsx` | Create | The single mobile baseline smoke test. |
| `backend/**` | Create | Generated API-only Phoenix application and lockfile. |
| `backend/.tool-versions` | Create | Declare Erlang 29.0.5 and Elixir 1.20.2-otp-29 for reproducible installation. |
| `backend/mix.exs` | Modify | Declare compatible Elixir and Phoenix `~> 1.8.13`; retain all persistence/UI exclusions. |
| `backend/lib/backend_web/{router.ex,controllers/health_controller.ex}` | Modify/Create | JSON root endpoint only. |
| `backend/test/backend_web/controllers/health_controller_test.exs` | Create | The single backend baseline smoke test. |
| `scripts/scaffold.sh` | Create | Sole generator orchestration and safety boundary. |
| `scripts/test.sh` | Create | Executable, fixed-command root test entry point. |
| `tests/scripts/scaffold_red.sh` | Create | RED acceptance tests for preflight, root authority, generator failures, and partial output. |
| `.gitignore`, `README.md` | Modify/Create | Ignore generated state; document setup, run, test, and limitations. |
| `openspec/config.yaml` | Modify | Expose the harness without enabling strict TDD. |

## Interfaces / Contracts

`scripts/scaffold.sh` accepts no arguments. It normalizes its `scripts/` parent and Git's `git -C <expected-root> rev-parse --show-toplevel` result with the same `cd` plus `pwd -P` operation, requires equality, and derives only `$root/mobile` and `$root/backend`. This is a testable normalization guarantee, not universal path canonicality.

Before mutation it verifies absent targets and pinned tool/generator versions. Generator failure propagates status, identifies and preserves created targets, and skips the next generator. Retries refuse existing targets rather than overwrite or resume.

`scripts/test.sh` accepts no arguments, resolves its root from its own location, runs `npm --prefix "$root/mobile" test`, then `mix --cd "$root/backend" test`, and propagates the first failure.

`mobile/package.json` declares exact `engines.node` `26.5.0` and `engines.npm` `11.17.0`, with Expo `~57.0.18`; generation uses `expo-template-blank-typescript@57.0.20`. `backend/.tool-versions` declares `erlang 29.0.5` and `elixir 1.20.2-otp-29`; `backend/mix.exs` declares the compatible Elixir requirement and Phoenix `~> 1.8.13`. Commit both lockfiles. README, ignores, and config retain proposal scope and `strict_tdd: false`.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit | `App` render | RNTL/Jest smoke. |
| Integration | JSON root and exclusions | ConnCase plus dependency/native-directory assertions. |
| Scaffold harness | preflight, root, order, partial output | `tests/scripts/scaffold_red.sh` uses fakes to assert no preflight mutation, next-command suppression, status propagation, partial preservation, and retry refusal. |
| Test harness | mobile/backend pass and failure | Fake-command shell acceptance tests verify order and exact exit propagation. |
| E2E | Native/device and HTTP process | Not available; Expo Go start and live server remain documented manual checks. |

## Threat Matrix

| Boundary | Applicability | Safe/failure behavior | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A: no executable-file discovery or dynamic-path classification mechanism is implemented. | — | — |
| Git repository selection | Applicable | Only the normalized `scripts/` parent matching normalized Git output is authoritative; mismatch or lookup failure exits before generators. | `tests/scripts/scaffold_red.sh`: `git -C` returning another repo fails; relative and absolute script invocations resolve the same expected root. |
| Commit state | N/A: no commit/index automation. | — | — |
| Push state | N/A: no push/ref resolution. | — | — |
| PR commands | N/A: no PR command composition. | — | — |

## Migration / Rollout

No migration required. Future apply work is one reversible scaffold change. No persistence, deployment, clinical/#12 behavior, HTML/LiveView/EEx, authentication, voice-provider work, strict-TDD enablement, or GitHub mutation is included.

## Open Questions

None.

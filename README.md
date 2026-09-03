# proyectoMed

Planning and specification repository for a Revalida clinical-practice MVP.
The application is an Expo React Native mobile client (`mobile/`) talking to a
JSON-only Phoenix API (`backend/`). Issue source-of-truth lives on the
[GitHub issue tracker](https://github.com/ChordanDev/proyectoMed/issues); see
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md) for how agents
and humans interact with it.

This repository currently hosts the **runtime scaffold** for the planned stack.
The scaffold is intentionally minimal: one pinned Expo blank-TypeScript app
under Expo Go, one JSON-only Phoenix API without Ecto or HTML tooling, a
deterministic root test orchestrator, and baseline smoke coverage per runtime.
It adds no clinical, product, or `#12` behavior.

---

## Toolchain (pinned)

| Tool       | Version          | Source                                      |
| ---------- | ---------------- | ------------------------------------------- |
| Node       | `26.5.0`         | `mobile/package.json` `engines.node`        |
| npm        | `11.17.0`        | `mobile/package.json` `engines.npm`         |
| Expo SDK   | `~57.0.18`       | `mobile/package.json` `dependencies.expo`   |
| Elixir     | `1.20.2-otp-29`  | `backend/.tool-versions`                    |
| OTP        | `29.0.5`         | `backend/.tool-versions`                    |
| Phoenix    | `~> 1.8.13`      | `backend/mix.exs`                           |

The scaffold was generated with pinned community templates:

- `npx create-expo-app@4.0.0 mobile --template expo-template-blank-typescript@57.0.20`
- `mix phx.new backend --app backend --module Backend --no-html --no-ecto --no-assets --no-gettext --no-mailer --no-dashboard --no-install --no-agents-md --no-version-check`

Both generators are wrapped by [`scripts/scaffold.sh`](scripts/scaffold.sh) so
the preflight, ordering, version pin, and partial-output policy are testable
and reproducible. Re-running the script requires `mobile/` and `backend/` to
be absent (no overwrite, no resume).

---

## Install

```sh
# Mobile (Expo / React Native).
npm --prefix mobile install

# Backend (Phoenix / Elixir).
( cd backend && mix deps.get )
```

The repository commits both lockfiles (`mobile/package-lock.json` and
`backend/mix.lock`) so a fresh clone builds deterministically.

---

## Run

```sh
# Mobile — boots Metro under Expo Go (no native compilation).
npm --prefix mobile start

# Backend — boots the JSON API on http://localhost:4000.
( cd backend && mix phx.server )
```

The backend exposes exactly one HTTP route:

```sh
$ curl -i http://localhost:4000/
HTTP/1.1 200 OK
content-type: application/json; charset=utf-8

{"status":"ok"}
```

---

## Test

The root entry point runs mobile Jest and Phoenix ExUnit in sequence and
propagates the first non-zero exit from either suite:

```sh
bash scripts/test.sh
```

Equivalent per-runtime commands:

```sh
# Mobile (Jest + React Native Testing Library).
npm --prefix mobile test

# Backend (ExUnit).
( cd backend && mix test )
```

A baseline smoke test lives in each runtime:

- `mobile/__tests__/App.smoke.test.tsx` — asserts the blank Expo root
  component renders the template welcome text.
- `backend/test/backend_web/controllers/health_controller_test.exs` —
  asserts `GET /` returns HTTP 200 and `{"status":"ok"}`.

These smoke tests prove the harness runs; they do **not** implement any
clinical or `#12` behavior.

---

## Pull-request CI

Every pull request runs the `Pull Request Validation` GitHub Actions workflow.
It installs the mobile dependencies with `npm ci`, fetches the Phoenix
dependencies with `mix deps.get`, and then runs the single root command:

```sh
bash scripts/test.sh
```

The workflow reads its Node version from `mobile/package.json` and its Erlang
and Elixir versions from `backend/.tool-versions`.

---

## Available harnesses

| Script                                       | Purpose                                                                                  |
| -------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `scripts/scaffold.sh`                        | Sole generator boundary — preflight, git-root authority, Expo then Phoenix, partial preservation. |
| `scripts/test.sh`                            | Root test orchestrator — `npm --prefix mobile test` then `( cd backend && mix test )`.    |
| `tests/scripts/scaffold_red.sh`              | RED/GREEN acceptance tests for `scripts/scaffold.sh` (16 invariants).                   |
| `tests/scripts/test_red.sh`                  | RED/GREEN acceptance tests for `scripts/test.sh` (ordering + exit-code propagation).     |

Both RED harnesses use bash fake-command stubs over `PATH`, so they are
hermetic: no network access, no real npm/npx/mix, no Expo or Phoenix generators.

```sh
# All RED harnesses from a clean state.
bash tests/scripts/scaffold_red.sh
bash tests/scripts/test_red.sh
```

---

## Limitations

### iOS native build

CocoaPods (`pod`) is **not** installed on the baseline host. As a result
no local `mobile/ios/` or `mobile/android/` native project is generated or
committed; the scaffold runs only under Expo Go (managed workflow).

If a future change needs a native module that requires CocoaPods, install
CocoaPods (`sudo gem install cocoapods` or Homebrew `brew install cocoapods`),
re-run `npx expo prebuild --platform ios`, and add the generated `ios/` and
`android/` directories to version control via a follow-up SDD change.

### Other known limitations

- **No persistence layer.** `--no-ecto` was chosen so the database adapter
  is a deliberate downstream decision (see `#13` evaluation). `GET /` is the
  only route.
- **No view layer.** `--no-html --no-assets --no-gettext --no-mailer --no-dashboard`
  remove HTML, EEx, LiveView, Tailwind, asset pipeline, gettext, mailer, and
  dashboard generators. Only JSON responses are served.
- **No strict TDD.** `openspec/config.yaml` keeps `strict_tdd: false`. The
  harness is available (`scripts/test.sh`, RED harnesses), but test-first
  discipline is left to the change that implements the first real capability.
- **Toolchain drift.** Pinned versions in `mobile/package.json` and
  `backend/.tool-versions` are the only supported way to reproduce the
  scaffold. Drift between the host toolchain and these pins is the most
  likely source of regressions.

---

## Repository layout

```
.
├── AGENTS.md                    Agent conventions (issue tracker, triage labels).
├── docs/
│   ├── PRD.md                   Product requirements (clinical-practice MVP).
│   └── agents/                  Agent reference docs.
├── mobile/                      Generated Expo TypeScript app (PR 2).
├── backend/                     Generated Phoenix API (PR 3).
├── scripts/
│   ├── scaffold.sh              Sole generator orchestrator (PR 2).
│   └── test.sh                  Root test orchestrator (PR 3).
├── tests/scripts/               RED harnesses for both scripts (PR 1).
└── openspec/
    ├── config.yaml              SDD harness config; `strict_tdd: false`.
    ├── specs/                   Archived capability specs.
    └── changes/                 Active change folders (proposal → archive).
```

---

## See also

- [`openspec/changes/scaffold-expo-phoenix-runtime/`](openspec/changes/scaffold-expo-phoenix-runtime/) —
  the proposal, design, and tasks for the runtime scaffold.
- [`docs/agents/domain.md`](docs/agents/domain.md) — domain vocabulary.
- [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md) — canonical
  five-label triage vocabulary used on GitHub Issues.

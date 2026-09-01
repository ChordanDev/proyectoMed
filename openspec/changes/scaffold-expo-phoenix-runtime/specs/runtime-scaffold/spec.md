# runtime-scaffold Specification

## Purpose

Provides a reproducible Expo React Native and JSON-only Phoenix runtime with a deterministic root test command, baseline smoke coverage, pinned toolchain versions, and developer setup guidance. Adds no clinical, product, or #12 behavior.

## Requirements

### Requirement: Reproducible Mobile Runtime

The system MUST provide `mobile/` as a blank TypeScript Expo app (`create-expo-app --template blank-typescript`) that boots in Expo Go without native compilation, and MUST NOT commit native iOS or Android project directories.

#### Scenario: Mobile boots under Expo Go

- GIVEN a fresh clone with documented Node/npm installed
- WHEN `npm --prefix mobile start` runs from repo root
- THEN Metro starts and reports a dev URL

#### Scenario: No native project directories committed

- GIVEN the scaffold has been applied
- WHEN the repository is inspected
- THEN `mobile/ios/` and `mobile/android/` MUST NOT be committed directories

### Requirement: Reproducible Backend Runtime

The system MUST provide `backend/` as a Phoenix API (`mix phx.new --no-html --no-ecto` and related UI/asset exclusions) that serves JSON at the generated `GET /` placeholder, and MUST NOT introduce Ecto, HTML, LiveView, or EEx layers.

#### Scenario: Backend returns 200 JSON on root

- GIVEN a fresh clone with documented Elixir/OTP installed
- WHEN `GET /` is requested against `mix --cd backend phx.server`
- THEN the status is 200 and body is JSON

#### Scenario: Backend excludes persistence and view tooling

- GIVEN the scaffold has been applied
- WHEN `backend/mix.exs` is inspected
- THEN no `ecto`, `ecto_sql`, `phoenix_html`, `gettext`, or `swoosh` dependency is present

### Requirement: Root Test Orchestration

The system MUST provide `scripts/test.sh` as the root test entry point that runs mobile Jest and Phoenix ExUnit in sequence and propagates the first non-zero exit from either suite.

#### Scenario: Root script passes when both suites pass

- GIVEN both runtimes pass their smoke tests
- WHEN `scripts/test.sh` is invoked from repo root
- THEN the script exits 0

#### Scenario: Root script fails when any suite fails

- GIVEN a mobile Jest assertion is forced to fail
- WHEN `scripts/test.sh` is invoked
- THEN the script exits non-zero

### Requirement: Baseline Smoke Coverage Per Runtime

The system MUST include exactly one passing baseline smoke test per runtime: mobile asserts the root component renders, backend asserts `GET /` returns 200.

#### Scenario: Mobile smoke passes in isolation

- GIVEN `mobile/` is generated and dependencies installed
- WHEN `npm --prefix mobile test` runs
- THEN the smoke suite passes

#### Scenario: Backend smoke passes in isolation

- GIVEN `backend/` is generated and dependencies installed
- WHEN `mix --cd backend test` runs
- THEN the smoke suite passes

### Requirement: Pinned Toolchain Constraints

The system MUST record Node, npm, Expo SDK, Elixir, OTP, and Phoenix version constraints within `mobile/` and `backend/`, sufficient to install a matching toolchain from these files alone.

#### Scenario: Mobile declares Node and npm engines

- GIVEN the scaffold has been applied
- WHEN `mobile/package.json` is read
- THEN an `engines` field declares the minimum Node and npm versions

#### Scenario: Backend declares Elixir and OTP versions

- GIVEN the scaffold has been applied
- WHEN `backend/.tool-versions` (or equivalent) is read
- THEN the file declares the Elixir and OTP versions used

### Requirement: Developer Setup And Limitation Guidance

The system MUST provide a root `README.md` documenting toolchain install, per-runtime run, the root test command, and the CocoaPods limitation blocking local native iOS builds. The `.gitignore` MUST exclude `node_modules/`, `_build/`, `deps/`, generated assets, `.beam` files, Elixir LS, and Expo caches.

#### Scenario: README documents setup, run, and test

- GIVEN a developer reads the root README
- WHEN they follow the steps
- THEN they can install toolchains, start runtimes, and run the test command

#### Scenario: iOS native limitation is documented

- GIVEN a developer reads the limitations
- WHEN they assess iOS builds
- THEN a note states CocoaPods is required and missing in the baseline

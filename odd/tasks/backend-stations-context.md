# Feature: Migrate Station domain operations behind Backend.Stations

Tracking task for GitHub Issue #135 (Ticket 15).
Parent: #22 (tracking specification; branch and PR directly to `develop`).
Target branch: `develop`
Feature branch: `feat/135-backend-stations-context`

## Tasks

- [x] Task 1: Move internal modules to `backend/lib/backend/stations/` and update internal namespaces
- [x] Task 2: Implement public `Backend.Stations` context module with domain operations and extension points
- [x] Task 3: Refactor `BackendWeb` controllers to delegate strictly to `Backend.Stations`
- [x] Task 4: Migrate existing tests and add comprehensive `Backend.StationsTest` suite
- [x] Task 5: Add architecture tests preventing direct web-to-internal calls
- [x] Task 6: Run full verification suite (`scripts/test.sh`, credo, format, compile) and prepare PR
- [x] Task 7: Clarify and test `append_patient_reply/2` finish race behavior (TR-02 pre-existing/intended)
- [x] Task 8: Fix `OpenAIAdapter.get_config/1` environment keyword merge (sec-perf-001)
- [x] Task 9: Implement learner message rollback on AI failure (TR-01)
- [x] Task 10: Run full test suite, format/lint, and document Jorge review resolution

## Acceptance Criteria

- `Backend.Stations` is the only public domain entry point used by Station controllers and external-integration delivery surfaces.
- Existing Station Package loading, session, message, finish, result, transcription, and synthesis behavior remains externally compatible during the migration.
- Conversation, package loading, Station AI, evaluation, and provider-specific implementation details are internal to `Backend.Stations` or real external adapter seams.
- `BackendWeb` does not call `Backend.Conversation`, `Backend.StationLoader`, `Backend.StationAI`, `Backend.Evaluator`, `Backend.Transcription`, or `Backend.TTS` directly.
- The migration defines stable extension points required by Impressos, real-time voice, Jev verification, timer, and discard work without implementing those separate capabilities.
- Existing tests are migrated with behavior preserved; architecture tests prevent new direct web-to-internal calls.
- No parallel context, umbrella application, speculative internal behaviours, or full hexagonal layer is introduced.
- `bash scripts/test.sh` exits 0.

## Evidence

- Commits:
  - `0d593de` — refactor(backend): move station domain implementation modules under Backend.Stations (Refs #135)
  - `19b46d5` — feat(stations): implement public Backend.Stations context interface (Refs #135)
  - `7b4f13d` — refactor(backend_web): delegate station domain operations strictly to Backend.Stations (Refs #135)
  - `b419702` — test(backend_web): migrate controller tests to use Backend.Stations (Refs #135)
  - `52f9757` — test(backend): add architecture boundary tests forbidding web-to-internal calls (Refs #135)
  - `8844b73` — fix(stations): resolve review findings for retry rollback and config merge (Refs #135)
- Tests:
  - Web: 23 passed (`npm --prefix web test`)
  - Backend: 187 passed (`mix test`)
  - End-to-end: 210 passed total (`bash scripts/test.sh`)
  - Web Typecheck: clean (`npm --prefix web run typecheck`)
  - Web Lint: clean (`npm --prefix web run lint`)
  - Backend Format: clean (`mix format --check-formatted`)
  - Backend Compile: clean (`mix compile --warnings-as-errors`)
  - Backend Credo: clean (`mix credo --strict`)
  - Backend Dialyzer: 0 errors (`mix dialyzer --format short`)

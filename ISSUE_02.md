## Parent

Part of #22

## What to build

A versioned Station Package file format and a `Backend.StationLoader` that loads the active station at boot. The package is authored outside the repo by the Content Partner as a single JSON file. The loader validates the shape and crashes loudly if anything is wrong, so a malformed package can never silently break a station.

## Acceptance criteria

- [ ] `priv/stations/<station_id>/package.json` is the canonical location for the active station. Only one station is loaded.
- [ ] The package schema enforces: `station_id`, `version`, `language` (`pt-BR`), `display_title`, `patient_profile`, `revealable_facts` (list), `response_rules` (list), `expected_actions` (list), `rubric` (list of criteria with `id`, `description`, `evidence_questions`, `practice_recommendation`).
- [ ] `Backend.StationLoader.load_active/0` returns the parsed package on success and raises with a clear pt-BR log line on any validation error.
- [ ] The application supervisor calls `Backend.StationLoader.load_active/0` at boot and the Phoenix endpoint `GET /api/stations/active` returns the package metadata.
- [ ] ExUnit coverage for `Backend.StationLoaderTest` covers happy path, missing file, malformed JSON, missing required field, wrong language.
- [ ] `bash scripts/test.sh` exits 0.

## Blocked by

- #23 (Restore Expo runtime in this checkout)

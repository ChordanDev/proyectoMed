# 338 Results history

Objective: persist one Educational Result per graded session of a learner and expose it as `GET /me/results` and `GET /me/results/:id` (#338, parent #326, ADR-014 #346, ADR-013 amendment on #209).
Branch: `feat/338-results-history` from `feat/326-production-launch`. Delivery: single PR to the parent branch. Runner: `mix test` (backend, `MIX_TEST_PARTITION=_issue338`), local CI script.

## Specs

- S1 "Each finished session stores its Educational Result (station version, date, status per criterion, points, recommendations, cited learner phrases, total null when unresolved; no audio, no full transcript)." Stored when the result is first graded (hook after the #301 grade-once path), only for sessions with a learner (`:user_id`).
- S2 "A technical failure stores nothing."
- S3 "GET /me/results lists them by date with an area filter" (bearer token, date descending, paginated).
- S4 "GET /me/results/:id shows one." "The detail matches the result shown at the end of the session."
- S5 "A finished session appears in the learner's history; another learner cannot see it" (another learner's result is 404).
- S6 "There is no cross-session total or readiness signal."
- S7 "Deleting the account deletes the history" (FK `on_delete: :delete_all`).
- S8 Document both endpoints with JSON examples in `docs/unreal-station-client.md`.

Constraints: keep the `stations.ex` change to a small hook (siblings #339, #342 edit it); the rest in new modules under `Backend.Stations.Results`. BackendWeb calls only `Backend.Stations`.

## Tasks

- [x] T1 (S1, S2, S6, S7) inline: migration `educational_results`, schema and `Results.History.record/2`, hook in `Stations.get_educational_result/2`, context tests. RED 5/5 failing (StoredResult undefined), GREEN 5/5; backend suite 2182 passed. Commit: see L3.
- [ ] T2 (S3, S4, S5, S6, S8) inline: `MeResultController`, routes under the device-auth pipeline, controller tests, docs. Commit: see Log.

Route evidence: both units are one dependent behaviour of about 300-400 lines; no Writer trigger reason, so inline.

## Log

- L1 (2026-10-25) Request: implement GitHub issue #338 "Store results and expose the learner's history" as a bounded writer (task text from the workflow: persist one Educational Result per finished session; GET /me/results list by date desc, optional area filter, paginated; GET /me/results/:id identical to the end-of-session result; another learner's result 404; no cross-session aggregate; technical failure stores nothing; account deletion cascades; document both endpoints).
- L2 Decisions: the stored `result` is the exact serialized v2 Educational Result the learner saw first (insert once, `ON CONFLICT (session_id) DO NOTHING`), so the detail's `result` equals the end-of-session body. The station identity (case number, version number, slug, area, theme, display title) is denormalized on the row; `station_version_id` is nilified if the case is deleted, so history survives content deletion. Legacy sessions without a learner store nothing.

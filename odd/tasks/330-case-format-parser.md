# 330 — Tagged case format and parser

Issue: #330 (parent spec #326). Branch: `feat/330-case-format-parser` → PR base `feat/326-production-launch`.

## Objective

Define a tagged Markdown case format, rewrite the acute-appendicitis case in it as the reference example, and build a deterministic parser that turns a case into a Station Package or a list of located errors.

## Why

Cases will come from an n8n pipeline as Markdown and be reviewed by doctors (#326). The backend must load them without a developer, and the format errors must be shown to the reviewer with a line number.

## Constraints

- Parser is pure and deterministic: no LLM, no database, no file access.
- Lives behind the public `Backend.Stations` context (`Backend.Stations.CaseFormat` is internal).
- The reference case keeps the clinical content of the hand-tuned package identical.
- The parsed package must pass `StationPackage.validate/1`; format-only data (area, theme, actors, PEP links) is additive and ignored by current consumers.
- The format supports a companion actor (#326 user stories 24-25).

## Checklist

- [x] T1 — Format spec, reference case and parser core: the reference case parses into a valid Station Package equal to the hand-tuned package on every hand-tuned field.
- [x] T2 — Validation rules with located errors: unknown link, duplicate id, missing tag, points not multiples of 0.025, total not 10.0, missing actor, bad thresholds.
- [x] T3 — Companion actor: a two-actor fixture parses with actors, facts and mandatory questions owned by each actor.
- [x] T4 — Grade equivalence on stored transcripts (#228 and #243 regression fixtures): parsed and hand-tuned packages yield the same criterion statuses and points.

## Routing

All tasks: delegated direct (this worker is the single bounded writer for the issue).

## Acceptance criteria

- The format spec documents every tag with an example.
- The reference acute-appendicitis case parses into a valid Station Package.
- Each validation rule has a failing example with a located error.
- On stored transcripts, the reference package yields the same criterion statuses and points as the hand-tuned package.

## Checks

- Focused: `mix test test/backend/stations/case_format*`.
- Full: local CI script (format, credo/compile warnings, backend and web tests).

## Progress

- T1 (commit b764042): RED observed — 4/4 tests failed with `Backend.Stations.parse_case/1 is undefined`; GREEN — 4/4 pass. Reference case equals the hand-tuned package on every field; credo strict clean on the new modules.
- T2 (commit 3d4dfde): 31 validation tests, one failing example per rule with its located error. RED was not observable as test-first: the rule checks were written with the parser core in T1. Instead a mutation probe disabled the unknown-actor and total rules: 3/31 failed, restored: 31/31 pass.

- T3 (commit 398edaf): companion fixture `backend/test/backend/stations/fixtures/case_format/companion.md` and 5 tests. RED not observed: actor support was built with the parser core in T1, so the tests passed on first run (5/5).

- T4 (this commit): 5 equivalence tests (#228 transcript; #243 transcript under 4 recorded scenarios) compare criteria and estimates of the parsed and hand-tuned packages; all equal, no difference to explain. RED not observable test-first (the parsed package was already equal); mutation probe: pointing item-06 criterio-1 at the glicemia impresso made 4/5 fail on item-06, restored 5/5 pass. A probe raising item-06's top `mínimo` changed no grade on these transcripts, so transcript equivalence alone does not cover every field; the T1 field-by-field equality does.

- Review round 1 (Jorge C1, deduped TR-1; inline route, one-file fix): invalid UTF-8 made `Tags.scan/1` raise `ArgumentError` from the Unicode regexes. `CaseFormat.parse/1` now checks `String.valid?/1` first and returns `{:error, [%{line: n, message: "case is not valid UTF-8"}]}` located at the first invalid line. RED — 2 new encoding tests failed with `ArgumentError`; GREEN — case_format tests 47/47.

## Next step

Local CI, push, PR to `feat/326-production-launch`.

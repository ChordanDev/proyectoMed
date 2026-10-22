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

- [ ] T1 — Format spec, reference case and parser core: the reference case parses into a valid Station Package equal to the hand-tuned package on every hand-tuned field.
- [ ] T2 — Validation rules with located errors: unknown link, duplicate id, missing tag, points not multiples of 0.025, total not 10.0, missing actor, bad thresholds.
- [ ] T3 — Companion actor: a two-actor fixture parses with actors, facts and mandatory questions owned by each actor.
- [ ] T4 — Grade equivalence on stored transcripts (#228 and #243 regression fixtures): parsed and hand-tuned packages yield the same criterion statuses and points.

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

(updated per task)

## Next step

T1.

# #273 Regenerate with targeted guidance when Jev cannot decide whether an unasked fact was stated

Parent: #237. Branch: `fix/273-undecided-fact-regeneration` (base `feat/237-clinician-demo-readiness`).

## Objective

A patient reply that Jev refuses only because it cannot tell whether an unasked
`on_request` fact was stated gets one regeneration that withholds those facts by
authored id, as #242 does for clear disclosure violations. The authored content no
longer invites the ambiguity, and refusal causes are counted without content.

## Why

In the 2026-10-20 rehearsal "Teve febre?" was refused twice with `low_confidence`:
the fever fact was asked and stated, but `fact_stated` for the unasked medication
fact stayed undecided (0.30, 0.31), probably because `hda-06` says "não tomou
antitérmico". The learner saw "Examinador: Anotado." for a patient question, and each
refusal cost about 1.5 s. #242 targets the retry only at stated-yes/asked-no.

## Constraints

- Builds on #242 (`unasked_fact_ids`, `withheld_fact_ids`) and #256 (a refusal plus a
  regeneration timeout keeps the turn).
- Other refusal causes keep today's behavior: the plain retry with `withheld_fact_ids: []`.
- Refused or unverified patient text is never logged, stored or returned (#224/#235).
  The refusal-cause counter logs only cause names and counts.
- Content edits keep clinical meaning, fictional case, pt-BR; the mapping record and
  the clinical review checklist follow.
- Allowed surfaces: `candidate_gate.ex`, `jev_decision.ex`, `jev_decision/**`,
  `stations.ex`, the appendicitis package, qualification fixtures, tests, docs.
- No live calls (no keys): the live check stays pending.

## Tasks

- [ ] T0 Feature document. Route: inline.
- [ ] T1 Targeted regeneration for undecided unasked facts: `TypesafeAdapter.verdict/4`
  reports `undecided_fact_ids` (on-request facts whose stated answer is undecided while
  the learner did not ask) only when they are the sole open answer of a
  `:low_confidence` verdict; `JevDecision` validates the ids against the package;
  `CandidateGate` withholds them in the single regeneration. Route: inline (three
  modules, each a few lines, already mapped; one writer = this worker).
- [ ] T2 Refusal-cause counter: `CandidateGate` counts each Jev decision by cause
  (`verified`, `risk`, `unasked_fact`, `undecided_unasked_fact`, `undecided_other`),
  logs one info line per refusal with only the cause name and its count, and exposes
  the counts through `Backend.Stations.refusal_cause_counts/0`. Route: inline.
- [ ] T3 Content: split `hda-06` so the fever answer no longer carries the
  antipyretic clause (item-4 criterion 3, recent medication). Update the mapping record
  (new decision), the clinical review checklist and the package test. Route: inline.

## Acceptance criteria

- With a stub verifier, an undecided-unasked-fact refusal triggers one regeneration
  with those ids withheld (tested).
- Other refusal causes keep today's behavior (tested).
- Live check: "Teve febre?" gets a patient answer. Pending (needs the maintainer's keys).

## Checks

- Focused `mix test` per task; full local CI script (mirrors `pr-validation.yml`).

## Progress

| Task | Commit | RED | GREEN |
| --- | --- | --- | --- |

## Next step

T1.

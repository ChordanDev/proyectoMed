# #242 Stop the simulated patient from volunteering unasked facts

Parent: #237. Branch: `fix/242-patient-unasked-facts` (base `feat/237-clinician-demo-readiness`).

## Objective

When Jev refuses a patient candidate because it states an `on_request` fact the
learner did not ask for, the single regeneration must be told, by authored fact id,
which facts not to mention yet, so the learner gets an answer instead of a refusal.
The patient prompt must also tell the model to answer only what was asked.

## Why

In the 2026-10-19 live run the question "Alguma coisa piora ou melhora a dor, como
andar, tossir ou ficar parado? Teve febre, náuseas ou vômitos?" got no answer: both
candidates stated `hda-05` (loss of appetite, `on_request`) without being asked, so
the TypeSafe verdict was `semantic_refusal` twice. The plain retry repeated the same
mistake because it carried no information about why the first candidate failed.

## Constraints

- #224/#235 invariants: refused text is never logged, stored, returned, or passed
  to the regeneration; the learner turn is kept when the retry still fails.
- The targeted instruction names facts by authored id (and authored content looked
  up by that id), never by Jev or candidate text.
- Refusals for any other reason keep today's retry unchanged.
- Only one regeneration per turn, inside the same monotonic deadline.

## Tasks

- [x] T1 Jev reports the on-request facts it refused as unasked (`unasked_fact_ids`,
  authored ids, validated at the `JevDecision` seam).
  Route: inline (2 files plus tests, already understood).
- [x] T2 `CandidateGate` targeted regeneration: arity-4 generator receives
  `%{withheld_fact_ids: ids}`; the default `Stations` generator and `StationAI`
  carry the ids into the system prompt.
  Route: inline (bounded, understood seams).
- [x] T3 Patient prompt answers only what was asked (multi-part questions do not
  pull adjacent facts); prompt lists authored fact ids. Docs updated.
  Route: inline.

## Acceptance criteria

- Stub verifier refusing the first candidate for a stated-but-unasked fact: the retry
  receives the targeted instruction and a compliant reply is delivered (tested).
- Refusals for other reasons keep today's retry (tested).
- No refused text is logged, stored or returned (tested).
- Live check on acute-appendicitis with `JEV_ADAPTER=typesafe`: pending, needs the
  maintainer's keys.

## Checks

- `mix test` (backend), local CI script mirroring `pr-validation.yml`.

## Progress

| Task | Commit | RED | GREEN |
| --- | --- | --- | --- |
| T1 | `42a9a7d` | 6 of 141 failed (typesafe + seam tests) | 141 passed |
| T2 | `516b378` | 7 of 144 failed (gate, stations, prompt, OpenAI payload) | 144 passed; full backend 1112 passed |
| T3 | `23de031` | 2 of 8 failed (station_ai prompt tests) | 8 passed; full backend 1114 passed |

Checks: local CI (mirror of `pr-validation.yml`) passed: backend 1114 tests,
web 192 tests (7 files), extra suite 4 tests. GitHub Actions is blocked by billing.

Native review: not run by this bounded writer (left to the orchestrator under RDD).

Pending: live check on acute-appendicitis with `JEV_ADAPTER=typesafe` (needs the
maintainer's keys).

## Next step

Maintainer live check of the question from the issue; then review and merge the
child PR into `feat/237-clinician-demo-readiness`.

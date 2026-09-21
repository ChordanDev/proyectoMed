# Jev prototype design and backlog

## Objective and authorization
Correct the Jev/PEP educational design and record the confirmed publication of two ADRs, Ticket 14, and five children before runtime implementation. Publication and acceptance are complete. After verification, the user authorized an isolated documentation commit and branch push, but no pull request or direct push to `develop`. Preserve user frontend edits and `.pi/`.

## Decisions
- Every non-template patient candidate must pass Jev before text/TTS. Only exact package/version-bound templates with deterministic applicability bypass it; length/model IDs never authorize text and deny rules take precedence.
- Learner input remains untrusted generation evidence. Rejected patient candidates never become trusted history/regeneration input.
- Semantic refusal/low confidence allows one bounded regeneration. Timeout/malformed/transport/provider failures invalidate the attempt, not clinical uncertainty or fallback text.
- Evaluate full ordered role-labelled evidence. Jev classifies; code validates existing evidence IDs and applies authored counts/order/caps/veto/exclusions and exact decimal points.
- Unresolved active criteria force total=null; show subtotal, scored/eligible maxima and unresolved items without rescaling. No probability-weighted points, official grade, certification, pass/fail or readiness claim.
- Use original partner-authored content. `2023_1_PEP_publicacao.pdf` (55 pages, 2023/1) is structural evidence, not imported content; repository PDF is a different edition.
- ADR-011 #123 and ADR-012 #124 were accepted as architecture on 2026-09-21. Acceptance does not implement runtime behavior, select or approve a provider, accept privacy/ZDR/legal terms, establish clinical accuracy, authorize certification/pass-fail/readiness claims, complete clinical pt-BR qualification, or activate pilot/production use. No other ADR changed.

## Tasks
- [x] T1 — Correct glossary/spec/design and reconcile voice, provider, evaluation and Impressos boundaries. Final independent verification passed.
- [x] T2 — Publish ADR-011 and ADR-012 in their original pre-acceptance state, plus Ticket 14 with five children. Confirmed identities: ADR-011 #123, ADR-012 #124, Ticket 14 #125, children #126–#130; native subissue and blocker relationships received exact readback, and an independent verifier passed.
- [x] T3 — Verify published graph and final document links. Local changed sections were read back, required links and exact blocker sets were present, `git diff --check` passed, and stale tentative/unpublished/blocked-publication claims were absent.
- [x] T4 — Restore delegated execution. Explore, worker and verifier completed after the user-requested OpenAI profile change.
- [x] T5 — Accept ADR-011 #123 and ADR-012 #124 with the current date, record human approval comments, and update Ticket 14 #125 without authorizing pilot/production activation. Confirmed on 2026-09-21 with exact body/comment readback: [#123 approval](https://github.com/ChordanDev/proyectoMed/issues/123#issuecomment-5767715417), [#124 approval](https://github.com/ChordanDev/proyectoMed/issues/124#issuecomment-5767716172), and [#125 gate-resolution record](https://github.com/ChordanDev/proyectoMed/issues/125#issuecomment-5767716610). #125 records the remaining provider/privacy/ZDR/legal/clinical gates.
- [x] T6 — Synchronize acceptance across the four design/tracking documents and independently verify ADR bodies/comments, unchanged native graph, `git diff --check`, and untouched runtime files. Independent verifier passed all requested live and local checks; historical absence of every unrelated ADR mutation cannot be proven without an immutable global snapshot, but no unrelated mutation was observed.
- [x] T7 — Deliver the four documentation files through a two-work-unit feature-branch chain on isolated branch `docs/jev-adr-acceptance` and push that branch without opening a PR. Slice 1 is commit `d57ebbfea094f05c069af6318dcdcc871929d0a5`; slice 2 is commit `2627519bcb9fccaaf91d90dc8807ad1f76cb2b68`. A final tracking-only commit records the confirmed remote delivery.

## Confirmed acceptance scope
- The completed GitHub operation changed only the internal status/body fields and added brief approval comments on #123/#124 plus a gate-resolution comment on #125.
- Accepted authorizes architecture only. It does not authorize implementation or pilot/production activation; select or approve a provider; accept privacy/ZDR/legal terms; establish clinical accuracy; authorize certification/pass-fail/readiness claims; or complete clinical pt-BR qualification.
- #126 has no native blockers after acceptance. Native dependencies remain unchanged: #127 [#126], #128 [#126, #127], #129 [#128], and #130 [#126, #127, #128, #129].
- #123 and #124 remain open with `type:docs`. #125–#130 still have no readiness labels. No other ADR changed.

## Routing and verification
Delegated mapping, multi-file writing and independent verification. Parent performed canonical gh state discovery because explorer lacks shell. Strict TDD off (retained source `openspec/config.yaml`); future runtime runner `bash scripts/test.sh`. Runtime tests skipped: docs-only work. No native review transaction or unrelated frontend candidate created.

- Earlier worker and final independent verifier: `git diff --check -- CONTEXT.md SPEC_MVP.md docs/design/jev-prototype.md odd/tasks/jev-prototype-design.md` passed.
- Local acceptance sync and independent verification: `git diff --check -- CONTEXT.md SPEC_MVP.md docs/design/jev-prototype.md odd/tasks/jev-prototype-design.md` passed. Untracked-doc whitespace/NUL/conflict scans were clean.
- Live verification confirmed #123/#124 Accepted bodies and approval comments, #125 gate-resolution comment, exact unchanged native graph, #126 with zero native blockers, no issue after #130, and no observed changes to other ADRs.
- `git diff --binary -- backend web` retained SHA-256 `5c212062dbeb1e19528e461597c25ee17f64f77ddc9fcd7a89ce9f70fd351bf0`; runtime status and the three frontend file hashes matched the pre-sync baseline.
- Explicit untracked design/task whitespace and conflict-marker scan: clean.
- Earlier changed-section readback confirmed the linked published identities, exact native blocker sets, then-current Proposed status, human gates, and unchanged ownership boundaries. That status statement is retained only as historical verification evidence from before acceptance.
- Native assessment returned unassessable (`native-assess-unavailable`, empty native output); required independent verification completed, not a native approval.
- The user authorized an isolated documentation branch and selected `feature-branch-chain` after the 655-line authored diff exceeded the ~400-line review threshold. Direct `develop` push remains prohibited; no PR is authorized in this step.
- Slice 1, commit `d57ebbfea094f05c069af6318dcdcc871929d0a5`, contains `CONTEXT.md` and `docs/design/jev-prototype.md` (296 authored lines). Native assessment was unavailable, so an independent verifier checked the exact commit and passed.
- Slice 2, commit `2627519bcb9fccaaf91d90dc8807ad1f76cb2b68`, contains `SPEC_MVP.md` and `odd/tasks/jev-prototype-design.md` (361 authored changed lines) and passed independent verification.
- `origin/docs/jev-adr-acceptance` was confirmed at the local branch tip after both work-unit commits. A tracking-only follow-up records this delivery evidence without changing architecture or runtime content.

## Tracker preflight and publication incident
Target github.com/ChordanDev/proyectoMed; default develop; actor ChordanDev with ADMIN. Completed all-state limit-1000 inventory, not saturated; ADR-011/012 and Ticket 14 titles were unused. Ticket 14 is not historical closed GitHub issue #14. Default-branch YAML forms and labels were verified. ADR form permits `type:docs`; the implementation form declares ready-for-agent, but #125 still has no labels because the remaining human qualification gates are pending. The architecture acceptance gate is resolved. No first-person checkboxes.

32 relevant issue bodies matched prior reviewed snapshots. #27/#44 are delivered seams, not duplicates. #114 Accepted selects LiveKit/WebRTC, Deepgram, and ElevenLabs; #115 Proposed V3 is excluded. #116 has children #117–#121; #119 owns turn safety, #120 approved TTS, and #121 interruption/recovery validation. Impressos #105 and children #106/#107/#108 remain unchanged; only event-dependent criteria need them. Live #22 has no native children; no historical links were reconstructed. Existing #22/#35/#38/#104–#121 bodies, states, and labels were confirmed unchanged.

The initial bounded publication attempt returned no created identities and was resolved as `no_write`. No policy or configuration bypass was attempted. A later, separately bounded publication operation succeeded and supplied exact per-write readback. This factual sequence replaces the earlier unresolved interpretation without treating the later operation as a retry through the denied boundary.

Issue #122 was a concurrent voice pull request, not a duplicate of the Jev ADRs or Ticket 14.

## Confirmed acceptance outcomes
- [ADR-011 #123](https://github.com/ChordanDev/proyectoMed/issues/123) is Accepted as of 2026-09-21, remains open with `type:docs`, and has the [human-approval comment](https://github.com/ChordanDev/proyectoMed/issues/123#issuecomment-5767715417).
- [ADR-012 #124](https://github.com/ChordanDev/proyectoMed/issues/124) is Accepted as of 2026-09-21, remains open with `type:docs`, and has the [human-approval comment](https://github.com/ChordanDev/proyectoMed/issues/124#issuecomment-5767716172).
- [Ticket 14 #125](https://github.com/ChordanDev/proyectoMed/issues/125) is open with no labels, has exactly native subissues #126–#130, and has the [architecture-gate resolution comment](https://github.com/ChordanDev/proyectoMed/issues/125#issuecomment-5767716610).
- Children: [#126](https://github.com/ChordanDev/proyectoMed/issues/126) package/schema and fixtures (AFK); [#127](https://github.com/ChordanDev/proyectoMed/issues/127) Jev adapter/gate (HITL); [#128](https://github.com/ChordanDev/proyectoMed/issues/128) evaluation and estimates (AFK); [#129](https://github.com/ChordanDev/proyectoMed/issues/129) result and disclaimer (HITL); [#130](https://github.com/ChordanDev/proyectoMed/issues/130) clinical qualification (HITL).
- Exact native blocker sets: #126 none; #127 blocked by #126; #128 blocked by #126 and #127; #129 blocked by #128; #130 blocked by #126, #127, #128, and #129.
- An independent verifier passed the publication identities, relationship graph, readback, and preservation checks.

ADR-011 now architecturally extends the relevant #35 boundary. ADR-012 now architecturally replaces the relevant portion of #38's no-score rule while preserving educational/privacy limits and the ban on certification, pass/fail, and readiness claims. Neither change is implemented in the runtime. Voice issues remain integration references, not blanket blockers. Provider/legal/privacy/ZDR review and clinical qualification remain human gates; architecture acceptance does not confer implementation or ready-for-agent approval.

## Preserved frontend baseline

Pre-runtime documentation diff SHA: `5c212062dbeb1e19528e461597c25ee17f64f77ddc9fcd7a89ce9f70fd351bf0`.

Current runtime status is limited to these three preserved frontend files; this documentation sync does not modify them. Final hashes equal this continuation's baseline (not proof about earlier turns):
- `web/src/App.test.tsx`: `58e289943ed06f97a9b3c1ad5c9d6b099f454483512698c700dc003e6d785532`
- `web/src/features/station/screens/StationScreen.test.tsx`: `93da2c49a6504442d5fbd65626c8fe9b1dd2f4a2a7fc14065461706528177501`
- `web/src/features/station/screens/StationScreen.tsx`: `85bbdde6d8ce4a43737125a227d9b74de7cfaf0a6f77ac3dcae9f81080c312d3`

## Next step
Pull request [#132](https://github.com/ChordanDev/proyectoMed/pull/132) (`docs/jev-adr-acceptance` -> `develop`, `type:docs`, `Closes #131`) is open; linked issue #131 carries `ready-for-agent` per the maintainer's direct instruction. This commit records the pull request after its creation. Merge requires passing CI validation and one approval; no merge has been performed. Provider/privacy/ZDR/legal and clinical pt-BR qualification remain separate gates; architecture acceptance does not authorize runtime implementation or pilot/production activation.

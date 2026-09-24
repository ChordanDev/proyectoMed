# Station Package Contracts and Fictional Rubric Fixtures (#126)

Parent: #125 (Jev verification and PEP-shaped educational estimates)
Branch: `feat/126-station-package-contracts` → PR target: `feat/125-jev-evaluation`
ADRs: ADR-011 #123 (Jev verification), ADR-012 #124 (PEP-shaped estimates)

## Tasks

- [ ] Bump version 1.0.0 → 2.0.0 with explicit v1 migration path
- [ ] Add `placeholder` marker validation; missing marker fails explicitly
- [ ] Extend `revealable_facts` with `id` and `disclosure_condition`
- [ ] Restructure rubric: levels (inadequado/parcialmente_adequado/adequado), decimal points (0.125), mandatory actions, order, count_cap, first_n, veto, exclusion, modality_requirement
- [ ] Add `approved_templates` validation (template_id + applicability, package/version-bound)
- [ ] Update JSON schema `package.schema.json` to 2.0.0
- [ ] Create fictional fixtures: binary/partial levels, 0.125 granularity, omission, uncertainty, unobservable, excluded, order, veto, first-N caps
- [ ] Create two-criterion partial reconciliation fixture (subtotal=0.25, scored_max=0.25, eligible_max=1.25, total=null)
- [ ] Migrate existing chest-pain package to v2
- [ ] Full test suite green
- [ ] Work-unit commits on feat/126

## Coordination

- #106 (Impressos) adds `impressos` optional field to the same schema/validator. This branch works on develop HEAD (no #106 merge). When both merge to #125, resolve conflicts in rubric/schema areas.
- Transcript-only criteria don't wait for Impressos.

## Evidence

- Commits: (pending)

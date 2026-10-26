## Agent skills

### Architecture governance

This repository follows mandatory architectural invariants:

- **Frontend feature-first (`web/src`)**:
  - Vite Single Page Application (SPA), frozen as the internal station harness (ADR-013 #209, ADR-015 #347): no account, billing or admin features.
  - Unidirectional dependency flow: `app -> features -> shared` (e.g. `web/src/features/station/`).
  - Keep `web/src/App.tsx` thin, delegating views and state to features.
  - Colocated tests next to code or in immediate `__tests__` directories; run via `npm --prefix web test`.
  - Share only after real reuse: keep code inside the feature until 2+ distinct features require identical behavior to maximize Locality and avoid premature abstraction.
- **Backend modular monolith (`backend/`)** (ADR-007 #92 and its amendment):
  - Structured around Phoenix Contexts as deep modules providing high Leverage.
  - Four public context interfaces, one module each: `Backend.Stations` (sessions, conversation, Station AI, grading, Educational Results, usage), `Backend.Accounts` (users, roles, terms, deletion, device-login tokens), `Backend.Billing` (RevenueCat webhook, entitlement, quota) and `Backend.Content` (cases, revisions, case format, published Station versions).
  - Internal implementation modules reside under `backend/lib/backend/<context>/`; callers outside a context use only its public module.
  - Dependencies point one way, with no cycles: `Stations` may call `Content`, `Billing` and `Accounts`; `Billing` may call `Accounts`; `Content` and `Accounts` call no other context.
  - Data lives in Postgres through Ecto (`Backend.Repo`, ADR-014 #346); only contexts use the Repo.
  - Thin `BackendWeb`: controllers and LiveViews (ADR-015 #347) only decode and validate input, delegate to a public context interface, and render HTML or serialize JSON.
  - Behaviours and adapters only for real variable seams (e.g. external provider integration); no speculative abstractions.
  - No umbrella apps or full hexagonal architecture without a new ADR.

### Project skills

- `frontend-feature-first`: `.agents/skills/frontend-feature-first/SKILL.md`
- `backend-phoenix-contexts`: `.agents/skills/backend-phoenix-contexts/SKILL.md`

### Issue tracker

Issues and specs are tracked in GitHub Issues through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository with root-level domain documentation and ADRs tracked as GitHub Issues. See `docs/agents/domain.md`.

### Git workflow

`main` is release-only. After repository administrators configure it, `develop` is the intended default integration branch: create `develop` from `main`; create each parent issue branch from `develop`; and create parallel child branches from their parent issue branch. Child PRs target their parent issue branch, while the parent maintains a Draft PR targeting `develop`. When all required children have merged and checks pass, merge the parent into `develop`.

CI runs on every non-draft PR, whatever its base, and on pushes to `develop`: the parent's Draft PR runs it once marked ready for review.

Issues without children (for example #23, #25, #27, #32, and #33) branch directly from and PR directly to `develop`. Independent children are sibling branches; chain them only for a genuine native blocker. Promote `develop` to `main` only for a release, then tag that release.

GitHub auto-closing keywords apply only to PRs targeting the repository default branch: child PRs use `Refs #N`; parent PRs targeting default `develop` use `Closes #parent` and `Closes #child` for completed children. Never push directly to `develop` or `main`: require a PR, CI, one approval, and resolved conversations. `main` accepts only PRs from `develop`; any emergency hotfix must return to `develop` afterwards. Every merge into `main` is a versioned release.

### Review feedback loop

When addressing review findings (human, advisory such as Jorge, or automated CI) on an open pull request, agents must never push follow-up commits in silence. After committing and pushing the resolution, the agent must leave an explicit comment on the PR containing:
1. **Finding reference:** The ID or title of each finding addressed.
2. **Commit SHA:** The specific commit hash implementing the fix.
3. **Solution summary:** What was changed to resolve the finding.
4. **Verification evidence:** Passing test counts, typechecks, builds, or review authority receipts.
5. **Chain propagation:** For chained PRs, explicit confirmation of whether and how the fix was merged forward into dependent branches.

Changing the GitHub default branch and configuring branch protection rules are administrator actions outside this documentation update.

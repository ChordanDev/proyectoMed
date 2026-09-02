## Agent skills

### Issue tracker

Issues and specs are tracked in GitHub Issues through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the canonical five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository with root-level domain documentation. See `docs/agents/domain.md`.

### Git workflow

`main` is release-only. After repository administrators configure it, `develop` is the intended default integration branch: create `develop` from `main`; create each parent issue branch from `develop`; and create parallel child branches from their parent issue branch. Child PRs target their parent issue branch, while the parent maintains a Draft PR targeting `develop`. When all required children have merged and checks pass, merge the parent into `develop`.

Issues without children (for example #23, #25, #27, #32, and #33) branch directly from and PR directly to `develop`. Independent children are sibling branches; chain them only for a genuine native blocker. Promote `develop` to `main` only for a release, then tag that release.

GitHub auto-closing keywords apply only to PRs targeting the repository default branch: child PRs use `Refs #N`; parent PRs targeting default `develop` use `Closes #parent` and `Closes #child` for completed children. Never push directly to `develop` or `main`: require a PR, CI, one approval, and resolved conversations. `main` accepts only PRs from `develop`; any emergency hotfix must return to `develop` afterwards. Every merge into `main` is a versioned release.

Changing the GitHub default branch and configuring branch protection rules are administrator actions outside this documentation update.

# 332 — Let admins edit a case in place with re-validation and history

Issue: #332 (parent spec #326). Branch: `feat/332-admin-edit-case` → PR base `feat/326-production-launch`. Builds on #331.

## Objective

Any admin edits a case's Markdown in the admin panel and saves. Every save re-runs the case parser and shows the located errors. A save made over a newer version is rejected with a pt-BR reload warning instead of overwriting (optimistic locking). Every save keeps the previous Markdown as a case revision with its editor and timestamp, and the panel lists the revisions.

## Why

Doctors fix small clinical errors without regenerating a case (#326 story 11), and the kept revisions show what doctors change so the generator prompt can improve (story 17). Two doctors editing the same case must not silently overwrite each other.

## Constraints

- `Backend.Content` owns `cases` and the new `case_revisions` table and calls no other context (ADR-007 #92 amendment). Errors come from `Backend.Stations.parse_case/1`, composed by the LiveView, as in #331.
- `BackendWeb` stays thin and never calls the Repo (architecture test).
- No change to accounts/auth code (sibling #336). The editor is the `current_scope.user` passed into `Content`; `Content` only reads its `id` and `email` and keeps an email snapshot, so it never calls `Accounts`.
- Published Station versions do not exist yet (approve/publish is a later child of #326). Edits only ever write `cases` and `case_revisions`, so they cannot change a published version; the revision rows give the future publish step something to reference.
- n8n keeps inserting rows with only area, theme and markdown: the lock version has a database default.
- Panel copy in pt-BR. Local Postgres only; test partition `MIX_TEST_PARTITION=_issue332`, dev database `backend_dev_issue332` for screenshots on `PORT=4136`.
- Planning heuristic: about 400 authored changed lines per task (advisory only).

## Checklist

- [x] T1 — Content: migration (`cases.lock_version`, `case_revisions`), `Backend.Content.CaseRevision`, `Content.update_case_markdown/3` (optimistic lock, previous Markdown kept as a revision in one transaction), `Content.list_case_revisions/1`; docs in `docs/case-format/README.md`.
- [x] T2 — Admin panel: edit form on the case page, save re-validates and shows located errors, stale save shows the reload warning, revisions listed with editor and timestamp.
- [ ] T3 — Checks and evidence: local CI script, screenshots (edit view with errors after a bad save, revisions list), PR.

## Routing

All tasks: delegated direct (this worker is the single bounded writer for the issue; each task touches 2+ non-trivial files).

## Acceptance criteria

- Saving re-runs the parser and shows the result.
- A stale save is rejected with a reload warning (optimistic locking).
- Previous revisions are kept and listed.
- Edits never change an already published Station version.

## Checks

- Focused: `MIX_TEST_PARTITION=_issue332 mix test test/backend/content_test.exs test/backend_web/live`.
- Full: local CI script (backend tests, web typecheck/lint, format, compile warnings, credo strict, dialyzer).

## Progress

- T1 (Content, commit 2c8db5b): migration `create_case_revisions` (`cases.lock_version` default 1, `case_revisions` with `case_id` on delete cascade, `markdown`, `lock_version`, `editor_id` on delete nilify, `editor_email` snapshot, unique `(case_id, lock_version)`), `Backend.Content.CaseRevision`, `Case.markdown_changeset/2` (`optimistic_lock(:lock_version)`), `Content.update_case_markdown/3` (`Repo.transact/1`: update + revision insert, replacing an `Ecto.Multi` that dialyzer flagged as an opaque-type mismatch; `{:error, :stale}` on a newer version; unchanged Markdown is a no-op) and `Content.list_case_revisions/1` (newest first). Docs: "Editing a case" in `docs/case-format/README.md`. RED — 8/8 new Content tests failed (undefined functions, no `lock_version`); GREEN — 20/20 Content tests.
- T2 (panel): `AdminCaseLive.Show` gains the "Editar caso" form (textarea, `save` event through `Content.update_case_markdown/3` with `current_scope.user` as editor), re-parses the saved Markdown so the located errors and numbered lines refresh, shows `#case-stale` ("Este caso mudou desde que você o abriu: recarregue a página antes de salvar.", reload link, draft kept in the editor) on a stale save, refuses a blank save with a flash, and lists "Versões anteriores" with version, editor email, UTC time and the replaced Markdown. RED — 6/6 new LiveView tests failed (no `#case-edit` form); GREEN — 17/17; focused run (Content, LiveView, architecture) 70/70; credo strict clean.

## Next step

T3: local CI, screenshots on `PORT=4136`, PR.

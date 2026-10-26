# 336 — Learner account on the web

Issue: #336 (parent #326). Branch: `feat/336-learner-account` from `feat/326-production-launch`.

## Objective

Learners (role `student`) create and manage their own account on the LiveView
pages: sign-up with terms and privacy acceptance (date and document version
stored), login, password recovery by email and account deletion that erases the
learner and all their data. Production sends the account emails through a real
provider chosen by environment variables.

## Why

#331 shipped `phx.gen.auth` with admins provisioned by seeds and no public
sign-up. Learners need self-service accounts before launch (#326), and the
privacy obligations require recorded consent and full erasure.

## Constraints

- Admin accounts are never creatable through public sign-up (`role` is never cast).
- `Backend.Accounts` calls no other context; `BackendWeb` stays thin.
- Legal texts are placeholders the user will replace; pt-BR copy.
- Local mail adapter stays for dev, test adapter for tests; no secrets committed.
- Do not touch the admin case panel (sibling #332).
- Tests run on the isolated partition `MIX_TEST_PARTITION=_issue336`.

## Tasks

Route for every task: delegated direct (this bounded writer); inline inside the writer.

- [x] T1 Sign-up with terms and privacy acceptance (migration, registration
  changeset, legal document versions, `/users/register`, `/termos`, `/privacidade`).
- [x] T2 Password recovery by email (`/users/reset-password`, token context
  `reset_password`, confirms an unconfirmed account on reset).
- [x] T3 Account deletion that erases the learner and all their data, with the
  documented hook for later contexts (cascading foreign keys, enforced by a test).
- [x] T4 Production mail provider chosen by environment variables (`MAILER_PROVIDER`,
  `MAILER_API_KEY`, `MAILER_DOMAIN`, `MAILER_FROM_EMAIL`, `MAILER_FROM_NAME`).
- [x] T5 README documentation, local CI and screenshots on PORT=4138.
- [x] T6 Jorge advisory review and confirmed repairs.

## Acceptance criteria

- Sign-up requires accepting the terms and the privacy policy and stores the
  acceptance date and version of each.
- Login and password recovery work.
- Deleting the account removes the user and all their data.
- Admin and student roles stay separate.

## Checks

- Focused: `MIX_TEST_PARTITION=_issue336 mix test <files>` (RED before GREEN).
- Closure: local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

- T1: RED 13/14 failing (no `/users/register` route, no `Accounts.legal_document/1`);
  GREEN full backend suite 1962 passed; format, compile --warnings-as-errors, credo --strict clean.
  Commit a38ea73.
- T2: RED 14/14 failing (no reset functions or routes); GREEN 14/14, full suite 1976
  passed; compile and credo clean. Commit cc2cd07.
- T3: RED 12 of 14 new tests failing (the foreign-key invariant and the hidden admin
  section already held); GREEN 26/26 focused, full suite 1990 passed; compile and
  credo clean. Hook decision: later contexts erase their rows through
  `references(:users, on_delete: :delete_all)`, enforced by
  `AccountDeletionTest`; Accounts keeps calling no other context. Commit 1378501.
- T4: RED 7/11 failing (no `MAILER_PROVIDER` handling; the Req client delivery test
  already passed, proving Swoosh's Req client works with req 0.7). A first version
  refused to boot `:prod` without `MAILER_PROVIDER`; it broke 7 existing prod
  runtime-config tests outside this issue's edit surface, so unset now keeps the
  local adapter (documented: set a provider in every real deployment). GREEN full
  suite 2000 passed; credo clean. README documents the account pages and the
  `MAILER_*` variables. Commit 06572ad.
- T5: first local CI run failed 1/2000: the shared, non-partitioned `backend_test`
  database carries `case_revisions.editor_id` from sibling #332, which restricts
  deletes. Editors are admins and admins are never deleted, so the cascade test now
  lists admin-only references explicitly (commit f1fc8e5). Second run: LOCAL CI
  PASSED (web 337 tests, backend 2000 tests, typecheck, lint, format, compile,
  credo, dialyzer). Screenshots NOT captured (no browser available: the Playwright
  download hung, no Chrome installed); smoke check on PORT=4138 against the
  isolated `backend_dev_issue336` database returned 200 for the sign-up, legal,
  reset and login pages and 302 for unauthenticated settings. Pending: manual screenshots.
- T5 (closure): merged `origin/feat/326-production-launch` at b8d0f9a (#358, #359)
  cleanly as 52a7904; LOCAL CI PASSED. Screenshots captured with headless Firefox
  on PORT=4138 against `backend_dev_issue336`: the sign-up page with both
  acceptance checkboxes, and the account settings with the delete section
  (authenticated HTML rendered from a curl login session). Kept outside the repo.
- T6: Jorge advisory review (mapper, three specialists, refuter) on b8d0f9a..52a7904.
  Verified without findings: no public path creates an admin, acceptance stores
  version and date, deletion erases the Postgres rows and revokes sessions and
  tokens, no mail secret is committed or echoed. Confirmed and repaired test-first:
  - Reset token checked only at mount (medium): an open reset page could set the
    password after the link was used or expired. The submit now re-verifies the
    token (RED 6/7, GREEN). Commit 63269af.
  - Sign-up crashed when the confirmation email failed after the account was
    committed (low): it now keeps the account, logs the error and sends the
    learner to the login page to request a link (RED MatchError, GREEN). Commit 8454b05.
  - Admin-only foreign key comment said restrict while the rule is nilify (low,
    doc drift). Commit f0dd734.
  - Production booted silently with the never-delivering local adapter when
    `MAILER_PROVIDER` was unset (medium): `:prod` now refuses to boot without it
    and warns when `local` is named on purpose; the 7 prod runtime-config tests
    set `MAILER_PROVIDER=local` in their prod env (RED 11/12, GREEN 214/214). This
    supersedes the T4 fallback. Commit f973219.
  Follow-ups, not in this PR: rate limiting of sign-up, reset and magic-link
  emails; sign-up email enumeration (product/privacy decision); idempotent
  double-submit of account deletion (theoretical race). LOCAL CI PASSED after the
  repairs (web 337, backend 2028).

## Next step

Merge the PR into `feat/326-production-launch` after human review; replace the
placeholder legal texts and set `MAILER_*` in the deployment (production no
longer boots without `MAILER_PROVIDER`).

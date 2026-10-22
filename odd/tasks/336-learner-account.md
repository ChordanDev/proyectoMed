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
- [ ] T3 Account deletion that erases the learner and all their data, with the
  documented hook for later contexts (cascading foreign keys, enforced by a test).
- [ ] T4 Production mail provider chosen by environment variables (`MAILER_PROVIDER`,
  `MAILER_API_KEY`, `MAILER_DOMAIN`, `MAILER_FROM_EMAIL`, `MAILER_FROM_NAME`).
- [ ] T5 README documentation, local CI and screenshots on PORT=4138.

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
  passed; compile and credo clean.

## Next step

T3.

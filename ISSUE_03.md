## Parent

Part of #22

## What to build

An ephemeral session store in `Backend.Conversation` that backs the MVP station lifecycle. Sessions live in an in-memory ETS table keyed by `session_id` with a short safety timeout. There is no database, no persistence, no personal history.

## Acceptance criteria

- [ ] `Backend.Conversation.start/0` returns `%{session_id, started_at, expires_at}` with a default safety timeout (proposal: 30 minutes).
- [ ] `Backend.Conversation.append_message/2` appends a `%{role, modality, text, at}` entry, returns `{:ok, session}` or `{:error, :expired}`.
- [ ] `Backend.Conversation.complete/2` returns `{:ok, session}` or `{:error, :expired}` and locks the session.
- [ ] `Backend.Conversation.fetch/1` returns `{:ok, session}` or `{:error, :not_found}` for unknown ids and `{:error, :expired}` past the timeout.
- [ ] A supervisor process periodically purges expired sessions.
- [ ] ExUnit coverage: `Backend.ConversationTest` covers start, append, complete, fetch, expiry, double-complete.
- [ ] `bash scripts/test.sh` exits 0.

## Blocked by

- #24 (Station Package format + StationLoader)

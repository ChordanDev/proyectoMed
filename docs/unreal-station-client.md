# Unreal station client module

`StationClient` (`unreal/Source/StationClient/`) is the one module in the Unreal
client that talks to Phoenix and, from #191, to LiveKit. Scene and interface code
depend on it and never call the network directly. It was introduced by #190; the
parallel slices #191, #192, #194, #195 and #196 consume this interface.

> **Changing the interface.** Adding to it, or changing a signature, a type or an
> error code listed here, needs agreement from both Unreal tracks (ChordanDev and
> andrewblockernst) before it lands. Update this document in the same PR.

## Quick path

```cpp
#include "StationClient.h"
#include "StationClientSubsystem.h"

UStationClient* Client = GetGameInstance()->GetSubsystem<UStationClientSubsystem>()->GetClient();

Client->FetchActiveStation([](const TStationResult<FStationSummary>& Result)
{
	if (Result.HasError())
	{
		// Result.GetError().Code, for example "network_error"
		return;
	}
	const FStationSummary& Station = Result.GetValue(); // title, brief, voice mode
});

// Responses can still arrive after the caller is gone (for example when PIE
// stops), so capture UObjects weakly.
Client->StartSession(/*bAudioConsent*/ true, [WeakClient = TWeakObjectPtr<UStationClient>(Client)](const TStationResult<FStationSession>& Result)
{
	// From here, WeakClient->GetRemainingTime() counts down the Station Timer.
});
```

Build-file dependency: add `"StationClient"` to the consuming module's
`PrivateDependencyModuleNames`.

## Rules every consumer can rely on

| Topic | Rule |
| --- | --- |
| Threading | Every callback runs on the game thread, exactly once while the engine runs. A call refused locally (for example `no_session`) calls back before it returns. |
| Timeouts | A request Phoenix does not answer within 15 s fails with `network_error`. `FetchResult` waits 95 s, as the web client does, because the first fetch assesses the run before answering. |
| One run at a time | The client holds at most one session. `StartSession` fails with `session_in_progress` until `DiscardSession` succeeds or `ForgetSession` is called. |
| Content | The client holds no clinical rules and no Station Package content. Everything it returns is what Phoenix served for this run. |
| Secrets | `FStationVoiceCredential::Token`, the device login's `device_code` and its `access_token` and `refresh_token` are secrets: never log or display them (the `user_code` is shown to the learner, but not logged). |
| Authentication | `GET /stations`, `GET /pre-station-notice`, `POST /sessions` and every `/sessions/:id/...` route need `Authorization: Bearer <access_token>` from the [device login](#learner-login-device-flow). A session belongs to the learner that started it. |
| Configuration | Phoenix's origin comes from `[/Script/StationClient.StationClient] PhoenixBaseUrl` in the game config (default `http://127.0.0.1:4000`), or `-PhoenixUrl=<origin>` on the command line. |

## Station Timer

Phoenix owns the duration: `deadline_at` is fixed when the session starts (ten
minutes today). The client anchors Phoenix's `server_now` to the local monotonic
clock, so `GetRemainingTime()` ignores changes to the machine's date and time.

- It returns zero before a run, after the deadline, and once the run is completed.
- `RefreshSession` re-anchors the clock to Phoenix.
- The monotonic clock stops while the Mac sleeps, so after a sleep the timer shows
  more time than is left. Phoenix still refuses late turns with
  `station_time_elapsed` (409): on that error, and when the app comes back to the
  foreground, call `RefreshSession`.
- `GetServerTime()` is Phoenix's clock now (UTC), from the same anchor. It is
  unset until Phoenix has sent a `server_now`, and keeps running after the run.
  The scene's desk clock uses it ([#425](#the-prova-simulada-exam-room-issue-425)).
- At zero, call `FinishSession(EStationFinishReason::Timer)`. If Phoenix answers
  `deadline_not_reached` (409), the local clock ran ahead: call `RefreshSession`
  and keep counting.

### Training overtime (#323)

In a training, `deadline_at` is the expected end, not the end of the run. Phoenix
keeps accepting turns and impresso requests after it, until `cap_at`
(`started_at` + 20 minutes). At `cap_at` Phoenix completes the run with
`completion_reason: "cap"`, and later turns get `station_time_elapsed` (409).
`expires_at` stays after `cap_at`, so the result can still be read.

- Do not call `FinishSession(EStationFinishReason::Timer)` at zero in a training:
  show that the expected time is over and count the overtime up. The learner
  finishes whenever they choose (`user`).
- In a real test (`"simulated_exam"`), `cap_at` equals `deadline_at`: the run ends
  at ten minutes with `completion_reason: "timer"` and there is no overtime.

### A simulated exam ends exactly at its deadline (#424)

Phoenix decides this; the client only waits for it.

- There is no grace for the dialogue: the patient never answers after the
  deadline, and the voice worker stops the reply it is speaking at that moment.
- What the learner started saying before the deadline still counts. Phoenix keeps
  that utterance with no patient reply, even when its transcript arrives just after
  the deadline. The worker reports it like a refused reply (`PatientUnanswered`).
- An utterance that starts after the deadline (500 ms tolerance) is discarded. It
  gets no outcome event, and the worker leaves the room without an `error` event,
  so the run is not taken for a lost voice.
- At zero, call `FinishSession(EStationFinishReason::Timer)` as usual. Phoenix
  answers when its evidence window closes: when an utterance that started after
  the deadline arrives, or at most 5 seconds after the deadline. That is well inside the request timeout
  (15 s). Keep the voice link until the finish returns; `FinishSession` leaves the
  room afterwards.

## Operations

All operations are methods of `UStationClient`. Each one takes a
`TStationCallback<T>`, which receives a `TStationResult<T>`: a value, or an
`FStationClientError`.

| Method | Phoenix route | Value on success | Main consumer |
| --- | --- | --- | --- |
| `FetchActiveStation` | `GET /api/stations/active` | `FStationSummary`: title, candidate brief, voice mode | #190 |
| `StartSession(bAudioConsent)` | `POST /api/stations/active/sessions` | `FStationSession`, a training; starts the Station Timer | #190 |
| `StartSession(bAudioConsent, Mode)` | `POST /api/stations/active/sessions` | `FStationSession` in the chosen Station Mode (`EStationSessionMode`: `Training` or `SimulatedExam`); a simulated exam needs `bAudioConsent` | #421 |
| `RefreshSession` | `GET .../sessions/:id` | `FStationSession` with status and transcript (`Messages`) | #195, #196 |
| `RequestVoiceCredential` | `POST .../sessions/:id/voice` | `FStationVoiceCredential` for one LiveKit room | #190, #191 |
| `SendTurn(Text, Modality)` | `POST .../sessions/:id/messages` | `FStationTurnReply`: the approved patient reply, or an examiner acknowledgement (it releases nothing; see [exam requests in the dialogue](#exam-requests-in-the-dialogue-issue-351)) | #191, #192, #194 |
| `RequestImpresso(Text, RequestId)` | `POST .../sessions/:id/impressos/request` | `FStationImpressoReply`: the decision and what was released | #194 |
| `ListImpressos` | `GET .../sessions/:id/impressos` | Every impresso released so far | #194 |
| `ArmExamMode` | `POST .../sessions/:id/exam-mode` | `FStationExamMode`: the learner's next utterance is the [spoken exam request](#spoken-exam-requests-issue-364), until `ExpiresAt` | #364 |
| `CancelExamMode` | `DELETE .../sessions/:id/exam-mode` | Nothing; the mode is disarmed | #364 |
| `FinishSession(Reason)` | `POST .../sessions/:id/finish` | `FStationSession` marked completed | #195 |
| `FetchResult` | `GET /api/v2/.../sessions/:id/result` | `FStationResult`: criteria with transcript evidence | #195 |
| `DiscardSession` | `POST .../sessions/:id/discard` | Nothing; the local session is cleared only after Phoenix confirms | #195, #196 |
| `ForgetSession` | none | Clears the local session at once and leaves the room, for a run Phoenix stopped answering; call `DiscardSession` first so Phoenix forgets it too if it is back | #196 |

Synchronous accessors: `GetSession()` (null without a run), `GetRemainingTime()`
(and `GetRemainingTimeAt(LocalSeconds)` for tests), `GetServerTime()`, `GetPhoenixBaseUrl()` and
`SetPhoenixBaseUrl()`. `FStationClock` is the public helper behind the timer.

Known limits, for the slices that build on them:

- A run whose `StartSession` is still in flight when the game quits is not
  discarded; Phoenix forgets it after 30 minutes. So does a run forgotten with
  `ForgetSession` whose `DiscardSession` did not reach Phoenix.

### Run lifecycle

```text
no session ──StartSession──▶ active ──FinishSession──▶ completed
    ▲                          │                          │
    └──────── DiscardSession ◀─┴──────────────────────────┘
```

- `SendTurn` is refused locally with `session_completed` once the run is completed.
- `RequestImpresso` with an empty `RequestId` gets a new id, returned only on
  success. To retry after a failure without asking twice, create the id yourself
  (`FGuid::NewGuid().ToString()`) and pass it on every attempt.
- `SendTurn` is not idempotent. After a `network_error`, Phoenix may still have
  taken the turn, and after `reply_verification_failed` it may have kept it
  without a reply: call `RefreshSession` and check the transcript before resending.
- `RefreshSession` skips transcript lines whose speaker the client does not know.
- `FStationSession::Mode` is the Station Mode Phoenix recorded (#421). It is fixed
  for the whole run; a body without `mode` reads as `Training`, and one with an
  unknown mode fails with `invalid_response`.
- `RefreshSession` never reopens a run this client saw finish: an answer read
  before the finish keeps the run completed, with its completion time.

### A training that loses Phoenix (#196)

`UStationRunFlow` invalidates a training when Phoenix is lost, because nothing
can go on without it. Phoenix counts as lost when a call of the run gets no
answer (`network_error`, or `http_502`, `http_503` or `http_504`, which a
gateway answers for a Phoenix that did not) and the `RefreshSession` that
follows gets none either. The calls are a turn (its transcript reload is the
check), an exam request, the voice credential, the finish and the result. A
voice failure checks Phoenix the same way: `Fatal` (for example a failed
transcription) or a `Failed` link. A failed microphone does not.

- When the check is answered, nothing changes: the turn or exam request comes
  back to the learner as before, a voice failure leaves the run going in writing
  ("A voz caiu. O tempo da estação continua." or "Microfone indisponível.
  Continue por escrito."), and a finish or result shows why the feedback is
  missing.
- When it is not, the step becomes `Invalidated`: the run's conversation,
  requests and answers are forgotten, the room is left, the patient is silenced
  and nothing resumes it, and every later Phoenix answer for the run is
  dropped. No feedback or partial result is ever shown. A check that fails
  after the run reached its feedback changes nothing: the finish and the
  result were answered.
- Invalidating can take up to about 30 s: the call's 15 s timeout, then the
  check's.
- `Restart` sends `DiscardSession` without waiting for it, calls
  `ForgetSession` and shows the brief at once. A new run starts as soon as
  Phoenix answers `StartSession`.
- A Phoenix error with its own code (`station_time_elapsed`, `invalid_attempt`,
  and so on) is an answer: it never invalidates the run.
- The real-test mode ("Prova simulada", #318), where a voice failure also
  invalidates the run, is not built yet.

## Errors

`FStationClientError` carries `HttpStatus`, `Code` and `Message`. `Code` is
Phoenix's `error` field when Phoenix answered; Phoenix's `Message` is Brazilian
Portuguese and can be shown to the learner. `HttpStatus` is 0 when no Phoenix
answer was involved.

Codes the client raises itself:

| Code | When |
| --- | --- |
| `network_error` | Phoenix did not answer: not running, unreachable, or no reply within 15 s. |
| `invalid_response` | Phoenix answered with a body that does not match this contract. |
| `no_session` | A session operation was called with no run in progress. |
| `session_in_progress` | `StartSession` while a run is held or already starting. |
| `session_completed` | `SendTurn` after the run ended. |
| `http_<status>` | Phoenix answered an error without an `error` field. |

Phoenix codes the slices are expected to handle (see `router.ex` and the
controllers for the full list). Branch on `Code`, not on `HttpStatus`: one code
can come with different statuses from different routes.

| Code | Status | Raised by |
| --- | --- | --- |
| `missing_token` | 401 | every authenticated route without `Authorization: Bearer` |
| `invalid_token` | 401 | every authenticated route with an unknown, expired or revoked access token: refresh, or log in again |
| `session_not_found` | 404 | every session route, also for another learner's session |
| `session_expired` | 410 | every session route |
| `session_completed` | 422, 409 | `SendTurn` and `RequestVoiceCredential` (422); `RequestImpresso` and `POST .../exam-mode` (409) |
| `station_time_elapsed` | 409 | `SendTurn` after the deadline |
| `deadline_not_reached` | 409 | `FinishSession(Timer)` called early |
| `audio_consent_required` | 400 | `StartSession` of a `SimulatedExam` without audio consent (#421) |
| `no_consent` | 403 | `RequestVoiceCredential` and `POST .../exam-mode` on a run without audio consent |
| `typed_input_not_allowed` | 403 | `SendTurn` with `Modality` text and `RequestImpresso` in a `SimulatedExam`, which is voice only (#422) |
| `voice_unavailable` | 503 | `RequestVoiceCredential` when Phoenix has no LiveKit set up |
| `rate_limited` | 429 | every session route that calls a paid provider, past its per-session or per-learner limit (see [Rate limits](#rate-limits-issue-395)); `RequestVoiceCredential` also more than 5 times a minute |
| `reply_verification_failed`, `station_ai_unavailable`, `timeout` | 502, 504 | `SendTurn` |
| `session_not_finished` | 422 | `FetchResult` before `FinishSession` |
| `invalid_attempt` | 502 | `FetchResult` when the run could not be assessed |

## Learner login (device flow)

The client acts for a learner account (#337). It never asks for a password:
the learner logs in in a browser, as with a TV app (shaped after OAuth 2.0
Device Authorization, RFC 8628). Admin accounts cannot use it.

1. **Start.** `POST /device/start` (no body, no token):

   ```sh
   curl -s -X POST "$PHOENIX/device/start"
   ```

   ```json
   {
     "device_code": "Gq8…(43 characters)",
     "user_code": "BCDF-GHJK",
     "verification_uri": "https://<phoenix>/device",
     "verification_uri_complete": "https://<phoenix>/device?user_code=BCDF-GHJK",
     "interval": 5,
     "expires_in": 600
   }
   ```

   Show the `user_code` and `verification_uri` (or a QR code of
   `verification_uri_complete`). Keep `device_code` secret.

2. **The learner confirms.** At `/device` the learner logs in (or signs up),
   checks that the code matches the one in the game, and chooses
   **Autorizar** or **Negar**.

3. **Poll.** Every `interval` seconds, until `expires_in` runs out:

   ```sh
   curl -s -X POST "$PHOENIX/device/token" \
     -H 'content-type: application/json' -d '{"device_code": "'"$DEVICE_CODE"'"}'
   ```

   While waiting, Phoenix answers `400` with an `error` code and a pt-BR
   `message`:

   | `error` | Meaning | What to do |
   | --- | --- | --- |
   | `authorization_pending` | Not confirmed yet. | Poll again after `interval`. |
   | `slow_down` | Polled faster than `interval`. | Add 5 s to the interval for every later poll. |
   | `access_denied` | The learner chose **Negar**. | Stop; offer to start again. |
   | `expired_token` | The 10 minutes ran out, even if the learner approved in time. | Stop; start again. |
   | `invalid_grant` | Unknown or already used `device_code`. | Stop; start again. |

   Once the learner approves, the next poll answers `200` once:

   ```json
   {
     "access_token": "…",
     "refresh_token": "…",
     "token_type": "Bearer",
     "expires_in": 900,
     "refresh_expires_in": 2592000
   }
   ```

4. **Call the API** with `Authorization: Bearer <access_token>`:

   ```sh
   curl -s "$PHOENIX/stations" -H "authorization: Bearer $ACCESS_TOKEN"
   ```

5. **Refresh.** The access token lasts 15 minutes. On `401 invalid_token` (or
   shortly before `expires_in`), exchange the refresh token for a new pair:

   ```sh
   curl -s -X POST "$PHOENIX/device/refresh" \
     -H 'content-type: application/json' -d '{"refresh_token": "'"$REFRESH_TOKEN"'"}'
   ```

   The answer has the body of step 3. Both old tokens stop working: store the
   new pair before using it. A refresh token lasts 30 days from its last use.
   Presenting any refresh token this login already rotated away, however many
   refreshes ago, revokes the whole login. Send one refresh at a time and do
   not retry it with the old token: a retry after the first refresh succeeded
   counts as reuse. On `400 invalid_grant`, start the login again from step 1.

6. **Log out.** `POST /device/logout` with the access token revokes this
   device's tokens; `{"everywhere": true}` revokes every device login of the
   learner. It answers `204`.

   ```sh
   curl -s -X POST "$PHOENIX/device/logout" -H "authorization: Bearer $ACCESS_TOKEN"
   curl -s -X POST "$PHOENIX/device/logout" -H "authorization: Bearer $ACCESS_TOKEN" \
     -H 'content-type: application/json' -d '{"everywhere": true}'
   ```

Changing or resetting the password and deleting the account also revoke every
device login: the next call answers `401 invalid_token`, and the refresh
`400 invalid_grant`. These account changes and logout everywhere also revoke
a login the learner approved but the client has not polled yet: its poll
answers `400 invalid_grant`. Phoenix stores only hashes of codes and tokens and never
logs them.

## Station catalog (`GET /stations`)

Phoenix lists the published stations a learner can pick (issue #333). There is
no `UStationClient` method for it yet; a client calls the route directly.

- **Routes:** `GET /stations` and `GET /api/stations` return the same body.
- **Auth:** none today. Both routes sit on the public `:api` pipeline; they will
  require the device token once #337 (Unreal device login) lands.
- **Response:** `200` with a JSON array, `[]` when nothing is published.
- **What is listed:** only cases whose status is approved, and for each case
  only its latest approved version. Pending and disapproved cases never appear;
  disapproving a case removes it at once.
- **Ordering:** by case number, ascending.

```json
[
  {
    "id": 1,
    "version": 2,
    "slug": "acute-appendicitis",
    "area": "Cirurgia Geral",
    "theme": "Abdome agudo inflamatório — apendicite aguda",
    "actors": [
      {
        "id": "paciente",
        "role": "patient",
        "name": "Rafael Nogueira",
        "age": 27,
        "voice": "masculina-adulta"
      }
    ]
  }
]
```

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | integer | The case number: the station's identity in the catalog. Unique per entry. |
| `version` | integer | The published version of that case, starting at 1; it grows each time an edited case is approved again. |
| `slug` | string | The case's `[ESTAÇÃO]` id. For display only: two cases may share one slug, so never key on it. |
| `area` | string | `[ÁREA]` of the published version. |
| `theme` | string | `[TEMA]` of the published version. |
| `actors[].id` | string | The `[ATOR]` id. |
| `actors[].role` | string | `patient` or `companion`. |
| `actors[].name` | string | The actor's display name. |
| `actors[].age` | integer | The actor's age in years. |
| `actors[].voice` | string | The voice key (`voz=`) the voice worker maps to a TTS voice. |

Examiner-only data (facts, persona, tone, mandatory questions, presenting
context, rubric, impressos) is never in the catalog.

## Sessions on a published station (`POST /sessions`)

Phoenix starts a session on a station of the catalog (issue #334, ADR-013
amendment on #209). There is no `UStationClient` method for it yet; until the
client moves, `StartSession` keeps using the deprecated active-station routes
below.

- **Auth:** none today, like the catalog; the device token arrives with #337.
- **Request:** a JSON body with exactly one station choice and the audio consent.

| Body | Starts |
| --- | --- |
| `{"station_id": 12, "audio_consent": true}` | The latest published version of catalog entry `12` (the case number; a numeric string such as `"12"` is accepted too). |
| `{"random": true, "area": "Pediatria", "audio_consent": false}` | A random published station of that `area` (the catalog's `area`). |
| `{"random": true, "audio_consent": false}` | A random published station of any area. A blank `area` means any area. |

- **Station Mode (#421):** an optional `mode`, fixed for the whole run and
  returned by every session response (start, `GET .../sessions/:id` and
  `POST .../finish`):

| `mode` | Starts |
| --- | --- |
| absent, `null` or `"training"` | A training, as before the mode existed, so older clients keep working. |
| `"simulated_exam"` | A simulated exam ("Prova simulada", #318). It needs `"audio_consent": true`. |

- **Response:** `201` with the session. `station_id` is the catalog id and
  `station_version` the published version (both integers, as in the catalog);
  `station` carries what the learner sees before the first turn.

```json
{
  "session_id": "Jp0qJouf20BUkSvGHbDCgA",
  "station_id": 12,
  "station_version": 2,
  "station": {
    "id": 12,
    "version": 2,
    "slug": "acute-appendicitis",
    "area": "Cirurgia Geral",
    "theme": "Abdome agudo inflamatório — apendicite aguda",
    "display_title": "Abdome agudo inflamatório — apendicite aguda",
    "language": "pt-BR",
    "candidate_brief": { "scenario": "…", "tasks": ["…"] },
    "actors": [
      { "id": "paciente", "role": "patient", "name": "Rafael Nogueira", "age": 27, "voice": "masculina-adulta" }
    ]
  },
  "audio_consent": true,
  "mode": "training",
  "status": "active",
  "voice_mode": "realtime",
  "started_at": "2026-10-25T15:00:00Z",
  "expires_at": "2026-10-25T15:30:00Z",
  "deadline_at": "2026-10-25T15:10:00Z",
  "cap_at": "2026-10-25T15:20:00Z",
  "server_now": "2026-10-25T15:00:00Z"
}
```

- **Pinned version:** the session plays the version published when it
  started. Approving an edited case later publishes a new version for new
  sessions only; a running session, its turns, impressos and result never
  change.
- **Errors:**

| Code | Status | When |
| --- | --- | --- |
| `invalid_parameters` | 400 | No station choice, both `station_id` and `random`, a `station_id` that is not a positive integer, a non-string `area`, a missing or non-boolean `audio_consent`, or a `mode` other than `"training"` or `"simulated_exam"`. |
| `audio_consent_required` | 400 | A `"simulated_exam"` without `"audio_consent": true`. No session starts. |
| `subscription_required` | 402 | The learner has no active subscription (#339). |
| `station_not_found` | 404 | No published station has that `station_id` (unknown, pending or disapproved case). |
| `no_published_station` | 404 | Nothing is published in that `area` (or at all, without one). |
| `daily_quota_exhausted` | 429 | The learner has used today's simulations (#340). See [Daily quota](#daily-quota). |
| `station_unavailable` | 503 | The published package could not be loaded; the run cannot start. |

### Daily quota

Each plan allows a number of simulations per day (#340). Past it, `POST
/sessions` answers `429` with a `Retry-After` header (seconds until the reset)
and this body:

```json
{
  "error": "daily_quota_exhausted",
  "message": "Você usou todas as simulações de hoje. A cota renova à meia-noite (horário de Brasília).",
  "daily_quota": 10,
  "resets_at": "2026-10-26T03:00:00.000000Z"
}
```

- **Day boundary:** the quota resets at local midnight in `America/Sao_Paulo`,
  which is 03:00 UTC (Brazil has no daylight saving time). `resets_at` is that
  moment, in UTC.
- **What counts:** sessions that reached a graded result that day, plus
  sessions in flight. A session holds its slot from its start until it is
  graded or until its `expires_at`. A session that is abandoned or fails
  technically is never graded, so it releases its slot at `expires_at` and
  never consumes quota. A graded session counts on the day it finished.
- **Two starts at once:** starts of one learner are serialized. At one
  simulation left, two `POST /sessions` sent at the same moment start one
  session; the other answers `429`. Counting only graded results at start
  would let both through.
- Show the `message` and offer a retry after `resets_at`. The remaining count
  is shown on the web account page (`/conta`).

### Pre-Station Notice (`GET /pre-station-notice`)

Show it before a station, before asking for audio consent (ADR-003 #36). Phoenix
derives `providers` from its running configuration, so it names every provider
the station will actually call, and only those. All texts are pt-BR and can be
shown as they are.

```json
{
  "title": "Ferramenta Educacional",
  "body": "Ferramenta educacional independente para treino de habilidades clínicas. Não insira dados de pacientes reais.",
  "educational_disclaimer": "Estimativa educacional gerada por IA. Não é nota oficial do Revalida. …",
  "audio_consent": "Ao ativar a voz, você aceita que o áudio da conversa seja processado pelos provedores de áudio listados. …",
  "providers": [
    {
      "id": "anthropic",
      "name": "Anthropic (Claude)",
      "processes": "text",
      "roles": [
        { "id": "simulated_patient", "processes": "text", "description": "Gera as falas do paciente simulado a partir do texto da conversa." }
      ]
    },
    {
      "id": "deepgram",
      "name": "Deepgram",
      "processes": "audio",
      "roles": [
        { "id": "speech_to_text", "processes": "audio", "description": "Transcreve a sua fala." }
      ]
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `providers[].id` | `anthropic`, `openai`, `typesafe`, `livekit`, `deepgram` or `cartesia`. |
| `providers[].processes` | `audio` when any of its roles receives audio, otherwise `text`. |
| `providers[].roles[].id` | `simulated_patient`, `patient_adjudicator`, `jev_verification`, `rubric_resolver`, `learner_feedback`, `audio_transport`, `speech_to_text` or `text_to_speech`. |
| `providers[].roles[].description` | What that provider does in the station, in pt-BR. |

With voice off (`voice_mode` `off`) no audio provider is listed.

### Session routes

Every operation is addressed by the session id; request and response bodies are
the ones of the operations table above.

| Route | Operation |
| --- | --- |
| `GET /sessions/:id` | Refresh: status, transcript, timer (`RefreshSession`); a session started here also returns `station`. |
| `POST /sessions/:id/messages` | A learner turn (`SendTurn`). |
| `POST /sessions/:id/impressos/request` | An impresso request (`RequestImpresso`). |
| `GET /sessions/:id/impressos` | Released impressos (`ListImpressos`). |
| `POST /sessions/:id/exam-mode`, `DELETE /sessions/:id/exam-mode` | Arm or cancel the [spoken exam request](#spoken-exam-requests-issue-364) (`ArmExamMode`, `CancelExamMode`). |
| `POST /sessions/:id/voice` | LiveKit credential (`RequestVoiceCredential`). |
| `POST /sessions/:id/transcribe`, `POST /sessions/:id/synthesize` | Turn-based voice (legacy HTTP audio). |
| `POST /sessions/:id/finish` | Finish (`FinishSession`). |
| `GET /sessions/:id/result` | The v2 educational result (`FetchResult`). |
| `POST /sessions/:id/discard` | Discard (`DiscardSession`). |

### Rate limits (issue #395)

The routes that call paid providers are throttled per session and per
learner: `POST .../messages` (`SendTurn`), `.../transcribe`, `.../synthesize`,
`.../voice` (`RequestVoiceCredential`), `.../impressos/request`
(`RequestImpresso`), `POST`/`DELETE .../exam-mode` and `GET .../result`
(`FetchResult`). The defaults (per minute, per session: 40 turns, 40
transcriptions, 30 syntheses, 10 voice credentials, 15 impresso requests, 20
exam-mode changes, 20 result fetches; per learner, twice that) sit well above
a human-paced station, so a client that waits for each answer before the next
request never meets them. Operators can change them (`RATE_LIMIT_<ACTION>_<KIND>`,
see the README).

Past a limit the route answers `429` with a `Retry-After` header (seconds)
and this body; the request did nothing and counts toward neither limit, so the client may resend it after
`Retry-After`, but never in a loop:

```json
{
  "error": "rate_limited",
  "message": "Muitas solicitações nesta sessão. Aguarde 12 s e tente novamente."
}
```

The voice worker's routes are never throttled, so a spoken turn is never
dropped by a limit.

### Deprecated active-station routes

`GET /api/stations/active`, `POST /api/stations/active/sessions` and the
`/api/stations/active/sessions/:id/...` and `/api/v2/stations/active/sessions/:id/result`
routes keep working until this client and the frozen web harness move to the
routes above. They are unauthenticated only in dev and test (for the frozen web
harness and the E2E suite); in production they need the access token, and the
per-session aliases serve only the learner's own sessions. In production there is no active station (stations come
only from the database), so `GET /api/stations/active` and
`POST /api/stations/active/sessions` answer `404 no_active_station` there.
`POST`/`DELETE /api/stations/active/sessions/:id/exam-mode` (#364) is the
alias this client uses for the spoken exam request until it has the device
login; then every call moves to `/sessions/:id/...` together.

`POST /api/stations/active/sessions` takes the same optional `mode` and answers
the same `invalid_parameters` and `audio_consent_required` errors.

The voice worker needs no change: it reads `GET /api/internal/voice/sessions/:id`,
which serves the language and speech-to-text keyterms of the session's own
pinned station.

## Training score (#323)

The result of a training adds, next to `estimates` (which overtime never
changes): `overtime_seconds` (whole seconds past `deadline_at`, `0` when the
learner finished within ten minutes), `overtime_penalty` (0.25 points per started
minute, at most `"2.5"`) and `training_score` (`estimates.total` minus the
penalty, never below `"0"`, `null` when `estimates.total` is `null`). Phoenix
computes them; the client only displays them. A real test result has none of
these fields.

## Results history (`GET /me/results`, issue #338)

Phoenix keeps the learner's Educational Results (ADR-014 #346, ADR-013
amendment on #209). There is no `UStationClient` method for it yet; a client
calls the routes directly.

- **What is stored:** the first time `GET /sessions/:id/result` serves a graded
  result for a learner's session, Phoenix stores that exact body with the
  station version and the finish date. Fetching the result again stores
  nothing new. A technical failure (`502 invalid_attempt`) stores nothing, so
  the attempt never appears. No audio and no transcript are stored: only the
  criteria, points, recommendations and the learner phrases cited as evidence.
- **Auth:** the device access token (`Authorization: Bearer <access_token>`),
  as on every station route; a missing or invalid token is `401`.
- **Scope:** only the learner's own results. Another learner's result is
  `404 result_not_found`, exactly like an unknown id.
- **No aggregate:** there is no total, average, trend, pass/fail or readiness
  signal across sessions. Each result keeps its own `estimates.total`, `null`
  when any active criterion is unresolved (ADR-012 #124). Show
  `educational_disclaimer` with the history and with every result.
- **Account deletion** deletes the history.

### List (`GET /me/results`)

Newest first (by `finished_at`). Query parameters, all optional:

| Parameter | Meaning |
| --- | --- |
| `area` | Only results of that `[ÁREA]` (the catalog's `area`, exact match). Blank means every area. |
| `page` | 1-based page, default `1` (at most `100000`). |
| `page_size` | Results per page, `1` to `100`, default `20`. |

`GET /me/results?area=Cirurgia%20Geral&page=1&page_size=20`

```json
{
  "results": [
    {
      "id": 41,
      "session_id": "Jp0qJouf20BUkSvGHbDCgA",
      "finished_at": "2026-10-25T15:09:12.482113Z",
      "station": {
        "id": 12,
        "version": 2,
        "slug": "acute-appendicitis",
        "area": "Cirurgia Geral",
        "theme": "Abdome agudo inflamatório — apendicite aguda",
        "display_title": "Abdome agudo inflamatório — apendicite aguda"
      }
    }
  ],
  "page": 1,
  "page_size": 20,
  "has_more": false,
  "educational_disclaimer": "Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame."
}
```

`has_more` is `true` when a next page exists. An invalid `page` or
`page_size` (not an integer, or out of range) is `400 invalid_parameters`.

### Detail (`GET /me/results/:id`)

The list entry's fields plus `result`, which is byte for byte the body
`GET /sessions/:id/result` served at the end of that session (see the v2
result of `FetchResult`), so the client can render it with the same view.

```json
{
  "id": 41,
  "session_id": "Jp0qJouf20BUkSvGHbDCgA",
  "finished_at": "2026-10-25T15:09:12.482113Z",
  "station": {
    "id": 12,
    "version": 2,
    "slug": "acute-appendicitis",
    "area": "Cirurgia Geral",
    "theme": "Abdome agudo inflamatório — apendicite aguda",
    "display_title": "Abdome agudo inflamatório — apendicite aguda"
  },
  "result": {
    "schema_version": "2",
    "session_id": "Jp0qJouf20BUkSvGHbDCgA",
    "status": "completed",
    "placeholder": false,
    "criteria": [
      {
        "id": "item-01",
        "description": "Apresenta-se ao paciente.",
        "status": "assessed",
        "level": "adequado",
        "level_description": "Apresentou-se e cumprimentou o paciente.",
        "max_points": "0.5",
        "points": "0.5",
        "evidence_ids": ["turn-1"],
        "evidence": [{ "id": "turn-1", "role": "learner", "text": "Bom dia, sou o doutor Pedro." }],
        "reason": null,
        "recommendation": "…"
      },
      {
        "id": "item-02",
        "description": "Caracteriza a dor abdominal.",
        "status": "uncertain",
        "max_points": "1.5",
        "evidence_ids": [],
        "evidence": [],
        "reason": "assessment_unresolved",
        "recommendation": "…"
      }
    ],
    "coverage": { "assessed": 1, "uncertain": 1, "not_observable": 0, "not_applicable": 0 },
    "estimates": {
      "total": null,
      "scored_subtotal": "0.5",
      "scored_max": "0.5",
      "eligible_max": "2",
      "unresolved": [{ "id": "item-02", "status": "uncertain" }]
    }
  },
  "educational_disclaimer": "Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame."
}
```

| Code | Status | When |
| --- | --- | --- |
| `result_not_found` | 404 | Unknown id, a non-numeric id, or another learner's result. |

## Who speaks in the voice room (`speaker`, issue #341)

A station may have a companion besides the patient (the catalog's `actors`,
`role: companion`). Both speak on the one patient voice track
(`patient-voice`); the voice worker publishes each reply sentence on the
room's `transcript` data topic, before its audio, and labels it with its
speaker. This is the field the Unreal client (#322) reads to drive the right
MetaHuman's lip sync and to name the speaker on screen.

```json
{
  "session_id": "Jp0qJouf20BUkSvGHbDCgA",
  "turn_id": 3,
  "generation_id": 3,
  "role": "patient",
  "speaker": "companion",
  "segment": 0,
  "text": "A febre começou há dois dias."
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `role` | string | Always `patient` for a spoken reply (kept for older clients); `examiner` for the acknowledgement events, which speak nothing. |
| `speaker` | string | `patient` or `companion`: the actor whose reply this is. Match it to the catalog `actors[].role`; a station has one actor of each role at most. Single-actor stations always send `patient`. |
| `segment` | integer | The sentence index within the reply, when Phoenix streams it sentence by sentence. |
| `text` | string | The verified sentence, without stage directions. |

- The audio that follows the event, until the next reply event, is that
  speaker's: each actor speaks with the Cartesia voice its voice key
  (`actors[].voice`) maps to in the worker's `CARTESIA_VOICE_IDS`
  (`voice-key=voice-id,...`); an unmapped key uses `CARTESIA_VOICE_ID`.
- The `status: "complete"` end event of a streamed reply carries no `speaker`.
- A worker built before #341 sends no `speaker`: read it as `patient`.
- The HTTP responses name the speaker too, as `"patient"` or `"companion"`; a
  reply with no stored speaker (any single-actor station) reads as `"patient"`:
  - the text reply of `POST /sessions/:id/messages` (`outcome: "patient_reply"`)
    carries `speaker`;
  - each `role: "patient"` message of the session transcript
    (`GET /sessions/:id`, `RefreshSession`) carries `speaker`; learner messages
    carry none;
  - the voice worker's non-streamed receipt (`status: "committed"` from
    `POST /api/internal/voice/sessions/:id/transcripts`) carries `speaker`. The
    streamed (`application/x-ndjson`) result line does not: its sentences
    already carry the speaker.

## Unavailable exam answers (issue #357)

When `RequestImpresso` names an exam the station has no impresso for, the
reply keeps `decision: "unavailable"`, releases nothing, and carries one of the
two answers the Revalida examiner gives in `feedback_message`. Show it as is:

| `feedback_message` | When |
| --- | --- |
| `Considere solicitado.` | The exam makes clinical sense for the case but is not in the checklist. It earns no points. |
| `Não consta no script.` | The exam makes no sense for the case, or Phoenix could not decide. |

No new decision value exists, so the parser in `StationJson.cpp` needs no
change. Retrying with the same `RequestId` returns the same text.

## Exam requests in the dialogue (issue #351)

Exam findings and impressos are released only by the exam button, which calls
`POST /sessions/:id/impressos/request` (`RequestImpresso`). A dialogue turn
(`SendTurn`, or a voice turn) never releases an impresso nor records an
impresso request, even when it names an exam. When the learner asks the
examiner for an exam in the dialogue, Phoenix says so, so the client can show
a hint pointing to the button.

An examiner-addressed text reply of `POST /sessions/:id/messages`:

```json
{
  "outcome": "examiner_acknowledged",
  "reply_text": null,
  "reply_audio_url": null,
  "learner_turn": {"role": "learner", "modality": "text", "text": "Solicito hemograma e PCR"},
  "newly_released": [],
  "exam_request": true,
  "server_now": "2026-10-25T14:03:11.204Z"
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `exam_request` | boolean | `true` when the learner asked for a physical exam, a maneuver, a complementary exam or a result, authored by the station or not; `false` when the learner only told the examiner what was done, found, concluded or planned. Display-only: show a hint pointing to the exam button. It releases nothing and is not graded; a wrong flag only shows or hides the hint. |
| `newly_released` | array | Always empty for a dialogue turn; kept for older clients. |

- A `patient_reply` response carries no `exam_request`; read it as `false`.
- The voice worker's receipt of an examiner-addressed voice turn
  (`status: "kept"`, `addressee: "examiner"`, from
  `POST /api/internal/voice/sessions/:id/transcripts`, streamed or not) carries
  the same `exam_request`. The worker does not forward it yet: its room event
  stays `{role: "examiner", status: "acknowledged"}` (#191/#194 open question).
- `FStationTurnReply` (`StationJson.cpp`) does not parse `exam_request` yet;
  the field is an addition, so the current parser keeps working.

## Spoken exam requests (issue #364)

In a voice run the exam button asks for the exam aloud: the learner presses
it, then says the request ("Solicito hemograma e PCR"). The spoken request goes
to the same impresso request as `RequestImpresso`, never to the patient.

1. On the press, call `POST /sessions/:id/exam-mode` (bearer token; no body).
   Phoenix arms an exam mode for the learner's next utterance:

   ```json
   {"status": "armed", "expires_at": "2026-10-25T14:03:31.204Z", "server_now": "2026-10-25T14:03:11.204Z"}
   ```

2. The learner speaks. The voice worker posts the final transcript to Phoenix
   as for any turn; Phoenix sees the armed mode and sends the text through the
   impresso request (the same keyword matcher and negation handling as a typed
   request), records an `impresso_requests` event with request id
   `voice-exam-<turn_id>` and records no dialogue turn. The patient
   generation never sees the request, now or later, and nothing is spoken.
3. The worker publishes the outcome on the room's `transcript` data topic (see
   the event below); read the released impressos with `ListImpressos`, as
   after a typed request.

The mode disarms after that one utterance, at `expires_at` (20 seconds after
the press by default) or on `DELETE /sessions/:id/exam-mode` (`200`,
`{"status": "disarmed"}`; also when nothing was armed), e.g. when the learner
closes the exam prompt without speaking. Pressing again re-arms it and
restarts the expiry. An utterance the learner finishes after `expires_at` is a
dialogue turn: an exam it names releases nothing ([#351](#exam-requests-in-the-dialogue-issue-351)).

The room event of a spoken exam request (`transcript` topic, published by the
worker, nothing spoken):

```json
{
  "session_id": "Jp0qJouf20BUkSvGHbDCgA",
  "turn_id": 4,
  "role": "examiner",
  "status": "impresso_requested",
  "request_id": "voice-exam-4",
  "decision": "released",
  "newly_released": [
    {"id": "laboratorio-sangue-enzimas", "title": "IMPRESSO — EXAMES LABORATORIAIS", "category": "laboratory"}
  ],
  "feedback_message": "Impresso liberado: IMPRESSO — EXAMES LABORATORIAIS"
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `status` | string | `impresso_requested`: the utterance was the exam request, not a dialogue turn. |
| `request_id` | string | `voice-exam-<turn_id>`, the id of the recorded `impresso_requests` event. |
| `decision` | string | As `RequestImpresso`: `released`, `already_released` or `unavailable` (an exam the station does not author, or a declined request). |
| `newly_released` | array | The impressos this request released: `id`, `title`, `category`, without `content`; read the content with `ListImpressos`. |
| `feedback_message` | string | The pt-BR line a typed request shows ("Impresso liberado: ...", "Considere solicitado.", "Não consta no script."). |

- Show the outcome as after a typed request: `feedback_message`, then
  `ListImpressos` for what was released.
- The event carries no `generation_id` and no `text`; no audio follows it.
- A barge-in does not drop it: when the learner speaks again before Phoenix's
  answer reaches the worker, the worker still publishes the event of the
  earlier turn (#432), so it can arrive after a `Learner` event of a newer turn.
  `UStationRunFlow` remembers each spoken exam request that newer speech
  superseded, with what the learner asked for, and takes that late event as the
  request's outcome, even after the learner cut a later reply (#434). It still
  ignores every other late event of an earlier turn.
- When the room event is lost (a publish error), the request is still
  recorded: `ListImpressos` shows it.

`ParseStationVoiceEvent` reads this event as `ExaminerImpresso`, with the
decision in `Impresso` (no `ReleasedImpressos`, and `NewlyReleased` without
`Content`). In `UStationRunFlow`, a text training types its exam requests;
a voice training whose voice and microphone work says them aloud
(`ShouldRequestExamsAloud`) while the learner holds the microphone in the
"Exames solicitados" panel: pressing arms the mode (`AskExamAloud`),
releasing goes back to the dialogue (`ReleaseExamAloud`). A request already
started when the button is released stays the request; if nothing was heard
yet, the mode listens two more seconds for the first caption and is then
disarmed. The utterance that takes the mode shows in the exam panel as a
card marked "Solicitando...", never in the conversation; its
outcome joins `GetExamRequests` as a typed request's does, and the flow reads
`ListImpressos` again. A press while that request still waits is refused
(`AskExamAloud` returns false) and the HUD shows it as waiting, never as
recording. A request superseded by newer speech is let go: the panel stops
showing it as waiting, `ListImpressos` is read again, and the mode passes to
the next utterance while it still listens. Its outcome still joins
`GetExamRequests` if it arrives later (#434); the newer utterance keeps its own
state, and Phoenix answers it as dialogue when the first request used the mode.
If the voice is lost while a spoken request waits, its outcome can no longer
arrive: the request is let go, and `ListImpressos` is read again. If Phoenix
answers that utterance as dialogue instead (it ended after `expires_at`), its
learner line joins the conversation before the reply.

- Errors: `403 no_consent` on a run without audio consent (a typed request
  needs no exam mode), `409 session_completed`, `404 session_not_found`,
  `410 session_expired`.
- Typed requests (`RequestImpresso`) are unchanged and do not touch the mode.
  They exist only in a training: a simulated exam refuses them (see
  [a simulated exam is voice only](#a-simulated-exam-is-voice-only-issue-422)).
- The learner's LiveKit token still has no data-publishing grant: the mode is
  set over HTTP and only the worker publishes room events.
- An utterance the learner was already speaking when the button was pressed
  may be the one that consumes the mode; arm it before the learner starts the
  request.

## A simulated exam is voice only (issue #422)

A simulated exam ("Prova simulada") takes no typed input. Phoenix refuses it
before anything is recorded, with `403 typed_input_not_allowed` and a pt-BR
`message`:

| Call | `message` |
| --- | --- |
| `SendTurn(Text, EStationTurnModality::Text)` | "A prova simulada é feita só por voz: o texto digitado não é aceito." |
| `RequestImpresso(Text, RequestId)` | "Na prova simulada os impressos são pedidos por voz, pelo botão Exames." |

- Nothing joins the conversation and no impresso request is recorded.
- A voice turn and the [spoken exam request](#spoken-exam-requests-issue-364)
  (`ArmExamMode`, then the next utterance) are unchanged. Phoenix records that
  request as the same verified impresso event the rubric uses.
- An examiner-addressed dialogue turn releases no impresso, in every mode
  ([#351](#exam-requests-in-the-dialogue-issue-351)).
- A training accepts both typed calls, as before.

What the client does:

- `UStationRunFlow::AllowsTypedInput()` is false in a simulated exam, so
  `CanSendTurn` and `CanRequestExam` are false and `SendTypedTurn` and
  `RequestExam` send nothing. `CanAskExamAloud` does not depend on it.
- The HUD hides the typed turn (`TurnRow`) and the typed exam box
  (`ExamTypedRow`) for the whole run. The exam panel only names the microphone.
- Without its voice a simulated exam takes no input at all, so the flow
  invalidates it (#318 business rule 8: no result and no penalty, and the
  learner can start again). That happens when `RequestVoiceCredential` fails
  (the run never goes on in writing, `IsVoiceFallback` stays false), when the
  voice is lost (a `Fatal` event or a failed room) and when the microphone
  will not open. `GetInvalidation` is then `EStationInvalidation::VoiceLost`
  (`PhoenixLost` when Phoenix stops answering), and the invalidated screen
  names the mode and the reason (`StationInvalidatedTitle`,
  `StationInvalidatedText`). A training still goes on in writing (#196).
- If Phoenix still refuses a typed call, `StationErrorText` shows its
  `message`, as for any Phoenix error.

## The Prova simulada exam room (issue #425)

A simulated exam looks and sounds like the official exam room (#318 business
rule 3, T3 and T3b). Phoenix is unchanged: it still serves `deadline_at` and
`server_now`, and still answers an examiner-addressed remark with
`outcome: "examiner_acknowledged"`, keeping the turn as evidence.

What the client does in a simulated exam:

- **No countdown.** `UStationRunFlow::ShowsStationTimer()` is false, so the HUD
  hides the Station Timer and names the run "Prova simulada". The flow still
  ends the run at zero, as before.
- **Desk clock.** `AStationDeskClock`, a scene object on the office desk, is an
  analog clock with hands that shows the time of day, never a countdown. The
  player controller sets it every frame from `UStationRunFlow::GetDeskClockTime()`:
  Phoenix's clock (`UStationClient::GetServerTime`) in the machine's time zone,
  or the machine's clock before Phoenix has sent a `server_now`. The client
  never computes a deadline. The clock is there in trainings too, as furniture.
- **Start and end sounds.** `UStationRunFlow::OnExamCue` broadcasts `Start` when
  the run starts running and `End` when it ends because the time is up
  (`FinishSession` with `timer`, from the Station Timer or because Phoenix ended
  the run), once per run. An early finish and an invalidated run sound nothing.
  The desk clock plays them (`S_ExamStart`, `S_ExamEnd`).
- **Silent examiner.** `examiner_acknowledged` leaves `GetVoice().bExaminerNoted`
  false, so the HUD shows no "Examinador: Anotado."; the remark stays in the
  conversation.
- **Brief once the time runs.** `CanReadBrief()` is false on a simulated exam's
  brief, which shows only the way in and says the scenario and tasks appear with
  the time already running. Once the run is running, the brief opens over the
  room (`IsBriefOpen`); **Voltar ao consultório** closes it (`CloseBrief`) and
  the HUD's **Cenário e tarefas** opens it again (`OpenBrief`).

A training is unchanged: the countdown, "Anotado.", the brief before the run,
and no sounds.

## Not in the interface yet

The [device login](#learner-login-device-flow) and the bearer header (#337) have
no `UStationClient` method yet: the module must add them before it can call the
authenticated routes in production.

The [results history](#results-history-get-meresults-issue-338) (`GET /me/results`,
`GET /me/results/:id`) has no `UStationClient` method yet either.

## Voice link (LiveKit)

From #191 the module also joins the run's LiveKit room. `UStationClient::ConnectVoice`
takes a credential from `RequestVoiceCredential` and returns an `FStationVoiceLink`
(`StationVoice.h`):

```cpp
Client->RequestVoiceCredential([WeakClient](const TStationResult<FStationVoiceCredential>& Credential)
{
	if (!WeakClient.IsValid() || !Credential.HasValue())
	{
		return;
	}
	FStationVoiceHandlers Handlers;
	Handlers.OnEvent = [](const FStationVoiceEvent& Event) { /* show captions and replies */ };
	Handlers.OnStateChanged = [](EStationVoiceState State) { /* mic indicator */ };
	Handlers.OnPatientPcm = [](TConstArrayView<int16> Pcm, int32 Rate, int32 Channels) { /* play, lip sync */ };

	// The link exists only from here, and ConnectVoice returns nullptr without a session.
	// Keep the shared reference it returns as a weak one: GetVoice() is a raw pointer the
	// game thread may free when it replaces or drops the link, so the capture thread must
	// not use it (the game's UStationMicrophone::Start takes this weak reference).
	if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Voice = WeakClient->ConnectVoice(Credential.GetValue(), MoveTemp(Handlers)))
	{
		Microphone->Start(Voice);  // takes a TWeakPtr<FStationVoiceLink, ESPMode::ThreadSafe>; pins it on the capture thread
	}
});

// Then, from the capture thread (WeakVoice is the weak reference the microphone holds):
if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Voice = WeakVoice.Pin())
{
	Voice->PushMicrophonePcm(Samples, Rate, Channels);
}
```

| Topic | Rule |
| --- | --- |
| Microphone | Whatever the caller pushes with `PushMicrophonePcm`: float samples, any rate and channel count. The link resamples to 48 kHz mono, cancels the echo of the patient's voice, then publishes a microphone-source track as `learner-<session>`, which is the only track the voice worker reads. Audio pushed while the state is not `WaitingForWorker` or `Ready` is dropped. |
| Push-to-talk | The microphone starts closed (#419): the track is published as `push-to-talk`, then muted at once, and pushed audio is dropped. The voice worker treats only a learner microphone with that name as push-to-talk; the web client's keeps its default name, so the mutes its browser makes on its own change nothing. `SetMicrophoneOpen(true)` unmutes it while the learner holds the talk key; `SetMicrophoneOpen(false)` mutes it again. The voice worker hears an unmute as a press, which stops the patient at once, and a mute as the release: it asks Deepgram to finalize and ends the turn once the transcript is quiet (0.3 s, at most 1.5 s), instead of waiting for Deepgram's end of speech. The learner token cannot publish data (#364), so the mute is the only signal. `UStationRunFlow::PressTalkKey`/`ReleaseTalkKey` drive it and keep it open for 150 ms after the release, so the last word reaches the worker before the mute. |
| States | `Connecting`, then `WaitingForWorker` once the microphone is published, then `Ready` when the `voice-worker` participant is in the room. `Reconnecting` while LiveKit retries the room connection, or once the worker that joined has left; the link returns to `Ready` if both come back. `Failed` (with `GetFailure()`, English, for logs) when joining or publishing fails, when the link is still `Connecting` 30 seconds after `Connect` (#448), when LiveKit drops the room, when the worker has not joined 20 seconds after the microphone was published, or after 10 seconds of `Reconnecting`. `Failed` is final: nothing more is heard or sent from that moment, and the link leaves the room in the background, once any SDK call under way returns. |
| Events | `OnEvent` gets the worker's `transcript` data messages, parsed as strictly as the web client does. Messages for another session, or from anyone but `voice-worker`, are dropped. The kinds are `Learner` (`bFinal` false for an interim caption), `PatientText` (one sentence, `Segment`), `PatientComplete`, `ExaminerAcknowledged`, `PatientUnanswered`, `TurnFailure` and `Fatal`. |
| Patient voice | `OnPatientPcm` runs on a LiveKit thread every 10 ms of the worker's `patient-voice` track. It must not block. |
| Same reply | The worker sends a reply's text before its audio, and both are the text Phoenix approved and stored for the run. |
| Typed turns | In a run with audio consent, the worker also speaks the reply Phoenix approved for a `SendTurn` typed turn, on the same `patient-voice` track (#325). No `transcript` event comes with it: the text is the `FStationTurnReply` answer, which stays text-only. Phoenix sends the reply to the worker alone, and the worker speaks it only while it is current: never once the learner has spoken a later turn, and it stops when the learner speaks over it, as a spoken reply does. `UStationRunFlow` calls `Resume` when the typed turn's reply arrives, unless a `Learner` event of a newer turn came after the turn was sent. |
| Barge-in | A `Learner` event with text for a newer turn means the learner spoke over the patient: the worker has already stopped the patient's voice and cancelled any turn Phoenix had not settled. `UStationRunFlow` then calls `FStationPatientOutput::Silence`, and `Resume` with the next `PatientText` while the run is going on, so audio still buffered or in flight never plays (#193). Finishing silences it too, and nothing resumes it while Phoenix closes the run; so does an invalidated run (#196). A turn without an outcome (`PatientComplete`, a whole reply, `ExaminerAcknowledged` or `PatientUnanswered`) leaves the conversation with its partial reply. Events of an earlier turn arrive late and are ignored. |
| Run end | The link leaves the room when `FinishSession` succeeds, when `DiscardSession` or `ForgetSession` is called, when `RefreshSession` sees the run completed, on `DisconnectVoice`, and when the client is destroyed. Leaving returns at once and finishes in the background, even while a join still hangs on an unreachable server (about 30 s). No game-thread handler runs after that; an `OnPatientPcm` call already under way may finish, so its target must outlive it or cut itself off. A refused finish (`deadline_not_reached`) keeps the link. The link does not notice a run that ended on Phoenix's side until `RefreshSession` or `FinishSession` reports it. |
| LiveKit SDK | The module initialises the SDK on first use, or reuses it when another module (the #189 spike) did. On quit it waits up to 2 s for each room still being left. |
| Privacy | The module logs no transcript or reply text and keeps none: events go straight to the handlers. |
| Threading | `ConnectVoice`, `DisconnectVoice` and the state run on the game thread, as do `OnEvent` and `OnStateChanged`. |

Known limits:

- One link at a time: `ConnectVoice` replaces the open one.
- The credential lasts 120 s. That is enough to join, and a joined room stays joined. A link that fails is not retried: ask for a new credential and connect again.
- The echo canceller uses the patient's voice as LiveKit delivers it. The delay of the game's own playback is left to the canceller to estimate.

## Tests

The module's automation tests live in
`unreal/Source/StationClient/Private/Tests/StationClientSpec.cpp`:

- `ProyectoMed.StationClient.Unit` needs nothing else.
- `ProyectoMed.StationClient.Phoenix` needs a local Phoenix with the LiveKit
  development values (LiveKit itself does not need to run; Phoenix only signs
  the token):

```bash
( cd backend && VOICE_MODE=realtime LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret mix phx.server )
```

Then, with the editor closed:

```bash
scripts/run-unreal-tests.sh ProyectoMed.StationClient
```

Set `STATION_PHOENIX_URL` to test against another Phoenix. The runner fails when
no test matches the filter.

`ProyectoMed.StationVoice.Unit` needs nothing else. `ProyectoMed.StationVoice.Stack`
drives a full spoken turn through LiveKit and the real voice worker. It needs the
local voice stack, which brings its own Phoenix (see README, "Voice worker fake
speech providers"):

```bash
scripts/run-voice-stack.sh -- scripts/run-unreal-tests.sh "ProyectoMed.StationVoice+ProyectoMed.StationRun.Voice+ProyectoMed.PatientVoice"
```

The stack's Phoenix answers with the mock patient ("Meu nome é Carlos."), not the
scripted one ("Bom dia, doutor."), so the whole suite takes two runs: the voice
specs above inside the stack, and the rest against the scripted Phoenix of the
previous section:

```bash
scripts/run-unreal-tests.sh "ProyectoMed.StationClient+ProyectoMed.StationRun.Phoenix+ProyectoMed.StationRun.Unit"
```

`ProyectoMed.StationRun.Unit.PhoenixLoss` (in `StationRunPhoenixLossSpec.cpp`)
needs nothing else either: it serves a fake Phoenix on port 18766 that can leave
one call unanswered while it still answers the check after it, which a real
Phoenix cannot be made to do, and it uses `http://127.0.0.1:9` for a Phoenix
that answers nothing. It covers each failure of a training that loses Phoenix
(#196). Like `ProyectoMed.StationClient.FakePhoenix`, it starts the editor's
HTTP listeners, so an editor already open on the same machine makes it fail
with "HttpListener unable to bind to 127.0.0.1:8000" (the Model Context
Protocol server): close that editor first.

`ProyectoMed.StationHud.Unit` (in `StationHudSpec.cpp`) needs nothing else: it
checks what the in-run HUD shows for a given run, such as the exam panel's
empty hint after the voice is lost, the request cards' document links, the
document reader's lines, and that the conversation is redrawn only when it
changes.

`ProyectoMed.StationHud.Snapshot` (in `StationHudSnapshotSpec.cpp`) renders the
in-run HUD in chosen states (exam panel closed and open, recording, the
document reader, a text training) to PNG files, to judge its look without
playing a run to each state. It asserts nothing about the look, needs an RHI
(the runner's `-nullrhi` skips it), and writes only when
`STATION_HUD_SNAPSHOT_DIR` names a folder:

```bash
STATION_HUD_SNAPSHOT_DIR=/tmp/hud "/Users/Shared/Epic Games/UE_5.8/Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor" \
  "$PWD/unreal/ProyectoMed.uproject" -ExecCmds="Automation RunTests ProyectoMed.StationHud.Snapshot; Quit" -unattended -nosplash -nosound
```

`ProyectoMed.StationCards.Snapshot` (in `StationCardSnapshotSpec.cpp`) does the
same for the full-screen cards around the run: the microphone disclosure, the
main menu (#421), the Pre-Station Notice, a training's brief (loaded, microphone
blocked, loading, failed), a simulated exam's brief (ready, microphone blocked,
no realtime voice), the invalidated run and the feedback (grading, graded,
scrolled to the end). It writes to the same `STATION_HUD_SNAPSHOT_DIR`; run it
with `-ExecCmds="Automation RunTests ProyectoMed.StationCards.Snapshot; Quit"`.
`ProyectoMed.StationCards.Unit` (in `StationBriefSpec.cpp`) checks what the main
menu and each mode's brief offer, and needs nothing else.

The stack test checks four things:

- The worker transcribes the pushed speech.
- The patient's sentence and the end of the reply belong to that turn.
- The patient's voice arrives.
- The sentence equals the reply Phoenix stored for the run.

It also checks that the room is left on finish and on discard. The neutral refusal
("Não consta no script.") is Phoenix's job and its tests cover it
(`backend/test/backend/station_ai_test.exs`). The client shows any approved reply
verbatim.

The Phoenix tests cover the deterministic paths: station, session lifecycle,
voice credential, impressos, finish and the errors above. An educational result
needs Phoenix's text provider (`LLM_PROVIDER` and its key), so its parsing is
covered by unit tests on Phoenix's real response shapes. The E2E approving Jev
adapter below is the seam that grades a run without one (#195).

A full patient turn has that seam (#192). `ProyectoMed.StationRun.Phoenix` sends
typed turns and expects Phoenix's scripted patient, a dev-only adapter that
answers every turn with "Bom dia, doutor." Start Phoenix with it and with the
E2E approving Jev adapter:

```bash
( cd backend && VOICE_MODE=realtime LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret JEV_E2E_APPROVING_ADAPTER=true STATION_AI_E2E_SCRIPTED_ADAPTER=true mix phx.server )
```

Both variables are honored only under `MIX_ENV=dev`. Never set them for a
clinician or a learner session: the patient then says nothing from the case.

The same spec covers exam and impresso requests (#194) through
`UStationRunFlow::RequestExam`, which needs no adapter: Phoenix's impresso route
matches keywords without a model. Those tests expect the default station
(`chest-pain-initial-assessment`), so leave `ACTIVE_STATION_ID` unset: it authors
the physical exam and an ECG, and no tomography, which the tests ask for to see
a declined request.

Finishing a run and its feedback (#195) are covered through
`UStationRunFlow::Finish`, `ExpireTimer` and `Discard`. They read the result the
E2E approving Jev adapter grades: it cites the learner's first line for every
criterion it can ground, so the tests check that a criterion cites the typed
turn. A timer finish is tested before Phoenix's deadline, where Phoenix refuses
it and the run goes on, and on a run Phoenix already ended, which is what Phoenix
does itself at the deadline: the tests end it through `FinishSession` instead of
waiting ten minutes. A turn or exam request Phoenix refuses with
`station_time_elapsed` or `session_completed` ends the run the same way.

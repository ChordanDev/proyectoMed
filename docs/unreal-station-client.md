# Unreal station client module

`StationClient` (`unreal/Source/StationClient/`) is the one module in the Unreal
client that talks to Phoenix, and from #191 to LiveKit. Scene and interface code
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
| One run at a time | The client holds at most one session. `StartSession` fails with `session_in_progress` until `DiscardSession` succeeds. |
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
- At zero, call `FinishSession(EStationFinishReason::Timer)`. If Phoenix answers
  `deadline_not_reached` (409), the local clock ran ahead: call `RefreshSession`
  and keep counting.

## Operations

All operations are methods of `UStationClient`. Each one takes a
`TStationCallback<T>`, which receives a `TStationResult<T>`: a value, or an
`FStationClientError`.

| Method | Phoenix route | Value on success | Main consumer |
| --- | --- | --- | --- |
| `FetchActiveStation` | `GET /api/stations/active` | `FStationSummary`: title, candidate brief, voice mode | #190 |
| `StartSession(bAudioConsent)` | `POST /api/stations/active/sessions` | `FStationSession`; starts the Station Timer | #190 |
| `RefreshSession` | `GET .../sessions/:id` | `FStationSession` with status and transcript (`Messages`) | #195, #196 |
| `RequestVoiceCredential` | `POST .../sessions/:id/voice` | `FStationVoiceCredential` for one LiveKit room | #190, #191 |
| `SendTurn(Text, Modality)` | `POST .../sessions/:id/messages` | `FStationTurnReply`: the approved patient reply, or an examiner acknowledgement with released impressos | #191, #192, #194 |
| `RequestImpresso(Text, RequestId)` | `POST .../sessions/:id/impressos/request` | `FStationImpressoReply`: the decision and what was released | #194 |
| `ListImpressos` | `GET .../sessions/:id/impressos` | Every impresso released so far | #194 |
| `FinishSession(Reason)` | `POST .../sessions/:id/finish` | `FStationSession` marked completed | #195 |
| `FetchResult` | `GET /api/v2/.../sessions/:id/result` | `FStationResult`: criteria with transcript evidence | #195 |
| `DiscardSession` | `POST .../sessions/:id/discard` | Nothing; the local session is cleared only after Phoenix confirms | #195, #196 |

Synchronous accessors: `GetSession()` (null without a run), `GetRemainingTime()`
(and `GetRemainingTimeAt(LocalSeconds)` for tests), `GetPhoenixBaseUrl()` and
`SetPhoenixBaseUrl()`. `FStationClock` is the public helper behind the timer.

Known limits, for the slices that build on them:

- A run whose `StartSession` is still in flight when the game quits is not
  discarded; Phoenix forgets it after 30 minutes.

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
- `RefreshSession` never reopens a run this client saw finish: an answer read
  before the finish keeps the run completed, with its completion time.

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
| `session_completed` | 422, 409 | `SendTurn` and `RequestVoiceCredential` (422); `RequestImpresso` (409) |
| `station_time_elapsed` | 409 | `SendTurn` after the deadline |
| `deadline_not_reached` | 409 | `FinishSession(Timer)` called early |
| `no_consent` | 403 | `RequestVoiceCredential` on a run without audio consent |
| `voice_unavailable` | 503 | `RequestVoiceCredential` when Phoenix has no LiveKit set up |
| `rate_limited` | 429 | `RequestVoiceCredential` more than 5 times a minute |
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
  "status": "active",
  "voice_mode": "realtime",
  "started_at": "2026-10-25T15:00:00Z",
  "expires_at": "2026-10-25T15:30:00Z",
  "deadline_at": "2026-10-25T15:10:00Z",
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
| `invalid_parameters` | 400 | No station choice, both `station_id` and `random`, a `station_id` that is not a positive integer, a non-string `area`, or a missing or non-boolean `audio_consent`. |
| `station_not_found` | 404 | No published station has that `station_id` (unknown, pending or disapproved case). |
| `no_published_station` | 404 | Nothing is published in that `area` (or at all, without one). |
| `station_unavailable` | 503 | The published package could not be loaded; the run cannot start. |

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
| `providers[].id` | `anthropic`, `openai`, `typesafe`, `livekit`, `deepgram` or `elevenlabs`. |
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
| `POST /sessions/:id/voice` | LiveKit credential (`RequestVoiceCredential`). |
| `POST /sessions/:id/transcribe`, `POST /sessions/:id/synthesize` | Turn-based voice (legacy HTTP audio). |
| `POST /sessions/:id/finish` | Finish (`FinishSession`). |
| `GET /sessions/:id/result` | The v2 educational result (`FetchResult`). |
| `POST /sessions/:id/discard` | Discard (`DiscardSession`). |

### Deprecated active-station routes

`GET /api/stations/active`, `POST /api/stations/active/sessions` and the
`/api/stations/active/sessions/:id/...` and `/api/v2/stations/active/sessions/:id/result`
routes keep working until this client and the frozen web harness move to the
routes above. They are unauthenticated only in dev and test (for the frozen web
harness and the E2E suite); in production they need the access token, and the
per-session aliases serve only the learner's own sessions. In production there is no active station (stations come
only from the database), so `GET /api/stations/active` and
`POST /api/stations/active/sessions` answer `404 no_active_station` there.

The voice worker needs no change: it reads `GET /api/internal/voice/sessions/:id`,
which serves the language and speech-to-text keyterms of the session's own
pinned station.

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
  speaker's: each actor speaks with the ElevenLabs voice its voice key
  (`actors[].voice`) maps to in the worker's `ELEVENLABS_VOICE_IDS`
  (`voice-key=voice-id,...`); an unmapped key uses `ELEVENLABS_VOICE_ID`.
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

## Not in the interface yet

The [device login](#learner-login-device-flow) and the bearer header (#337) have
no `UStationClient` method yet: the module must add them before it can call the
authenticated routes in production.

Joining the LiveKit room (publishing the microphone, receiving the patient voice
track and driving lip sync) lands with #191 as an addition owned by the
ChordanDev track; the #189 spike (`unreal/Source/PatientVoiceSpike/`) shows the
pieces. Typed and exam slices (#192, #194, #195) do not depend on it.

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

The Phoenix tests cover the deterministic paths: station, session lifecycle,
voice credential, impressos, finish and the errors above. A patient reply and an
educational result need Phoenix's text provider (`LLM_PROVIDER` and its key), so
their parsing is covered by unit tests on Phoenix's real response shapes. A slice
that needs a full turn or result against local Phoenix in CI adds that seam to
Phoenix first, as #190 asks.

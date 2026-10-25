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
| Secrets | `FStationVoiceCredential::Token` is a secret: never log or display it. The session id is the run's only credential. |
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
| `session_not_found` | 404 | every session route |
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

## Not in the interface yet

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

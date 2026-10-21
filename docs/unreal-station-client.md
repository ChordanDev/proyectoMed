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

Client->StartSession(/*bAudioConsent*/ true, [Client](const TStationResult<FStationSession>& Result)
{
	// From here, Client->GetRemainingTime() counts down the Station Timer.
});
```

Build-file dependency: add `"StationClient"` to the consuming module's
`PrivateDependencyModuleNames`.

## Rules every consumer can rely on

| Topic | Rule |
| --- | --- |
| Threading | Every callback runs on the game thread, exactly once. A call refused locally (for example `no_session`) calls back before it returns. |
| Timeouts | A request Phoenix does not answer within 15 s fails with `network_error`. |
| One run at a time | The client holds at most one session. `StartSession` fails with `session_in_progress` until `DiscardSession` succeeds. |
| Content | The client holds no clinical rules and no Station Package content. Everything it returns is what Phoenix served for this run. |
| Secrets | `FStationVoiceCredential::Token` is a secret: never log or display it. The session id is the run's only credential. |
| Configuration | Phoenix's origin comes from `[/Script/StationClient.StationClient] PhoenixBaseUrl` in the game config (default `http://127.0.0.1:4000`), or `-PhoenixUrl=<origin>` on the command line. |

## Station Timer

Phoenix owns the duration: `deadline_at` is fixed when the session starts (ten
minutes today). The client anchors Phoenix's `server_now` to the local monotonic
clock, so `GetRemainingTime()` is correct whatever the machine clock says.

- It returns zero before a run, after the deadline, and once the run is completed.
- `RefreshSession` re-anchors the clock to Phoenix.
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

- `FStationSession::CompletedAt` is set only by `FinishSession`; Phoenix's show
  body has no `completed_at`, so a later `RefreshSession` clears it.
- A `RefreshSession` sent before `FinishSession` but answered after it can
  replace the completed session with the active one it read. Avoid overlapping
  them until #195 settles the finish flow.
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
  taken the turn: call `RefreshSession` and check the transcript before resending.
- `RefreshSession` skips transcript lines whose speaker the client does not know.

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
controllers for the full list):

| Code | Status | Raised by |
| --- | --- | --- |
| `session_not_found` | 404 | every session route |
| `session_expired` | 410 | every session route |
| `session_completed` | 422 | `SendTurn`, `RequestVoiceCredential` |
| `station_time_elapsed` | 409 | `SendTurn` after the deadline |
| `deadline_not_reached` | 409 | `FinishSession(Timer)` called early |
| `no_consent` | 403 | `RequestVoiceCredential` on a run without audio consent |
| `voice_unavailable` | 503 | `RequestVoiceCredential` when Phoenix has no LiveKit set up |
| `rate_limited` | 429 | `RequestVoiceCredential` more than 5 times a minute |
| `reply_verification_failed`, `station_ai_unavailable`, `timeout` | 502, 504 | `SendTurn` |
| `session_not_finished` | 422 | `FetchResult` before `FinishSession` |
| `invalid_attempt` | 502 | `FetchResult` when the run could not be assessed |

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

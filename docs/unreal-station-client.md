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
	// game thread may free when it replaces or drops the link, so the capture source
	// (the game's microphone component arrives with the voice training slice) must not use it.
	if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Voice = WeakClient->ConnectVoice(Credential.GetValue(), MoveTemp(Handlers)))
	{
		WeakVoice = Voice;  // pin WeakVoice, a TWeakPtr<FStationVoiceLink, ESPMode::ThreadSafe>, in the capture source
	}
});

// Then, from the capture thread:
if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Voice = WeakVoice.Pin())
{
	Voice->PushMicrophonePcm(Samples, Rate, Channels);
}
```

| Topic | Rule |
| --- | --- |
| Microphone | Whatever the caller pushes with `PushMicrophonePcm`: float samples, any rate and channel count. The link resamples to 48 kHz mono, cancels the echo of the patient's voice, then publishes a microphone-source track as `learner-<session>`, which is the only track the voice worker reads. Audio pushed while the state is not `WaitingForWorker` or `Ready` is dropped. |
| States | `Connecting`, then `WaitingForWorker` once the microphone is published, then `Ready` when the `voice-worker` participant is in the room. `Reconnecting` while LiveKit retries the room connection, or once the worker that joined has left; the link returns to `Ready` if both come back. `Failed` (with `GetFailure()`, English, for logs) when joining or publishing fails, when LiveKit drops the room, when the worker has not joined 20 seconds after the microphone was published, or after 10 seconds of `Reconnecting`. `Failed` is final: the link leaves the room at once, so nothing more is heard or sent. |
| Events | `OnEvent` gets the worker's `transcript` data messages, parsed as strictly as the web client does. Messages for another session, or from anyone but `voice-worker`, are dropped. The kinds are `Learner` (`bFinal` false for an interim caption), `PatientText` (one sentence, `Segment`), `PatientComplete`, `ExaminerAcknowledged`, `PatientUnanswered`, `TurnFailure` and `Fatal`. |
| Patient voice | `OnPatientPcm` runs on a LiveKit thread every 10 ms of the worker's `patient-voice` track. It must not block. |
| Same reply | The worker sends a reply's text before its audio, and both are the text Phoenix approved and stored for the run. |
| Run end | The link leaves the room when `FinishSession` succeeds, when `DiscardSession` is called, when `RefreshSession` sees the run completed, on `DisconnectVoice`, and when the client is destroyed. Leaving returns at once and finishes in the background, even while a join still hangs on an unreachable server (about 30 s). No game-thread handler runs after that; an `OnPatientPcm` call already under way may finish, so its target must outlive it or cut itself off. A refused finish (`deadline_not_reached`) keeps the link. The link does not notice a run that ended on Phoenix's side until `RefreshSession` or `FinishSession` reports it. |
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
scripts/run-voice-stack.sh -- scripts/run-unreal-tests.sh "ProyectoMed.StationVoice"
```

The stack's Phoenix answers with the mock patient ("Meu nome é Carlos."), not the
scripted one ("Bom dia, doutor."), so the whole suite takes two runs: the voice
specs above inside the stack, and the rest against the scripted Phoenix of the
previous section:

```bash
scripts/run-unreal-tests.sh "ProyectoMed.StationClient"
```

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

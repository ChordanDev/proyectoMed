# 191 Unreal spoken turn

Objective: the learner speaks and the MetaHuman patient answers aloud, lip-synced, with the same approved reply as text (#191, parent #186).
Branch: `feat/191-spoken-turn` from `develop`. Delivery: chained PRs to `develop`, the strategy the human chose for #190. Test runners: `uv run python -m unittest` (voice-worker), `scripts/run-unreal-tests.sh` (Unreal automation).

## Specs

- S1 "The microphone is enabled only after the audio disclosure is shown and the learner opts in."
- S2 "Learner speech is published to the LiveKit room and committed as a turn by the existing voice worker."
- S3 "The patient reply is heard, lip-synced on the MetaHuman, and displayed as text, and all three correspond to the same approved reply."
- S4 "Asking about a fact outside the Station Package produces the neutral Brazilian Portuguese refusal, never invented clinical content."
- S5 "No learner audio or transcript outlives the station run."
- S6 "Automated tests cover a full spoken turn at the station client module against local Phoenix and a local LiveKit development server."
- S7 Product direction from the human (2026-10-21, #190 S12): "al iniciar la app por primera vez, vamos a pedir acceso al microfono para las sesiones de una vez. Luego vamos a hacer que los entrenamientos se puedan hacer por texto o audio, antes de entrar selecionaremos si lo haremos por texto o por audio." #190 left the first-launch microphone request and the full disclosure to #191. The disclosure names the real processors: Deepgram transcribes the learner's audio and Cartesia synthesizes the patient voice (#360, which replaced ElevenLabs on 2026-10-22). It replaces the neutral line #190 put under the voice choice.
- S8 Test seam chosen by the human (2026-10-22): "Modo fake en el worker". The voice worker gets a test-only mode, switched on by an environment variable. A fake STT returns a fixed phrase when the learner stops speaking, and a fake TTS emits a tone. The S6 test runs the real worker, a real `livekit-server --dev` and Phoenix with the mock LLM and the approving Jev adapter. It ships as its own small PR.
- S9 Interface rule (docs/unreal-station-client.md): LiveKit joins `StationClient` as an addition owned by the ChordanDev track. The change is documented in the same PR.
- S10 Voice loss, agreed with the human on 2026-10-22 after the by-eye check showed no message when the stack stopped ("Si, está bien" to this proposal): while LiveKit retries the connection, or while the voice worker is gone, the HUD shows "Reconectando a voz...". If the voice does not come back within **10 seconds**, it shows "A voz caiu. O tempo da estação continua.", stays that way, and the microphone stops.
  Amended on 2026-10-22 after the verifier's A4 ("Dale" to this proposal): if the voice worker has not joined 20 seconds after the microphone is published, the HUD shows the same "A voz caiu. O tempo da estação continua.". Once the voice is lost, the link leaves the room, so a worker that comes back later can no longer speak over that message (verifier A1).

## Tasks

- [x] T1 Voice worker fake providers: STT and TTS behind an env switch, refused unless LiveKit is on loopback, with unit tests — S8 — inline — d074820 (RED: ImportError; GREEN: 14 new, 166 worker tests OK)
- [x] T2 Local voice stack script: `livekit-server --dev`, mock LLM, Phoenix in e2e mode and the worker in fake mode, for the S6 test — S6, S8 — inline — probe passed (see L5)
- [x] T3 StationClient voice link: LiveKit SDK dependency, room join with Phoenix's credential, microphone-source publishing from a pluggable audio source, patient PCM out, `transcript` event parser — S2, S3, S5, S9 — inline — RED: 5 parser specs failed on stubs; GREEN: 36 unit specs
- [x] T4 Spoken-turn automated test at the station client module — S2, S3, S4, S6 — inline — 60/60 Unreal specs inside the voice stack; mutation check failed as expected
- [x] T5 Patient voice in the scene: playback and the mouth solver moved out of the spike; a native face anim instance blends the speaking mouth over the idle loop, swapped in at runtime, with no Live Link and no editor asset — S3 — inline — specs written after the code (5 PatientVoice.Unit); 71/71; pending the human's by-eye check
- [x] T6 UI: first-launch microphone permission, the full disclosure and opt-in, the voice HUD with the reply text — S1, S3, S7 — inline — 2 mic-flow unit specs, 1 Phoenix spec (mic blocked), 1 voice-stack flow spec; 71/71; pending the human's by-eye check
- [x] T7 Run end: leave the room and drop transcript text when the run ends — S5 — inline — the room is left on finish and discard (T3). With #355 merged, the spoken text stays through the feedback, which cites it, and `ResetRun` clears it on "Reiniciar estação" and when the game ends. The microphone stops at run end (L23). The spec was written after the code; a mutation check (no voice reset in `ResetRun`) makes it fail.
- [x] T8 Docs: interface contract, setup, voice runbook — S9 — inline — the voice link contract and tests are in docs/unreal-station-client.md. docs/unreal-setup.md covers voice trainings, the HUD states, the conversation panel and `NSMicrophoneUsageDescription` for #197. The README covers the fake providers and the stack. Real speech uses the README real-time runbook.
- [x] T9 Voice loss: "Reconectando a voz..." while LiveKit retries or the worker is gone, lost after 10 s — S10 — inline — RED: 3 of 4 `FStationVoiceLiveness` specs failed on a stub; GREEN: 14/14 unit, 75/75 in the voice stack; pending the human's by-eye rerun of the stack stop
- [x] T10 Voice loss, part two: the 20-second limit for the first join, and leaving the room once the voice is lost — S10 — inline — RED: 2 new `FStationVoiceLiveness` specs failed; GREEN: 77/77 in the voice stack. Leaving the room on `Failed` has no automated test: nothing can make the worker leave from inside a spec (verifier A5). It is checked by eye: after "A voz caiu", restarting the stack must not make the patient speak.

## Log

- L1 (2026-10-22) User: "si, arrancá con 191" after "Cual es la siguiente issue para hacer? de que se trata".
- L2 (2026-10-22) Map (sonnet explorer, read-only):
  - The #189 spike links the LiveKit C++ SDK 1.12.3 (`unreal/Source/ThirdParty/LiveKitSDK`). It plays the `voice-worker` participant's `patient-voice` track and drives lip sync through `FSpeechAnimationSolverV4` and the Live Link subject `PatientVoice`. It publishes no microphone.
  - The worker sends reply text as JSON data messages on topic `transcript`. The web parser is `web/src/features/station/hooks/voiceTranscriptEvents.ts`.
  - Phoenix's learner token (`live_kit.ex:60-68`) carries identity `learner-<id>`, `canPublishSources: ["microphone"]` and `canPublishData: false`. The worker reads only the learner's `SOURCE_MICROPHONE` track (`worker.py:382`).
  - No automated test drives a spoken turn through LiveKit today.
- L3 (2026-10-22) #325 (speak typed-turn replies) is a separate issue blocked by #191; out of scope here.
- L4 (2026-10-22) T1 done: `voice-worker/fake_providers.py`, wired through `build_stt`/`build_tts`. The worker refuses `VOICE_WORKER_FAKE_PROVIDERS` without a loopback `LIVEKIT_URL`, at startup. RDD assess on d074820: medium, `under_budget`.
- L5 (2026-10-22) T2 done: `scripts/run-voice-stack.sh` plus `scripts/voice-stack/{mock_openai.py,probe_spoken_turn.py}`. Probe run: learner final transcript, patient text, patient audio and patient end all ok; the stack stopped cleanly with no listener left on 4000, 7880 or 18766. Phoenix's OpenAI adapter does not stream, so the reply arrives as one segment.
- L6 (2026-10-22) Independent verifier (sonnet, read-only, baseline origin/develop): S8 and the S6 harness met, no blockers, 166 worker tests OK, full probe passed, clean teardown on SIGTERM and SIGINT. Two advisories fixed: the fake switch now refuses `LIVEKIT_URL` values with a backslash, `@`, blanks or control characters, which parsers read differently (RED: the new test cases failed); and the exit trap no longer trips over an empty PID array in macOS bash 3.2, and the script now requires `nc`. Advisories kept: `wait_for` waits the full timeout when a process died early; Phoenix still inherits turn-voice and TypeSafe variables, which this stack does not use.
- L7 (2026-10-22) RDD on the slice origin/develop..22ccd9f (lenses risk, resilience, reliability; the human granted it): approved and acknowledged, lineage review-f948679325ce5d97. Eight non-blocking advisories. Two fixed after review: the probe now waits for the worker to join instead of sleeping 2 s, and `wait_for` fails fast when its process dies (probe rerun: all four steps ok). The rest are left as suggestions: the mock does not validate bodies; the probe discards without a check; the startup refusal has no test; TERM exits 130; a `TimeoutError` alias.
- L8 (2026-10-22) Slice A boundary: T1 and T2, origin/develop..HEAD of this commit. Next PR slice: T3 and T4 (StationClient voice link and spoken-turn test).
- L9 (2026-10-22) T3 design:
  - The microphone enters `StationClient` as pushed PCM (`FStationVoiceLink::PushMicrophonePcm`). It is resampled to 48 kHz mono 10 ms frames (`FStationPcmFramer`), run through LiveKit's `AudioProcessingModule` (echo cancellation, noise suppression, AGC, high-pass) with the patient's voice as the reverse stream, then published from an `AudioSource` as a `SOURCE_MICROPHONE` track.
  - `PlatformAudio` was not used. It also plays remote audio through WebRTC's device, which would take the patient's voice out of the game's own playback that lip sync was measured against in #189. It would also keep tests from pushing generated audio.
  - The game captures the device and pushes the PCM (T5/T6).
  - `UStationClient::ConnectVoice` owns the link. It leaves the room on a successful finish, on discard, on a refresh that shows the run completed, on `DisconnectVoice` and on `BeginDestroy` (S5).
- L10 (2026-10-22) T4. `ProyectoMed.StationVoice.Stack` runs against `scripts/run-voice-stack.sh` and covers four things: a spoken turn (S2, S3), the reply equal to Phoenix's stored approved reply (S3), and the room left on finish and on discard (S5).
  - S4 is enforced in Phoenix (`backend/test/backend/station_ai_test.exs` asserts the "Não consta no script." refusal). The client shows any approved reply verbatim.
  - The stack spec was written after the link, so its RED is a mutation instead. With `Source->captureFrame` disabled, the spoken-turn spec timed out waiting for the reply.
  - The same run exposed harness flakiness: the worker in `start` mode refuses jobs above 0.7 CPU load, which happens while the editor starts. The stack now runs it as `dev --no-reload` (no load cap).
  - Whole suite inside the stack: 60/60, exit 0.
- L11 (2026-10-22) Independent verifier on 3665a0f (sonnet, read-only): 60/60 specs, two blockers.
  - B1: `livekit::initialize()` answers false when the SDK is already initialised, so the station client and the #189 spike each failed when the other one initialised it first.
  - B2: `Disconnect` waited on the game thread for a pending join; a blackholed LiveKit holds `connect` for about 32 s.
  - Correction batch:
    - B1: `EnsureInitialized` reuses an SDK another module initialised, and the spike does the same.
    - B2: `Disconnect` marks the link dead and leaves the room on a background thread (`StationLiveKit::RunTeardown`); module shutdown waits up to 2 s for those threads.
    - Advisories fixed too: null `Apm` guarded under its lock; a non-string `role` dropped as on the web; the discard spec now checks the held link's state and that no handler runs after it.
  - RED for B2: the new "leaves at once even while the room is still being joined" spec failed ("the game is not held up"). RED for the `role` case: failed. The B1 spec passes only when it runs before the stack specs, so its evidence is the verifier's scratch program: `initialize` gave 1, then 0.
  - GREEN: 71/71 Unreal specs inside the voice stack.
  - Advisories kept as known limits (docs): no leave on a run that ended on Phoenix's side until a refresh or finish reports it; `setStreamDelayMs` not set.
- L12 (2026-10-22) T5 and T6 design:
  - The face no longer needs Live Link. `UStationPatientFaceAnim`, a native anim instance with its own proxy, plays the scene's idle loop and lerps only the mouth controls (`StationFaceBlend::IsMouthControl`) toward the solver's output with a speech weight: 80 ms attack, 300 ms release, held 250 ms after the last loud patient frame.
  - The patient's voice reaches the speaker and the solver through `FStationPatientAudioSink`, which the component detaches under a lock before its objects go, so a late LiveKit frame never touches a freed wave.
  - The microphone (`UStationMicrophone`, the AudioCapture plugin) runs exactly while the voice link is `WaitingForWorker` or `Ready`.
  - The first-launch disclosure step (`EStationRunStep::Microphone`) names Deepgram and Cartesia (L14) and says the app keeps no audio or transcript after the station. It makes no claim about the providers' retention.
  - The system permission goes through AVFoundation on macOS. On Windows the privacy settings decide.
  - Tests inject `FStationMicrophoneSetup`, so they never prompt or write the user's settings.
- L13 (2026-10-22) T7 status: rooms are left on every run end the client sees (T3 and the L11 fix), and Phoenix forgets the session. The flow keeps the last turn's text on screen until the next run. Clearing it at run end belongs with the run-end screen of #195, which this branch does not have.
- L14 (2026-10-22) Human: "No, pasemos a Cartesia directo, ya ví mucho y es muchisimo mejor para tiempo real que evenlabs". Done in #360, its own session and branch `feat/cartesia-tts`. Here the Unreal disclosure and brief note now name Cartesia. The stack also unsets `CARTESIA_*`, so the worker is fake whichever provider the branch builds. When #360 reaches `develop`, merging it into this branch conflicts in `voice-worker/worker.py` `build_tts`: keep Cartesia, and keep `if fake_providers_from_env(os.environ) is not None: return FakeTTS()` first.
- L15 (2026-10-22) By-eye check, step 9: stopping the voice stack (Ctrl+C) during a voice training did not show "A voz caiu. O tempo da estação continua.". Cause: the link marks the voice lost only on a failed join, a `Fatal` event or `onDisconnected`. The worker leaving sets `WaitingForWorker` ("Conectando a voz..."), and the LiveKit SDK keeps reconnecting without calling `onDisconnected`. The editor log shows no voice failure after the credential. The human accepted the 10-second rule (S10, T9).
- L16 (2026-10-22) T9 in 2f14d08. `FStationVoiceLiveness` (StationClient, private) decides the shown state on the game thread from LiveKit's signals: worker present, and `onReconnecting`/`onReconnected`. A core ticker checks it twice a second while `Reconnecting`. The link now drops microphone audio unless the shown state is `WaitingForWorker` or `Ready`. Before the worker first joins there is still no time limit; nobody asked for one. RDD assess on 22ccd9f..HEAD: high, review due. It runs with the independent verifier after the human's by-eye check.
- L17 (2026-10-22) By-eye check, step 7, human: "La boca se veía bastante bien, o sea, como era un tono, simplemente un sonido, como que no modulaba tanto la voz, la boca, pero estaba bastante bien." Expected with the fake TTS: a steady 220 Hz tone gives the solver little to articulate. Lip sync with a real Cartesia voice is still to be seen by eye (README real-time voice runbook, needs the human's keys).
- L18 (2026-10-22) By-eye check, rest of the steps, human: "Si, funcionan bien todos los casos". Covered: the microphone disclosure and the macOS prompt, the brief voice note, the voice HUD states, the "Você:"/"Paciente:" captions, no self-triggered turn without headphones, and the voice stack stop showing "Reconectando a voz..." then "A voz caiu. O tempo da estação continua.". T5, T6 and T9 pass by eye.
- L19 (2026-10-22) Independent verifier on 60893d3..HEAD (sonnet, read-only): no blockers; S1–S5, S7, S9 and S10 pass by reading. Advisories:
  - A1: the link stays in the room after the 10-second `Failed`. Fixed in T10.
  - A2: when #195 finishes a run, nothing stops the OS microphone device until the next flow broadcast. To handle when merging with #355.
  - A3: `StartSession` does not leave the voice. A false positive: `StartSession` refuses while a run is active, and discarding leaves the voice.
  - A4: no limit before the worker first joins. The human chose the 20-second limit; "Dale" answers this proposal: "si el worker no entra en 20 segundos, aparece 'A voz caiu. O tempo da estação continua.'".
  - A5: the LiveKit delegate wiring has no automated test.
  - A6: after "Agora não", an OS grant lets the voice training start without asking again. Pending a decision from the human.
  - A7: minor items, among them `NSMicrophoneUsageDescription` for packaged macOS builds (#197) and the setup doc's missing HUD states (T8).
- L20 (2026-10-22) RDD on 22ccd9f..3dc698d (lenses risk, resilience, readability, reliability; the human granted it): approved and acknowledged, lineage review-00573b988975479f. The candidate based on 06542d6 failed three times with `lens_context_budget_exceeded`; the human granted it each time. Non-blocking findings, kept as later work:
  - The OS microphone device can stay open after the run ends (R1, R3; verifier A2).
  - Transcript text is kept after the run (T7, #195).
  - A `Fatal` event keeps the microphone until the 10-second loss (R3, R4).
  - A microphone that fails to open is silent in the HUD (R3, R4).
  - The SDK init failure is masked as ready, and the SDK-sharing spec is vacuous (R3, R4; StationClientModule.cpp:29-39).
  - The spike ignores the init result.
  - The voice event handling in the run flow has no direct spec.
  - Readability suggestions R2-001..005.
- L21 (2026-10-22) Verifier A6, the human's answer: "Si, alcanza para abrir el microfono". After "Agora não", choosing "Treino por voz" counts as the opt-in, because the brief names Deepgram and Cartesia before the choice. No change.
- L22 (2026-10-22) Merged `develop` after #353, #354 and #355 (typed turns, exams, finish and feedback) and #362 (Cartesia) landed there. Conflicts:
  - `voice-worker/worker.py`: Cartesia is kept, and the fake switch is checked first, as L14 planned.
  - The station flow, screens and controller: both sides are kept. `ResetRun` now also clears the voice view, so a run reset drops the spoken text (part of T7).
  - The HUD: my floating captions and the #353 conversation panel both sat at the bottom centre. The human was asked "En el entrenamiento por voz, ¿dónde se ve la conversación hablada?" and chose "Todo en el panel (Recommended)":
    - spoken turns join the conversation panel as "Você:" and "Paciente:" lines;
    - the live caption and the reply being spoken show in progress;
    - the floating captions are gone.
  RED: `ProyectoMed.StationRun.Voice` timed out waiting for transcript lines. GREEN: 27/27 voice specs in the voice stack, 67/67 specs against the scripted Phoenix, 169 worker tests. The suite now takes two runs because the two Phoenix setups answer differently; docs/unreal-station-client.md says so.
- L23 (2026-10-22) Verifier A2, now reachable through #355: after "Finalizar estação" the OS microphone kept capturing until the feedback loaded. `UStationRunFlow::IsListening` is true only while the run is `Running` and its voice link is in the room, and the controller follows it. RED: the voice flow spec expected the microphone to stop right after `Finish()` and failed. GREEN: 27/27 voice specs in the voice stack, 67/67 against the scripted Phoenix. One run against the scripted Phoenix quit before running any test; the runner reported it, and the rerun passed.
- L24 (2026-10-22) T7 closed, see its line.
- L25 (2026-10-22) Delivery. Every task is checked off. The branch is about 4,270 changed lines over `develop`. The human chose "Feature branch chain (Recommended)" when asked "¿Cómo encadeno las PRs?". The tracker `feat/191-spoken-turn-tracker` holds this document. The child slices, each based on the previous one:
  - 01 fake providers
  - 02 voice stack
  - 03 voice events, PCM and SDK sharing
  - 04 voice link
  - 05 patient face
  - 06 voice training
  A sonnet writer builds them in their own worktree (the context backstop). The last slice's tree must equal this branch. Push and PRs wait for the human.
- L26 (2026-10-22) The slicing writer built the chain locally:
  - the tracker, bdd2d96;
  - 01, 4052209;
  - 02, 9d58465;
  - 03, e834580;
  - 04, 421cffc;
  - 05, cb2ac5b;
  - 06, f7026c9.
  Every slice builds and passes its checks, and the last tree equals this branch. Slices 04 (about 1,130 lines) and 06 (about 970) stay over 400, because the voice link and the voice training are each cohesive with their tests. The writer also found 3 run-flow unit specs from #355 that called `Begin(Client)` with the real microphone setup. That setup reads a git-ignored ini, so on a fresh checkout the first-launch disclosure step made "neither finishes nor discards before the run is running" fail. RED reproduced by removing the local flag. Fixed by injecting the fake microphone; GREEN 9/9 without the flag.

# #189 Spike: MetaHuman lip sync driven by the patient voice track from LiveKit

Parent: #186, ADR-013 (#209). Branch `spike/189-metahuman-livekit-lipsync` from `origin/develop` (ac07c46). Delivery: `ask-on-risk`; output is a decision, not production code. Checks: C++ build with `Build.sh ProyectoMedEditor Mac Development`; lip sync quality is judged by the human (ChordanDev) by eye.

## Specs

Acceptance criteria quoted verbatim from #189:

- S1 "A MetaHuman in a minimal scene audibly plays the patient voice track from a local LiveKit development server fed by the existing voice worker."
- S2 "The MetaHuman's mouth moves in sync with that live audio."
- S3 "The chosen LiveKit integration and lip-sync approach are written up with the alternatives tried, their licence and cost, and measured audio-to-mouth delay."
- S4 "The source of the MetaHuman asset used and its licence terms are recorded."
- S5 "A human has watched the result and recorded a verdict on whether it is believable enough to continue."
- S6 "If the approach is not viable, the write-up says so and proposes the change to the spec instead of continuing."

Constraints from the session brief:

- S7 Findings go in a short doc under `docs/`, plus a proposed amendment to #186 or ADR-013. No issue comment or edit without the human's approval.
- S8 Lock `.uasset`/`.umap` with `git lfs lock` before editing; check the LFS budget before committing a MetaHuman.
- S9 Respect: in-client UI is native UMG; MVP targets macOS and Windows desktop only.
- S10 The voice worker and Phoenix run from a separate worktree of `feat/116-realtime-voice` (draft PR #151). Never merge, rebase, or push that branch.

## Tasks

- [x] T0 Research: LiveKit client options, live-audio lip sync, voice branch map — delegated explorers (mapping trigger) — no commit
- [ ] T1 LiveKit C++ SDK (official `client-sdk-cpp`, pinned) as a ThirdParty module; Unreal client joins a local room and receives `patient-voice` PCM — S1, S3 — inline
- [ ] T2 Playback through `USoundWaveProcedural` and lip sync through Epic `StreamingADA` `SpeechAnimationSolverV4`, with envelope jaw-open fallback — S1, S2 — inline
- [ ] T3 Minimal scene with a MetaHuman (human imports it) — S1, S4, S8 — human + inline
- [ ] T4 End-to-end against the real voice worker; latency measurement; human verdict — S1, S2, S3, S5 — human + inline
- [ ] T5 Findings doc under `docs/` and proposed amendment to #186 / ADR-013 — S3, S4, S6, S7 — inline

## Log

- L1 (2026-10-20) User request: "Work on GitHub issue #189 in ChordanDev/proyectoMed: 'Spike: MetaHuman lip sync driven by the patient voice track from LiveKit'. [...] Goal: prove the riskiest assumption before anything else is built. Inside the Unreal client, a MetaHuman joins a real local LiveKit room, plays the patient voice track that the existing voice worker publishes, and drives its lip sync from that track. The spike delivers a decision, not production code."
- L2 (2026-10-20) Research findings:
  - LiveKit has no official Unreal SDK. The official Apache-2.0 `livekit/client-sdk-cpp` v1.12.3 (2026-10-19) ships macOS arm64 (10.7 MB) and Windows x64 (11.9 MB) prebuilts. `AudioStream::fromTrack` + blocking `read()` gives interleaved int16 PCM, 48 kHz mono by FFI default. The community plugins (`mgwilt/livekit-unreal`, `lifelike-and-believable/livekit-ffi`) are weeks or months old; the first exposes no PCM.
  - UE 5.8 ships `StreamingADA` / `SpeechAnimationSolver` as a Runtime module. It takes float PCM and returns MetaHuman GUI controls, converted to 251 raw controls by `GuiToRawControlsUtils` (MetaHumanCoreTech, Runtime). Default NNE backend: Mac `NNERuntimeORTCpu`, Windows `NNERuntimeORTDml`. Epic's documented "MetaHuman (Audio)" Live Link source is editor and capture-device oriented. It depends on `MetaHumanPipelineCore`, declared `Editor`, so it is a packaged-build risk.
  - Paid alternative: Georgy Dev "Runtime MetaHuman Lip Sync" (Fab). Price and licence are unverified.
  - Voice branch: `livekit-server --dev` (devkey/secret, ws://127.0.0.1:7880); Phoenix `POST /api/stations/active/sessions/:id/voice`; worker publishes `patient-voice` (ElevenLabs pcm_24000) as `voice-worker`. A spoken reply needs OpenAI, Deepgram, ElevenLabs keys and `JEV_E2E_APPROVING_ADAPTER=true`. There is no offline stub.
- L3 (2026-10-20) Next step: ask the human for permission to download the LiveKit C++ SDK prebuilt.
- L4 (2026-10-20) Human: "dale, bajalo". `scripts/fetch-livekit-sdk.sh` pins v1.12.3 with SHA-256 checks and installs into the git-ignored `unreal/Source/ThirdParty/LiveKitSDK/{Mac,Win64}`. The SDK ships as dynamic libraries (`liblivekit` + `liblivekit_ffi`). Its headers include only the C++ standard library and it exports no protobuf or Abseil symbols.
- L5 (2026-10-20) T1/T2 code builds. The `PatientVoiceSpike` module holds `FLiveKitPatientStream`, `FPatientMouthSolver` (StreamingADA V4 or the envelope driver), `FPatientVoiceLiveLinkSource` (Basic role, the MetaHuman raw-control layout) and `UPatientVoiceComponent`.
  - `ProyectoMedEditor` Mac Development: build succeeded.
  - `ProyectoMed` (game) Mac Development: compiles and links with SpeechAnimationSolver, MetaHumanCoreTech and LiveKit, and copies both dylibs to `Binaries/Mac`. Only the known Xcode 27 `.app` finalize step fails (#262). The packaged run is not verified.
  - Stage-one publisher `scripts/spike-189/publish-test-voice.sh` verified against `livekit-server --dev`. `lk` publishes the track under its file path, so the component's empty `TrackName` attaches the publisher's first audio track.

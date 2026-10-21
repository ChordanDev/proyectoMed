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
- L6 (2026-10-20) RDD reviewed both work-unit commits (`b8f9682` with the risk and resilience lenses, `155a2f9` with the risk lens). Both were approved and acknowledged. The stop hook keeps proposing a base of `06542d6` (main), which is stale for this worktree; that is a known false positive.
- L7 (2026-10-20) Stage 1, observed in editor PIE (MCP over HTTP; the actor carries `UPatientVoiceComponent`, with an empty `TrackName`):
  - Connected in 74 ms. The first frame was 48000 Hz, mono, 480 samples (10 ms).
  - The solver runs on NNERuntimeORTCpu with 81 curves and 80 ms lookahead, about 50 mouth frames/s, and 3.2-5.0 ms per solve.
  - Audio backlog was 9-33 ms, plus 43 ms of device buffer.
  - Estimated mouth-minus-audio: +9 to +32 ms (the mouth trails the audio).
  - When the publisher loop restarted, the track was resubscribed and PCM kept flowing.
  - Human (2026-10-20): "sí, se escucha bien". The voice is audible in PIE. Not yet observed: the MetaHuman face (no MetaHuman yet).
- L8 (2026-10-20) MetaHuman created in-engine with MetaHuman Creator (UE 5.8, MetaHuman Creator plugin, beta). Asset `/Game/Spike/MHC_Patient`, from a stock preset, assembled with the UE Optimized pipeline into `/Game/Spike/MHC_Patient/BP_MHC_Patient`. Shared assets went to `/Game/MetaHumans/Common`.
  - Setup needed: the "MetaHuman Creator Core Data" launcher component (5.8 GB), an Epic account login in the editor, and `r.GPUSkin.Support16BitBoneIndex` plus `r.GPUSkin.UnlimitedBoneInfluences` in `DefaultEngine.ini`.
  - The Full Rig (joints and blend shapes) failed 3 of 3 times. Epic's auto-rig poll timed out after 300 s and the editor reported "Server Error"; it also warned "Falta memoria para hacer rigging automático con formas de mezcla". The Joints Only rig succeeded (204 s, then 50 s). The spike uses Joints Only.
  - Texture-source download first failed with 30 s idle timeouts on S3 (`HttpConnectionTimeout=30`, link ~2.5 MB/s). It succeeded after launching the editor with `-ini:Engine:[HTTP]:HttpConnectionTimeout=300,[HTTP]:HttpActivityTimeout=300`. A `Saved/Config/MacEditor/Engine.ini` override was deleted by the editor at startup, and `open <file> --args` drops arguments; `open -a UnrealEditor.app --args <uproject> ...` works.
  - MetaHuman Creator needs at least 10 GB of available memory (`AvailableVirtual < 10 GB` checks in its editor source). On this 24 GB Mac it warned during assembly, and one assembly attempt crashed the editor (SIGABRT in the `VisualLookUp` plugin's faiss code during a list drag-over). It assembled after closing other apps.
  - On-disk size: `Content/Spike` 149 MB plus `Content/MetaHumans` 151 MB, 187 files. The repo currently tracks 0 LFS files.
- L9 (2026-10-20) Scene `/Game/Spike/PatientVoice` (Basic level), set up via MCP:
  - `BP_MHC_Patient` at (200, 0, 0), yaw 90, with `useLiveLink=true`, `liveLinkSubject=PatientVoice` and `useARKit=false`.
  - An actor with `UPatientVoiceComponent` (TrackName empty).
  - Human verdict in PIE (2026-10-20): "sisi se mueve bastante bien". The mouth moves with the live LiveKit voice, using the speech solver and the Joints Only rig.
  - MCP `CaptureViewport` frames showed no mouth change (mean pixel diff about 1/255). They probably render the editor world rather than PIE, so they are not evidence either way.
- L10 (2026-10-20) Human: "lo vamos a hacer siempre desde mi compu asi que no hace falta commitear". The MetaHuman, the scene and the default open-world map stay local, excluded through `.git/info/exclude`.
  - Human asked whether a 4 TB SSD helps. It does not help the memory check: on Mac, `AvailableVirtual` is free RAM plus already-allocated swap (`MacPlatformMemory.cpp:199`), and macOS swaps only to the boot volume.
- L11 (2026-10-20/21) The Full Rig succeeded on the fifth attempt (291 s).
  - Root cause of the earlier failures: `UMetaHumanCloudServicesSettings.Timeout = 300` (MetaHumanSDK `DefaultMetaHumanSDK.ini`) caps each cloud request. Three attempts died at 300 s.
  - One attempt with `-ini:MetaHumanSDK:[/Script/MetaHumanSDKEditor.MetaHumanCloudServicesSettings]:Timeout=1200` still hung for 1200 s. The next one finished in 291 s. Epic's auto-rig service is intermittent.
  - Reassembled with UE Optimized. "Guardar todo" saved only `MHC_Patient`, so the 38 assembled assets were saved via MCP `save_assets`.
  - The room token expired after its 4 h validity; it was refreshed with `lk token create --valid-for 12h`.
- L12 (2026-10-21) Human verdict (S5) on the Full Rig in PIE: "no se la verdad, tendría que verlos juntos, pero sigamos con este, ya fue". The approach is accepted to continue. No side-by-side comparison of the Joints Only and Full rigs was made.
- L13 (2026-10-21) Paused stage 2 (T4). Human: "mi hermano tiene todo eso pero en otra rama, lo tiene que pasar a develop y ahi lo traemos acá y lo hacemos". The voice worker, Phoenix and the OpenAI/Deepgram/ElevenLabs keys arrive through develop. Resume: merge develop into this branch, run Phoenix and the worker locally, have the learner speak through the web harness, join Unreal as `unreal-observer` in `station-session-<sid>` with `TrackName=patient-voice`, then measure latency and record the verdict. T5 (findings doc and amendment) follows.

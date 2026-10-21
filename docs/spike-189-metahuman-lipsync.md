# Spike #189: MetaHuman lip sync from the LiveKit patient voice

**Verdict: viable, continue.** A MetaHuman in the Unreal client joined a local
LiveKit room, played the patient voice track published by the real voice worker,
and moved its mouth in sync with it. The human watching (ChordanDev) judged it
believable enough to continue. This answers the two questions that #186 and
ADR-013 (#209) left open:

| Open question | Decision |
| --- | --- |
| Which LiveKit client integration Unreal uses | The official **LiveKit C++ SDK** (`livekit/client-sdk-cpp`, Apache-2.0), linked as prebuilt dynamic libraries through an Unreal ThirdParty module. |
| How MetaHuman lip sync is driven from a live track | Epic's **StreamingADA speech-to-animation solver** (ships with UE 5.8, runtime module), fed with the same PCM the client plays, publishing MetaHuman face controls as a **Live Link subject** that the MetaHuman Blueprint consumes. |

Spike code lives in `unreal/Source/PatientVoiceSpike` and is throwaway; the
production network module (ADR-013) should reuse the approach, not the code.

## How it works

```text
voice worker ──Opus──▶ LiveKit room ──▶ FLiveKitPatientStream (C++ SDK, 48 kHz mono int16, 10 ms frames)
                                              │
                         ┌────────────────────┴───────────────────┐
                         ▼                                        ▼
           USoundWaveProcedural (audible)         FPatientMouthSolver thread
                                                  StreamingADA V4 solver (81 GUI curves, 20 ms steps)
                                                  → GuiToRawControlsUtils (251 raw controls)
                                                         ▼
                                       Live Link source "PatientVoice" (Basic role)
                                                         ▼
                                  BP_MHC_Patient: useLiveLink = true, subject = PatientVoice
```

- **`FLiveKitPatientStream`**: joins with a URL and token, subscribes to the
  `patient-voice` track of participant `voice-worker` via
  `Room::setOnAudioFrameCallback`. All `livekit::`/`std::` types stay in one
  `.cpp`.
- **`FPatientMouthSolver`**: a worker thread that runs
  `FSpeechAnimationSolverV4` on the NNE ONNX Runtime CPU backend (Mac) or
  DirectML (Windows default). It is language-agnostic: it reads audio, not text.
  The envelope-driven jaw fallback (`MouthDriver = Envelope`) also works through
  the same output path.
- **`FPatientVoiceLiveLinkSource`**: publishes the raw controls in the same
  layout as Epic's own MetaHuman audio Live Link source, so a stock MetaHuman
  needs no custom animation Blueprint.

## Results against the acceptance criteria

| Criterion (#189) | Result | Evidence |
| --- | --- | --- |
| A MetaHuman audibly plays the patient voice from a local LiveKit server fed by the existing voice worker | ✅ | Stage 2, 2026-10-21: the learner spoke through the web harness. The worker (Deepgram, Claude Haiku, Jev, ElevenLabs) answered on `patient-voice`, and Unreal joined as `unreal-observer`. Human: "Se escucha bien y acompaña la voz". |
| The mouth moves in sync with that live audio | ✅ | Same run, 271 s of patient audio, 13 544 mouth frames. Stage 1 (synthetic pt-BR voice): "sisi se mueve bastante bien". |
| Integration and lip sync approach written up, with alternatives, licence, cost and measured delay | ✅ | This document. |
| Source and licence of the MetaHuman asset recorded | ✅ | See "MetaHuman asset". |
| A human watched and recorded a verdict | ✅ | "sigamos con este, ya fue" (2026-10-21, Full Rig). |
| If not viable, say so and propose a spec change | n/a | Viable. Amendments are proposed below for what the spike learned. |

## Measurements

Measured on a 24 GB Apple Silicon Mac, UE 5.8.3 editor (PIE), local
`livekit-server --dev`. Timings come from `LogPatientVoiceSpike`, which logs
once per second.

| Metric | Stage 2 (real worker, 271 s) | Stage 1 (synthetic voice) |
| --- | --- | --- |
| Room connect | 113 ms | 74 ms |
| PCM delivered by the SDK | 48 kHz mono, 480-sample frames | same |
| Solver time per 20 ms step | median 3.8 ms, p95 5.2 ms, max 14.7 ms | 3.2–5.0 ms |
| Mouth frames | ~50 per second | ~50 per second |
| Playback backlog (procedural wave) | 5–84 ms, settled near 70 ms after the first minute | 9–33 ms |
| Audio device buffer | 43 ms | 43 ms |
| **Estimated audio-to-mouth offset** | **+39 ms at start, then −16 to −42 ms** (mouth ahead) | +9 to +32 ms (mouth behind) |

How the offset is estimated: mouth path = solver lookahead (80 ms) + time from
PCM arrival to a solved frame. Audio path = procedural backlog + device buffer.
Positive means the mouth trails the audio. This is a pipeline estimate. It leaves
out render latency (about one frame, ~16 ms) and was not checked against a
high-speed camera recording. The human saw no visible desync in either stage.

## Alternatives considered

### LiveKit client

| Option | Licence and cost | Why not chosen |
| --- | --- | --- |
| **Official C++ SDK v1.12.3** (chosen) | Apache-2.0, free | Gives PCM per track and has macOS arm64 and Windows x64 prebuilts. It links cleanly as dylibs, exports no protobuf or Abseil symbols, and its headers use only the C++ standard library. |
| `mgwilt/livekit-unreal` (community, UE 5.8) | Apache-2.0, free | Plays remote audio through the OS device, so there is no PCM for lip sync. It pins old SDKs and is weeks old. |
| `lifelike-and-believable/livekit-ffi` (community) | MIT, free | Publish/mocap oriented. Prebuilts are Windows only and macOS is unverified. |
| LiveKit Swift SDK | Apache-2.0 (not re-verified) | macOS only, so it would need a second code path for Windows. |
| Sidecar process (Python `livekit-rtc` → local socket) | Apache-2.0, free | Adds a process to ship and supervise, plus IPC latency. It is a fallback if the in-process SDK breaks. |
| Raw WebRTC / Pixel Streaming modules | free | Would re-implement LiveKit signalling. |

No official LiveKit Unreal SDK exists (checked 2026-10-20: LiveKit GitHub org,
docs.livekit.io SDK list, Fab).

### Lip sync

| Option | Licence and cost | Why not chosen |
| --- | --- | --- |
| **StreamingADA solver, called directly** (chosen) | Part of UE 5.8 (UE EULA), free | A runtime module, so the game target compiles and links with it. It takes arbitrary PCM. |
| Epic "MetaHuman (Audio)" Live Link source | UE EULA, free | Documented for editor use with a capture device. It depends on `MetaHumanPipelineCore`, which is declared `Editor`, so it is a packaged-build risk. |
| NVIDIA Audio2Face-3D (ACE plugin 2.5) | MIT plugin, open-weight models | Docs cover UE 5.5–5.6, Windows and Linux only. Local inference needs an NVIDIA GPU, so there is no macOS path. |
| Georgy Dev "Runtime MetaHuman Lip Sync" (Fab) | Paid; price and licence unverified (Fab returned 403) | A vendor dependency the engine's own solver makes unnecessary. |
| OVRLipSync | Free, unsupported since about 2020 | Abandoned. |
| Envelope → jaw open | Free | Implemented as a fallback. It only opens the jaw, so it is less believable. |

## MetaHuman asset

- **Source:** created in-engine with MetaHuman Creator (UE 5.8 plugin, beta)
  from a stock preset, auto-rigged with the **Full Rig** (joints and blend
  shapes), 2K textures, assembled with the **UE Optimized** pipeline as
  `/Game/Spike/MHC_Patient/BP_MHC_Patient`.
- **Licence:** from UE 5.6, MetaHuman use is covered by the standard Unreal
  Engine licence with no separate MetaHuman licence, free under USD 1M revenue.
  The terms prohibit using MetaHuman characters or animation to train or test AI
  models, and prohibit redistributing MetaHuman technology.
  - Source: Epic pages surfaced by search ([MetaHuman leaves Early Access](https://www.metahuman.com/news/metahuman-leaves-early-access-with-a-feature-packed-new-release),
    [unrealengine.com/eula/content](https://www.unrealengine.com/eula/content)).
  - The full licence pages could not be fetched (login wall and HTTP 403).
    Re-read [metahuman.com/license](https://www.metahuman.com/license) before
    any commercial release.
  - Driving a MetaHuman with AI-generated speech is an AI-assisted workflow,
    not AI training.
- **Size:** 331 MB on disk, 187 files:
  - `MHC_Patient` (the editable character): 138 MB.
  - The assembled character and textures: about 42 MB.
  - Shared `MetaHumans/Common`: 151 MB.
- **Storage:** kept local by decision for the spike ("lo vamos a hacer siempre
  desde mi compu"). See "Proposed amendments".

### What creating a MetaHuman needed on macOS

| Need | Detail |
| --- | --- |
| "MetaHuman Creator Core Data" | An Epic Launcher engine option, 5.8 GB. Without it, Creator runs with limited features. |
| Epic account login in the editor | Texture download and auto-rigging are Epic cloud services. |
| ≥ 10 GB available memory | Creator checks `AvailableVirtual` (free RAM plus allocated swap). On a 24 GB Mac, close other apps. One assembly crashed the editor (SIGABRT in the `VisualLookUp` plugin). An external SSD does not help: macOS swaps only to the boot volume. |
| GPU skinning settings | `r.GPUSkin.Support16BitBoneIndex` and `r.GPUSkin.UnlimitedBoneInfluences` (now in `DefaultEngine.ini`). |
| Slow links | Launch with `-ini:Engine:[HTTP]:HttpConnectionTimeout=300,[HTTP]:HttpActivityTimeout=300` and `-ini:MetaHumanSDK:[/Script/MetaHumanSDKEditor.MetaHumanCloudServicesSettings]:Timeout=1200`. Use `open -a UnrealEditor.app --args <uproject> …`, because `open <uproject> --args` drops arguments. |
| Patience with the Full Rig | Epic's auto-rig service hung on 4 of 5 attempts. The Joints Only rig worked every time. |

## Known limits

- **Packaged build not verified.** The game target compiles and links with the
  SDK, the solver and MetaHuman core, and copies both dylibs. macOS `.app`
  finalisation is blocked by #262, and Windows was not built.
- **No jitter control.** The playback backlog grew from about 20 ms to about
  70 ms during stage 2 and flipped the offset sign. Production needs a bounded
  jitter buffer and drift correction, or a solver delay aligned to the measured
  playback latency (the component already exposes `AudioDelayMs`).
- **Experimental engine plugin.** `StreamingADA` is marked Experimental and
  Hidden in UE 5.8, and its API can change between engine versions.
- **Resampling.** The solver resamples 48 kHz to 16 kHz with zero-order hold
  internally. Feeding it filtered 16 kHz audio may improve quality. Not tested.
- **Observer only.** Unreal subscribed; it did not publish the microphone.
  Learner audio came from the web harness. Mic capture, echo cancellation and
  barge-in in Unreal remain open (#116, #120, #121). The SDK offers
  `PlatformAudio` (WebRTC ADM with AEC) for that.
- **Token handling is spike-only.** The token came from `lk token create` into
  `Saved/PatientVoiceSpike/token.txt`. Production must take Phoenix's
  short-lived, room-scoped credential, as ADR-013 says.
- **Generation fencing not implemented.** The spike plays whatever arrives on
  the track. ADR-013's rule (never speak or animate a superseded reply) still
  needs the `transcript` data topic and generation ids.
- **Delay not camera-verified.** See "Measurements".

## Proposed amendments

Drafts for the human to approve; nothing has been posted to GitHub.

**ADR-013 (#209):** replace "Open questions left to the spike" with:

> - **LiveKit client:** the network module links the official LiveKit C++ SDK
>   (`livekit/client-sdk-cpp`, Apache-2.0) as prebuilt dynamic libraries,
>   pinned by version and checksum and fetched by script. A sidecar process is
>   the documented fallback.
> - **Lip sync:** the patient voice PCM received from LiveKit is both played
>   and fed to Unreal's StreamingADA speech-to-animation solver at runtime. Its
>   MetaHuman face controls reach the MetaHuman through a Live Link subject. No
>   third-party lip-sync plugin and no stored audio files are involved.
> - **Consequences added:** StreamingADA is an Experimental engine plugin, so
>   engine upgrades must re-verify it. Audio playback needs a bounded jitter
>   buffer so face and voice stay within perceptual sync.

**#186 (spec):** add to Implementation Decisions:

> - Creating or re-rigging a MetaHuman uses Epic's cloud services (an Epic
>   account login) and needs at least 10 GB of free memory. The MetaHuman
>   used by the scene weighs about 330 MB, of which 138 MB is the editable
>   MetaHuman Character asset.

and to Testing Decisions:

> - The audio-to-mouth offset is logged by the client and checked by a human.
>   The spike measured an estimated −42 to +39 ms.

**Asset storage (`docs/unreal-setup.md`, #314):** that guide puts "the imported
MetaHuman used by the scene" in Git LFS and asks for a review once #189 shows a
MetaHuman's size. The answer is about 330 MB per character: about 3% of the
10 GiB LFS storage, but every full clone also spends that much of the 10 GiB
monthly bandwidth. For the spike, the human chose to keep it local. The team
should decide whether the production patient goes into LFS as the guide says.

## Reproduce

1. `scripts/fetch-livekit-sdk.sh`, then build `ProyectoMedEditor` (see
   `docs/unreal-setup.md`).
2. **Stage 1 (no API keys):**
   - Run `livekit-server --dev`, then `scripts/spike-189/publish-test-voice.sh`.
   - In `/Game/Spike/PatientVoice`, clear `TrackName` on the `PatientVoice`
     component, then start PIE.
3. **Stage 2 (real worker):**
   - Run the "Real-time voice demo runbook" in `README.md`.
   - Mint an observer token for `station-session-<id>` with
     `lk token create --join --room station-session-<id> --identity unreal-observer`
     into `unreal/Saved/PatientVoiceSpike/token.txt`.
   - Set `TrackName = patient-voice`, start PIE and mute the browser tab.

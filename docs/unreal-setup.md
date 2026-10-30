# Unreal Engine project setup

The station client from ADR-013 (#209) lives in `unreal/` as a native Unreal
Engine project. This guide covers the engine version, the Unreal MCP plugin
used as editor-time agent tooling, how to connect Claude Code, and the known
limits. It is the outcome of #188.

## Engine and project

| Item | Value |
| --- | --- |
| Engine | Unreal Engine 5.8 (bootstrapped on 5.8.3), installed through the Epic Games Launcher. Upgrading is a separate decision (ADR-013). |
| Project | `unreal/ProyectoMed.uproject`, a Blank C++ project without starter content. |
| Targets | macOS and Windows desktop. |
| Toolchain | Xcode on macOS, Visual Studio 2022 with the "Game development with C++" workload on Windows. |

Engine-generated artefacts (`Binaries/`, `Intermediate/`, `Saved/`,
`DerivedDataCache/`, `Packaged/`, IDE project files) are ignored in the root
`.gitignore`. Under `Build/`, only each platform's `Resources/` folder
(`Info.Template.plist`, entitlements, icons) is tracked, because packaging
builds the `.app` from it. Regenerate IDE files from the `.uproject` (right-click >
"Generate Xcode/Visual Studio project files").

### Machine prerequisites

- **ASCII-only checkout path.** The Unreal Build Accelerator mangles
  non-ASCII characters in response-file paths (for example `Programación`
  becomes `Programaci  n`), and clang fails with "no such file or directory".
  Keep the repository under a path without accents or other non-ASCII
  characters.
- **Checkout outside iCloud Drive on macOS.** When "Desktop & Documents
  Folders" syncs to iCloud, the File Provider adds `com.apple.FinderInfo` and
  `com.apple.fileprovider.*` extended attributes to the built `.app`, and
  `codesign` fails with "resource fork, Finder information, or similar detritus
  not allowed" (UBT reports "Failed to finalize the .app with Xcode").
  `xattr -cr` does not help: iCloud adds them back during the build. Keep the
  repository (or a `git worktree` of it) under a folder iCloud does not sync,
  for example `~/code`.
- **Metal Toolchain on macOS.** Xcode 26 and later ship the Metal shader
  compiler as a separate component. Without it the editor reports "cannot
  execute tool 'metal' due to missing Metal Toolchain". Install it with
  `xcodebuild -downloadComponent MetalToolchain` and check it with
  `xcrun -sdk macosx metal --version`.
- **One editor instance.** On macOS, double-clicking a `.uproject` while an
  editor is already running (for example, the Project Browser) only brings that
  instance to the front. Quit it first.
- **LiveKit C++ SDK.** The project links the official LiveKit C++ SDK
  (Apache-2.0) as prebuilt libraries that are not committed. Run
  `scripts/fetch-livekit-sdk.sh` once before the first build, and again when
  the pinned version changes. It downloads the macOS and Windows packages,
  checks their SHA-256 and unpacks them into the git-ignored
  `unreal/Source/ThirdParty/LiveKitSDK/{Mac,Win64}`. Without them the build
  stops with a message naming the script. Why this SDK: `docs/spike-189-metahuman-lipsync.md`.
- **Command-line build.** To see compiler errors instead of a silent dialog:
  `"/Users/Shared/Epic Games/UE_5.8/Engine/Build/BatchFiles/Mac/Build.sh" ProyectoMedEditor Mac Development -Project="$PWD/unreal/ProyectoMed.uproject" -WaitMutex`.
- **Editor log on macOS:** `~/Library/Logs/Unreal Engine/ProyectoMedEditor/ProyectoMed.log`.

## Large files: Git LFS

Every binary under `unreal/` (`.uasset`, `.umap`, source art, audio, video,
icons) goes through Git LFS, as configured in the root `.gitattributes`.

- Install once per machine: `brew install git-lfs` on macOS (Git for Windows
  already bundles it), then `git lfs install`.
- `.uasset` and `.umap` are `lockable`: they check out read-only. Run
  `git lfs lock <path>` before editing an asset and `git lfs unlock <path>`
  after pushing it.
- The repository is private on a personal GitHub Free account, which includes
  10 GiB of LFS storage and 10 GiB of LFS bandwidth per month. A MetaHuman
  weighs several GB, so check the LFS usage and budget under GitHub Billing
  before committing one, and avoid repeated full clones.
- CI checkouts do not fetch LFS content unless a job asks for it.

### What goes in Git and what can go elsewhere

Rule: if the Unreal project loads it to open, run, or build, it lives in Git
(through LFS). Working material the project never loads can be shared outside
the repository, for example on a shared Google Drive folder.

| In Git (LFS for binaries) | Outside the repository (for example Google Drive) |
| --- | --- |
| C++ source, config, and `ProyectoMed.uproject` | Raw source files: DCC exports, original audio, layered image files |
| Every `.uasset` and `.umap` the project uses | References, screenshots, and test recordings |
| The imported MetaHuman used by the scene | Installable builds (#197) handed to testers |

Why project assets never travel outside Git:

- Assets reference each other by path. A level points to materials, which
  point to textures; a partial or mismatched copy opens with broken references.
- A commit pins the exact code and assets that fit together. A file copied
  through a shared drive cannot be tied to the commit that needs it.
- Shared drives have no locks. Two people editing the same binary asset lose
  one person's work, because binary assets cannot be merged.
- CI and packaged builds only see what is in the repository.

Keep raw source files outside `unreal/` so they never reach LFS. If the LFS
budget falls short, buy additional GitHub LFS storage first; moving to Perforce
is a separate decision. The scene's MetaHuman, with its shared `MetaHumans/Common`
assets, takes about 353 MB of LFS (#190). The doctor's office (#319) adds about
36 MB: 26 MB of furniture and props (two thirds of it the 1k textures of the two
CC0 props), 8 MB for the Y Bot and the retarget assets, 2 MB for the seated
loop. The running total stays well under the 10 GiB budget.

## Running the station client

The default map is `/Game/Station/Consultation`. `AStationGameMode` is the
project's global default game mode, so every level without its own override
shows the station screens.
It needs a local Phoenix; the station client module (`StationClient`) is the
only code that talks to it, and its interface is documented in
`docs/unreal-station-client.md`.

1. Start Phoenix. The LiveKit values are the local development ones; LiveKit
   itself only has to run for spoken turns (#191):

   ```bash
   ( cd backend && VOICE_MODE=realtime LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret mix phx.server )
   ```

2. Open the editor and press **Play**. The learner sees the Pre-Station Notice,
   then the brief Phoenix serves, where they pick "Treino por texto" or "Treino
   por voz", then the patient and the ten-minute Station Timer. The voice option
   only appears when Phoenix serves `voice_mode: realtime`. These screens, like
   the feedback and "Treino invalidado", are cards in the style of the in-run
   panels: opaque, rounded and outlined, with rounded buttons. The brief's
   scenario and tasks scroll above a footer that keeps both trainings in view.
3. A voice training logs `LogStationRun: Voice credential received for room
   station-session-<id>`; the token itself is never logged.
4. In either training, the "Conversa" panel down the left edge takes typed turns
   (Enter or "Enviar") and shows each turn as a chat bubble, the learner's on the
   right and the patient's on the left, with the reply Phoenix approved. It
   does not depend on the microphone, so a learner who declined audio completes
   the station by typing. Replies to typed turns are shown as text only; speaking
   them is a later slice. In a voice training, spoken turns join the same panel:
   the learner's words show in grey while they speak, then each turn and the
   patient's spoken reply stay in the conversation like typed ones. Speaking
   over the patient stops its voice and mouth at once (#193). A turn the patient
   had not answered yet leaves the panel with its partial reply; an answer
   already given stays. Finishing the station silences the patient too.
5. The "Exames" tab at the top right opens the "Exames solicitados" panel down
   the right edge; its × closes it again. A text training types a request there
   ("exame físico", "eletrocardiograma"); a voice training holds the round
   microphone at the bottom of the panel, or Shift + space bar, and says it
   (#364, push-to-talk as below, #419): the microphone
   turns amber while Phoenix arms the request, then red with a pulse and
   "Gravando 0:03 · solte para enviar" while it records. While the previous spoken
   request still waits for Phoenix, holding it records nothing and reads
   "Aguarde a resposta do pedido anterior". Either way the request
   goes to Phoenix's impresso route, never to the patient, and never joins the
   conversation. Each request is a card with its status ("Solicitando...",
   "Liberado", "Já liberado", "Não disponível"); a released one has "Ver
   documento", which opens the document in a reader over the scene. A request
   Phoenix declines shows Phoenix's feedback and nothing else. Documents a turn
   to the examiner released show under "Outros documentos liberados".
6. "Finalizar estação" under the timer ends the run early; at 00:00 the Station
   Timer ends it. Either way no turn or exam request can be sent any more, and
   the feedback screen shows each criterion with the transcript excerpts that
   support it, under the unofficial educational result notice. The coverage
   counts lead as colored tiles; each criterion is a card with its status as a
   colored label ("Avaliado", "Incerto", "Não observável", "Excluído pelo
   autor"), its points or why it has none, and its excerpts as chat bubbles;
   "Reiniciar estação" stays in a footer under the scrolling result. "Reiniciar
   estação" asks Phoenix to forget the run and, once it confirms, goes back to
   the brief for a new run. Grading needs Phoenix's text provider
   (`LLM_PROVIDER` and its key); for a local check only,
   `JEV_E2E_APPROVING_ADAPTER=true` grades with a fixed result that judges nothing.
7. A training that loses Phoenix is invalidated (#196): nothing can go on
   without it. Phoenix counts as lost when a turn, an exam request, the finish
   or the feedback gets no answer and a check of the session right after gets
   none either. The screen "Treino invalidado" replaces everything, with no
   feedback and no partial result; the patient stops speaking and moving, and
   the room is left. "Reiniciar estação" goes back to the brief at once, and a
   new run starts as soon as Phoenix answers again. Stopping Phoenix while a
   run is open shows this at the next turn, exam request or finish, or, in a
   voice training, as soon as the voice stops with it. Either way the call and
   the check can take up to about 30 s. A voice failure alone does
   not (see "Voice trainings").

Point the client at another Phoenix with `-PhoenixUrl=<origin>` or
`[/Script/StationClient.StationClient] PhoenixBaseUrl` in the game config.

### The consultation scene

- The patient is `/Game/Spike/MHC_Patient/BP_MHC_Patient`. The folder keeps the
  #189 spike name because moving a MetaHuman in the editor crashed it
  (`VisualLookUp`); rename it with plenty of free memory.
- The patient sits in a doctor's office (#319): a desk between the learner and
  the patient, the doctor's chair, the patient's chair, an exam couch, a closed
  cabinet and a few props, all scenery without interaction or readable content.
  The meshes live in `/Game/Station/Office/Furnishings`; the actors sit in the
  `Office` outliner folder of `Consultation`. Room is left free beside the
  patient's chair for a companion (#322).
- The analog desk clock (#425) is `DeskClock` in the `Office` folder, an
  `AStationDeskClock` at 1.2 scale. It stands on the right of the desk, in the
  far half the `StationView` camera sees, well below the patient's face; keep it
  there after any camera or desk change. Its meshes, materials and textures live
  in `/Game/Station/Office/Clock`: Poly Haven's Alarm Clock 01 with the dial
  repainted with Arabic numerals, and the hands pulled out of its rig so each
  points to twelve with its pivot at the dial's centre, the actor's origin. Its
  **Start Sound** and **End Sound** are the Prova simulada beeps in
  `/Game/Station/Audio` (`S_ExamStart`, `S_ExamEnd`), generated by
  `scripts/generate-exam-sounds.py`. The meshes and sounds are set on the placed
  clock, which is what makes the cook take them.
- The room is a closed box (#477): `WallBack`, `WallLeft`, `WallRight` and
  `WallFront` in `M_Paint_Clinic`, `Ceiling` in `M_Ceiling_White` and `Floor` in
  `M_Floor_Vinyl`, all in `/Game/Station/Office/Room`. `WallFront` sits behind the
  learner so the room also holds from the menu camera of #431, and the level has
  no sky, sun or fog left: nothing outside the room can be seen.
- The ceiling is 3 m up, above what `StationView` sees, so the light hangs from
  it. `CeilingLight` in the `Office` folder is `SM_CeilingLight` from
  `/Game/Station/Office/Lighting`, a 2.2 m suspended linear luminaire that runs
  from the desk to near the back wall, with its underside 1.94 m above the floor.
  It sits 90 cm to the learner's right so its far end shows in the top right of
  the view, clear of the HUD's centred timer panel; keep it clear of that panel
  after any change.
- All lighting is movable, so nothing is baked. The `Lighting` folder holds three
  rect lights: `CeilingRectLight` (4500 lm, the main source, under the luminaire),
  `CeilingUplight` (8000 lm, no shadows, on top of it, bounced off the ceiling as
  the room's soft ambient) and `FaceFill` (2600 lm, no shadows, no bounce, aimed
  at the patient's face from above the desk). All three are 5000 K. `FaceFill` is
  what keeps the eyes and mouth readable: the main source is off to one side, so
  check the face from `StationView` after moving either.
- The body plays `A_Patient_Sitting_Idle` in single-node mode: the Mixamo
  "Sitting Idle" variations 2 and 3 joined into one 9.4 s loop (both start and
  end on the same pose, so the joins have no seam), retargeted from the Y Bot to
  the patient. The face keeps the MetaHuman Creator template idle loop
  (`A_Patient_Idle_Face`) in single-node mode, with `useLiveLink` off. The
  project's `MetaHumans/Common` body and face skeletons list the plugin's
  skeletons as compatible so those loops can play.
- The retarget lives in `/Game/Station/Patient/Retarget`: `SK_YBot` and its
  loop, the auto-generated IK Rigs `IK_YBot` and `IK_Patient`, and
  `RTG_YBot_To_Patient` (fuzzy chain mapping, target aligned to the Y Bot's
  T-pose). To retarget another clip, right-click it in the Content Browser and
  pick **Retarget Animations** with that retargeter.
- The seated pose fixes the distance from the patient's hips to the feet, so the
  chair and the patient are fitted together: the patient actor sits 38 cm below
  the floor origin and `SM_VisitorChair` has a 41.5 cm seat. Changing the
  patient or the loop means fitting both again, checked from the side.
- In a voice training (#191) the game swaps the face to
  `UStationPatientFaceAnim` at runtime: it keeps the same idle loop and, while
  the patient speaks, lays the jaw, mouth, lips, tongue and teeth controls
  solved from the voice (StreamingADA, as in the #189 spike) over it. The
  patient is found as the actor with a skeletal mesh component named `Face`, so
  the level needs no extra setup, and no Live Link source is involved.
- In a voice training the patient also looks at the learner (#449). The game
  adds `UStationPatientGaze` to the patient. That component swaps the body to
  `UStationPatientBodyAnim`, which plays the same seated idle and turns
  `neck_01`, `neck_02` and `head` over it. The face copies those joints from the
  body in its post-process Anim Blueprint, so it turns with them. It also sets
  the face's eye-look controls (`CTRL_expressions_eyeLook*`) in
  `UStationPatientFaceAnim`. The mouth controls are left alone. The look target
  is read from the `StationView` camera every frame, so a re-framed camera needs
  no change.
  - While the learner holds the talk key the patient looks at them 3–8 s at a
    time, with glances away of 0.4–1.2 s.
  - While it answers, the looks last 2–5 s and the glances 0.7–1.8 s.
  - When nobody speaks the idle loops keep the gaze, with a look at the learner
    of 0.8–2 s every 4–10 s.
  - Glances go down, aside or at nothing, at most 25° from the learner.
  - The head takes half of a turn, at most 25° to a side, 12° up and 20° down,
    and the eyes do the rest, at most 30° to a side, 20° up and 25° down. Both
    eyes get the same controls, so they never cross.
  - The timings and limits live in `Station/Patient/StationGaze.cpp`.
  - `ProyectoMed.PatientGaze.Scene` checks the head turn and the eye angles on
    the real MetaHuman, headless.
- The learner sees the scene through the `CameraActor` tagged `StationView`
  with a seated doctor's eyes: 1.20 m above the floor, about 1.2 m from the
  patient's head, 6.5° down, with an 80° horizontal field of view and no look
  around. Tune it on the actor's transform and its camera component's
  **Field Of View**. The framing keeps the patient's head below the HUD's timer
  and **Finalizar estação** panel, clear of the conversation panel on the left
  and of the exam drawer on the right, with the desk in view; check all three
  after any change.
- Frame time on the reference Mac (Apple M4 Pro, 24 GB, macOS 27), Development
  build, `-game -windowed -ResX=1920 -ResY=1080`, seated patient and the office
  lit by its ceiling light (#477), 1740 frames after one second of warm-up:
  15.0 ms mean (about 67 fps), 15.0 ms median, 15.5 ms p95, 19.9 ms worst. The GPU
  bounds it (14.3 ms mean); the game thread takes 1.4 ms. A second run gave the
  same mean within 0.1 ms. The #319 room, open to the sky, took 15.4 ms mean and
  22.3 ms p95. Measured with `-csvCaptureFrames=1800 -csvExitOnCompletion`, with
  other builds running on the same Mac; the CSV lands in
  `~/Library/Application Support/Epic/UnrealEngine/5.8/Saved/Profiling/CSV`.

#### Third-party assets in the scene

| Asset | Source | Author | Licence | Link |
| --- | --- | --- | --- | --- |
| Y Bot and the "Sitting Idle" animations | Mixamo | Adobe | Mixamo terms: royalty-free in projects and shipped products; the raw files are not redistributed | https://www.mixamo.com |
| Potted Plant 02 (`SM_Plant_Floor`) | Poly Haven | Rico Cilliers | CC0 | https://polyhaven.com/a/potted_plant_02 |
| Stationery Supplies (cup and pens of `SM_PenCup`) | Poly Haven | Mateusz Sadek | CC0 | https://polyhaven.com/a/stationery_supplies |
| Alarm Clock 01 (`SM_AlarmClock_*`), dial repainted with Arabic numerals in Inter | Poly Haven | James Ray Cock (model and textures), Yann Kervran (rig); Inter by The Inter Project Authors | CC0; Inter is SIL OFL 1.1 | https://polyhaven.com/a/alarm_clock_01 |
| Prova simulada start and end beeps (`S_ExamStart`, `S_ExamEnd`) | Generated by `scripts/generate-exam-sounds.py` | proyectoMed | CC0 1.0 | — |

The rest of the furniture and the ceiling light (#477) were modelled for the
project in Blender. Raw sources
stay outside the repository: the `.blend`, the exported FBX files, the layout
used to place them, the Mixamo downloads, and the clock's dial and export scripts.

### Voice trainings

- First launch shows the microphone disclosure. **Permitir microfone** asks
  macOS for the microphone; **Agora não** skips it, and choosing **Treino por
  voz** asks then. The answer is remembered in `GameUserSettings.ini`
  (`[StationVoice] bMicrophoneDisclosureShown`); delete that line to see the
  disclosure again. On macOS the editor asks for the microphone as
  UnrealEditor, and **System Settings › Privacy & Security › Microphone**
  resets it.
- To try a voice training without paid providers, start the local stack in a
  terminal with `scripts/run-voice-stack.sh` and open the editor; the stack's
  Phoenix is on the default `http://127.0.0.1:4000`. The fake transcription
  hears every utterance held on the space bar as "Qual é o seu nome?" and the patient answers "Meu
  nome é Carlos." with a tone instead of a voice, so the mouth moves with
  the loudness of the tone. Real speech needs the real-time voice runbook in
  the README.
- The microphone is push-to-talk (#419): the voice worker hears the learner
  only while the **space bar**, or the "Segure para falar (Espaço)" button
  above the typed box (for touch screens), is held, and releasing it sends the
  turn at once, without waiting for the end of speech. The button reads
  "Falando... solte para enviar" while held. While the patient answers (from
  the learner's sent turn, spoken or typed, until the reply ends, or while its
  voice plays), a
  single press does nothing and the button reads "Toque e segure para
  interromper"; tap and then hold to cut the patient and talk. The exam
  microphone and Shift + space bar follow the same rule. While the typed-reply box has the keyboard focus the space
  bar types a space; click the scene to give it back to the talk key. In the
  station client the space bar never presses the focused button, on any of its
  screens (Enter still does), and switching to another app releases a held key.
- When the editor loads a run the CPU can pass 70%. A local `livekit-server`
  started without `agents: target_load: 2` then sends the job to no worker
  (its log reads `no servers available`) and the run reads "A voz caiu"; start
  it as the README's real-time voice runbook shows. `scripts/run-voice-stack.sh`
  already does.
- The voice status under the timer reads "Conectando a voz..." until the
  worker joins, then "Voz conectada". While LiveKit retries the connection or
  the worker is gone it reads "Reconectando a voz..." and the microphone stops.
  If the worker has not joined within 20 seconds, or the voice has not come back
  within 10, it reads "A voz caiu. O tempo da estação continua." for the rest of
  the run; the station timer keeps running and the learner continues in
  writing. A transcription failure stops the worker and reads the same. Each
  of these voice failures checks Phoenix once: when Phoenix does not answer
  either, the run is invalidated instead (see step 7 above). So stopping the
  whole local stack with Ctrl-C, which stops its Phoenix too, invalidates the
  run; stopping only `livekit-server` shows the voice
  loss. The microphone also stops as soon as the run ends, with
  "Finalizar estação" or the timer, before the feedback loads. If the system
  microphone will not open, it reads "Microfone indisponível. Continue por
  escrito." for the rest of the run, without trying the device again; the
  next run tries again. The voice loss message wins when both apply.
- Packaged macOS builds ask for the microphone through
  `NSMicrophoneUsageDescription` in `unreal/Build/Mac/Resources/Info.Template.plist`;
  without it macOS refuses the microphone without asking. The editor asks as
  UnrealEditor and needs nothing.

## Unreal MCP plugin

Unreal MCP is Epic's Experimental plugin that runs a Model Context Protocol
server inside the editor. ADR-013 allows it as development tooling only: it is
never part of the shipped client, never enabled in packaged builds, and never a
runtime dependency.

### Plugins

Enable in **Edit > Plugins**, then restart the editor:

- **Unreal MCP** (`ModelContextProtocol`). The Toolset Registry is enabled with
  it.
- **All Toolsets** (`AllToolsets`), an editor-only aggregator that enables
  every toolset plugin, including `SceneTools`, `ActorTools`, `EditorToolset`,
  and `AutomationTestToolset`.

Both are already enabled in `ProyectoMed.uproject`. Their entries carry
`"TargetAllowList": ["Editor"]` because `ModelContextProtocol` contains
**runtime** modules (`ModelContextProtocol`, `ModelContextProtocolEngine`)
that a game target would otherwise build; the allow list keeps game and
packaged targets from building or loading them.

### Server settings

**Edit > Editor Preferences > General > Model Context Protocol** (the list is
alphabetical; with a localized editor the setting labels are translated, so
searching for "mcp" only finds the URL path):

| Setting | Value |
| --- | --- |
| Auto Start Server | On |
| Server Port Number | `8000` (default) |
| Server URL Path | `/mcp` (default) |
| Enable Tool Search | On (default) |

These are per-user settings stored under `Saved/`. The project ships
`bAutoStartServer=True` as its default in
`unreal/Config/DefaultEditorPerProjectUserSettings.ini`, so a fresh checkout
starts the server with the editor. Changing the setting takes effect on the
next editor start; until then, run `ModelContextProtocol.StartServer` in the
editor console. A healthy start logs
`LogHttpListener: Created new HttpListener on 127.0.0.1:8000`.

The server speaks Streamable HTTP at `http://127.0.0.1:8000/mcp`. It binds to
loopback and rejects non-loopback `Origin` headers. Never change
`[HTTPServer.Listeners] DefaultBindAddress` away from loopback: the server has
no authentication.

## Connecting Claude Code

With the editor open and the server running, from the repository root:

```bash
claude mcp add --transport http unreal-mcp http://127.0.0.1:8000/mcp
```

Alternatively, run `ModelContextProtocol.GenerateClientConfig ClaudeCode` in
the editor console. It writes `unreal/.mcp.json`, which Claude Code picks up
when launched from `unreal/`.

With tool search on, the agent sees three meta-tools: `list_toolsets`,
`describe_toolset` (argument `toolset_name`), and `call_tool`. Toolset names
are qualified, but `call_tool` takes the qualified `toolset_name` plus the
short tool name (for example `find_actors` or `DiscoverTests`); a prefixed tool
name fails with "Unknown tool". The toolsets used to verify this setup are:

- `editor_toolset.toolsets.scene.SceneTools` and
  `editor_toolset.toolsets.actor.ActorTools` for the open level.
- `AutomationTestToolset.AutomationTestToolset`: call `DiscoverTests` once per
  session, then `ListTests`, `RunTests` or `RunTestsByFilter` (for example
  `StartsWith:System.Core`), and `GetTestStatus`/`GetTestResults`. For
debugging, `npx @modelcontextprotocol/inspector` connects with the
"Streamable HTTP" transport to the same URL.

Useful editor console commands: `ModelContextProtocol.StartServer`,
`ModelContextProtocol.StopServer`, `ModelContextProtocol.RefreshTools`.

## Known limits

- **Experimental.** The plugin, the Toolset Registry, and their APIs can change
  or break between engine versions.
- **No authentication.** Anything that can reach the port controls the editor.
  Keep it on loopback and never expose or forward the port.
- **Serial tool calls.** Calls run one at a time on the editor game thread. Do
  not issue overlapping tool calls from one or several agents.
- **Deleting or renaming assets crashes the editor.** In UE 5.8 the
  `SemanticSearch` index aborts (`faiss::IndexIDMap2Template::reconstruct`)
  when an asset is deleted, renamed or replaced, from a tool or from a script.
  Import each asset once under its final name. To remove one, delete the file
  with the editor closed.
- **Blender FBX scale.** Export meshes in metres with **Apply Scalings: All
  Local** (`apply_scale_options="FBX_SCALE_NONE"`); the other
  options import 100 times too small or too large.
- **Licensed Technology.** The editor warns that data sent through the plugin
  to a connected LLM service is Licensed Technology under the UE EULA; the
  developer is responsible for ensuring the LLM provider does not use it as
  training input (UE EULA Section 6(e)).
- **Restart for new C++ functions.** Live Coding picks up changes to existing
  function bodies, but a new `UFUNCTION` needs a full editor restart. After
  adding or changing a Python toolset, run `ModelContextProtocol.RefreshTools`.

## Verification checklist

Run on a real machine after setup; these are the acceptance criteria of #188.

1. **Connection:** `claude mcp list` shows `unreal-mcp` as connected, and the
   agent lists toolsets.
2. **Scene tool:** the agent runs a scene tool (for example, listing the actors
   in the open level) and the result matches the editor's Outliner.
3. **Automation test:** the agent runs at least one automation test through
   MCP and reports its result, matching **Tools > Session Frontend >
   Automation**.
4. **Loopback:** while the editor runs,
   `lsof -nP -iTCP:8000 -sTCP:LISTEN` (macOS) or
   `netstat -ano | findstr :8000` (Windows) shows only `127.0.0.1` or `[::1]`,
   never `*` or `0.0.0.0`.
5. **Absent from packaged builds:** package a Development build
   (**Platforms > <platform> > Package Project**, or `RunUAT.sh BuildCookRun
   -platform=Mac -clientconfig=Development -build -cook -stage -pak -package -archive`,
   see "Packaging a client build"),
   run it, and confirm that nothing listens on port 8000 and that the game
   binary contains no `ModelContextProtocol` or `ToolsetRegistry` strings.
   (`HttpListener` is expected in Development builds: `StationClient` links
   `HTTPServer` outside Shipping for its fake-Phoenix automation tests.)
   Search both ASCII and UTF-16LE, because Unreal
   stores `TEXT()` literals as UTF-16; `LogInit` is a good positive control.

## Packaging a client build

Installable builds for testers (#197) are Development builds. Code signing,
store distribution, and auto-update are out of scope. Share the archived build
outside the repository (see "What goes in Git and what can go elsewhere").

### macOS

From the repository root, with the LiveKit SDK fetched and the editor closed:

```sh
"/Users/Shared/Epic Games/UE_5.8/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
  -project="$PWD/unreal/ProyectoMed.uproject" -platform=Mac \
  -clientconfig=Development -build -cook -stage -pak -package -archive \
  -archivedirectory="$PWD/unreal/Packaged" -unattended -utf8output
```

The result is `unreal/Packaged/Mac/ProyectoMed.app` (about 1.7 GB).

- **`-package` is required on macOS.** `-archive` copies
  `unreal/Binaries/Mac/ProyectoMed.app`. Without `-package`, that `.app` holds
  only the executable (about 425 MB): no paks, no engine dylibs, no
  `liblivekit.dylib`, and macOS refuses to open it with "ProyectoMed cannot be
  opened because of a problem" (`Library not loaded: @rpath/liblivekit.dylib`
  in the crash report). `-package` folds the staged content into that `.app`.
- **Runs without Unreal Engine.** Every non-system dylib the packaged app
  loads comes from inside the bundle (`Contents/UE/...`); check with
  `lsof -p <pid> | grep dylib` while it runs.
- **The app is ad-hoc signed** ("Sign to Run Locally"). On another Mac,
  Gatekeeper blocks a downloaded copy: right-click the app > **Open**, or run
  `xattr -dr com.apple.quarantine ProyectoMed.app`.
- **Sandbox.** Development builds use
  `unreal/Build/Mac/Resources/Sandbox.Server.entitlements`, which allows the
  network and the microphone (`com.apple.security.device.audio-input`);
  `Info.Template.plist` declares `NSMicrophoneUsageDescription`. Logs go to
  `~/Library/Containers/com.YourCompany.ProyectoMed/Data/Library/Logs/ProyectoMed/`.
  Shipping builds would use `Sandbox.NoNet.entitlements`, which has no network
  access and could not reach Phoenix.

### Windows

Not yet verified on a Windows machine. The expected command, from a Developer
Command Prompt with the LiveKit SDK fetched:

```bat
"C:\Program Files\Epic Games\UE_5.8\Engine\Build\BatchFiles\RunUAT.bat" BuildCookRun ^
  -project="%CD%\unreal\ProyectoMed.uproject" -platform=Win64 ^
  -clientconfig=Development -build -cook -stage -pak -archive ^
  -archivedirectory="%CD%\unreal\Packaged" -unattended -utf8output
```

`LiveKitSDK.Build.cs` stages the LiveKit DLLs next to `ProyectoMed.exe`
through `RuntimeDependencies`.

### Choosing the environment

Point a packaged build at Phoenix with `-PhoenixUrl=<origin>`, for example
`open ProyectoMed.app --args -PhoenixUrl=https://phoenix.example.org` or
`ProyectoMed.exe -PhoenixUrl=https://phoenix.example.org`. The LiveKit URL
comes from Phoenix in each voice credential, so neither needs a rebuild.

### What a packaged build listens on

Nothing listens on port 8000 (the editor-only Unreal MCP server). Development
builds open the Unreal Insights trace control port, `TCP *:1985`, on every
interface; it is engine tooling, not part of the client, and Shipping builds
do not include it.

### Known toolchain issue: "Failed to finalize the .app with Xcode"

**Symptom.** Building the game target through UnrealBuildTool compiles and
links the game binary, then fails at the final `.app` step: UBT reports
"Failed to finalize the .app with Xcode" (UAT exit 6). Because the finalize
step fails, UBT never writes `unreal/Binaries/Mac/ProyectoMed.target`, so a
later `BuildCookRun -skipbuild -cook -stage` cooks with no errors and then
stops with "Missing receipt .../Binaries/Mac/ProyectoMed.target" (UAT
exit 103).

**Root cause (verified).** The checkout was under `~/Documents`, which iCloud
Drive syncs. The File Provider adds `com.apple.FinderInfo` and
`com.apple.fileprovider.fpfs#P` extended attributes to the `.app`, and
`codesign` refuses it with "resource fork, Finder information, or similar
detritus not allowed". `xattr -cr` does not help because iCloud adds them back
during the build. The Xcode version is not the cause: the failure reproduces on
Xcode 26.6.

**Fix.** Build from a checkout, or a `git worktree`, under a folder iCloud does
not sync (see "Machine prerequisites"), for example
`~/code/proyectoMed-worktrees/<name>`. Copy `unreal/Source/ThirdParty/LiveKitSDK/Mac`
into it from an existing checkout or fetch it again. From there, the
`BuildCookRun ... -build -cook -stage -pak -package -archive` command in
"Packaging a client build" produces a runnable `ProyectoMed.app`, and nothing
listens on port 8000 while it runs. Verified on UE 5.8.4 with Xcode 26.6 on
Apple silicon (#262).

**Diagnosing.** Search the UBT log for "detritus" first. If it is there, move
the checkout. The original report (UE 5.8.3, Xcode 27) showed the Xcode scheme
pre-action "Touch UBT generated tiles" failing during `ApplePostBuildSync`
(exit 65), while running the same `xcodebuild build -workspace
unreal/Intermediate/ProjectFiles/ProyectoMed_Mac_ProyectoMed.xcworkspace
-scheme ProyectoMed -configuration Development -destination
generic/platform=macOS UE_XCODE_BUILD_MODE=PostBuildSync` by hand succeeded.
Whether that Xcode 27 failure has the same cause is not yet confirmed. If the
log has no "detritus" and the checkout is outside iCloud, record the Xcode
version and the full `ApplePostBuildSync` output in #262.

All Toolsets enables the GameFeatures plugin in the editor, so the cook (an
editor process) requires a `GameFeatureData` rule in the Asset Manager. The
project ships it in `unreal/Config/DefaultGame.ini`.

## Recorded decisions

These come from the orchestration session for #186 and complement ADR-013:

- **In-client UI is native Unreal UMG.** The station interface (Pre-Station
  Notice, Station Timer, text input, exam and impresso views, feedback) is
  built with UMG inside the client, not as embedded React or a web view.
- **macOS and Windows first.** The MVP targets macOS and Windows desktop.
  Tablets and mobile are a later phase, consistent with the out-of-scope list
  in #186.

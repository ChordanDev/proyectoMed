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
assets, takes about 353 MB of LFS (#190).

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
   only appears when Phoenix serves `voice_mode: realtime`.
3. A voice training logs `LogStationRun: Voice credential received for room
   station-session-<id>`; the token itself is never logged.
4. In either training, the conversation panel at the bottom takes typed turns
   (Enter or "Enviar") and shows each turn with the reply Phoenix approved. It
   does not depend on the microphone, so a learner who declined audio completes
   the station by typing. Replies to typed turns are shown as text only; speaking
   them is a later slice.
5. The "Exames" button at the top right opens the exam panel. A request typed
   there ("exame físico", "eletrocardiograma") goes to Phoenix's impresso route,
   never to the patient, and never joins the conversation. Phoenix decides what
   is released: findings and impressos appear under "Documentos liberados", and
   a request Phoenix declines is shown as declined, with nothing in its place.
6. "Finalizar estação" under the timer ends the run early; at 00:00 the Station
   Timer ends it. Either way no turn or exam request can be sent any more, and
   the feedback screen shows each criterion with the transcript excerpts that
   support it, under the unofficial educational result notice. "Reiniciar
   estação" asks Phoenix to forget the run and, once it confirms, goes back to
   the brief for a new run. Grading needs Phoenix's text provider
   (`LLM_PROVIDER` and its key); for a local check only,
   `JEV_E2E_APPROVING_ADAPTER=true` grades with a fixed result that judges nothing.

Point the client at another Phoenix with `-PhoenixUrl=<origin>` or
`[/Script/StationClient.StationClient] PhoenixBaseUrl` in the game config.

### The consultation scene

- The patient is `/Game/Spike/MHC_Patient/BP_MHC_Patient`. The folder keeps the
  #189 spike name because moving a MetaHuman in the editor crashed it
  (`VisualLookUp`); rename it with plenty of free memory.
- The patient plays copies of the MetaHuman Creator template idle loops
  (`/Game/Station/Patient/Animations`) in single-node mode, with `useLiveLink`
  off. The project's `MetaHumans/Common` body and face skeletons list the
  plugin's skeletons as compatible so those loops can play. Lip sync (#191) has
  to blend the face idle with Live Link.
- The learner sees the scene through the `CameraActor` tagged `StationView`,
  standing 1.40 m from the patient at 1.62 m with a 70° field of view. Both
  stand because MetaHuman Creator ships no seated animation.

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
   -platform=Mac -clientconfig=Development -build -cook -stage -pak -archive`),
   run it, and confirm that nothing listens on port 8000 and that the game
   binary contains no `ModelContextProtocol`, `ToolsetRegistry`, or
   `HttpListener` strings. Search both ASCII and UTF-16LE, because Unreal
   stores `TEXT()` literals as UTF-16; `LogInit` is a good positive control.

## Known toolchain issue: Xcode 27 and macOS packaging

With UE 5.8.3 and Xcode 27, building the game target through UnrealBuildTool
fails at the final `.app` step: the generated stub Xcode project's pre-action
"Touch UBT generated tiles" fails and UBT reports "Failed to finalize the .app
with Xcode". The game binary itself compiles and links. Running the same
`xcodebuild build -workspace
unreal/Intermediate/ProjectFiles/ProyectoMed_Mac_ProyectoMed.xcworkspace
-scheme ProyectoMed -configuration Development -destination
generic/platform=macOS UE_XCODE_BUILD_MODE=PostBuildSync` by hand finalizes the
`.app`, and `BuildCookRun -skipbuild -cook` then cooks with no errors, but
staging still fails with "Missing receipt .../Binaries/Mac/ProyectoMed.target"
because UBT never writes the receipt after the failed finalize step. Packaging
and distribution are out of scope for #188; the fix is tracked in #262.

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

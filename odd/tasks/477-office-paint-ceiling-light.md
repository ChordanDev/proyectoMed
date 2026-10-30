# Paint the Office, Ceiling and Ceiling Light (#477)

Objective: finish the #319 room shell with painted walls, a ceiling and a ceiling light that lights the scene. Branch `feat/477-office-paint-ceiling-light` from `origin/develop`, PR to `develop` with `Closes #477`.
Delivery: `ask-on-risk`. Checks: rendered views from `StationView`, the Unreal automation specs that touch the scene, a frame-time measurement, and a human-approved PIE screenshot.

## Specs

- S1 (issue, business): "The walls are painted in a calm, neutral clinic colour, and the room no longer looks like a blockout."
- S2 (issue, business): "The room has a ceiling, so no void or sky shows from the learner's seat or from the menu view."
- S3 (issue, business): "A ceiling light is visible as an object in the room, and it is what lights the scene."
- S4 (issue, business): "The patient's face stays well lit and easy to read, with no harsh shadow over the eyes or mouth. Dialogue comes first."
- S5 (issue, business): "A human approves a PIE screenshot from the learner's seat."
- S6 (issue, technical): "The lighting stays dynamic and adds no baked lighting data to LFS."
- S7 (issue, technical): "The frame time on the reference Mac (24 GB Apple Silicon) is measured again and recorded in `docs/unreal-setup.md`. The baseline from #319 is 15.4 ms mean, 22.3 ms p95."
- S8 (issue, technical): "New assets follow #319: the ceiling light is built in Blender through the Blender MCP or comes from a CC0 source, `.blend` sources stay outside the repository, and every third-party asset is listed with its licence."
- S9 (issue, technical): "The camera tagged `StationView` and the patient's framing do not change."
- S10 (issue, technical): "`Consultation.umap` is locked with `git lfs lock` while editing, because it is binary and cannot be merged."

## Tasks

| ID | Specs | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S10 | inline | done | Lock ID 60282893 taken before any edit |
| T2 | S8 | inline (Blender MCP) | done | `SM_CeilingLight`, 104 faces, source in `~/Documents/Programacion/proyectoMedBlender` (L4, L8) |
| T3 | S1, S2, S3, S6, S9 | inline (Unreal MCP, editor Python) | done | Level diff against the baseline (L6, L9) |
| T4 | S3, S4 | inline (Unreal MCP, PIE `HighResShot`) | done; awaits S5 | L7, L8 |
| T5 | S7 | inline | done | L10; docs updated |
| T6 | S5 | human | pending | PIE screenshot sent to the human |

## Log

- L1 (2026-10-30, request): Implement issue #477 of ChordanDev/proyectoMed: "Paint the doctor's office and add a ceiling and a ceiling light". Human request quoted in the issue: "pintar el consultorio y ponerle techo y una luz".
- L2 (2026-10-30): #425 merged through PR #452, so the issue's blocker is gone. `unreal-mcp` refuses connections and the Blender addon is not running. No editor is open.
- L3 (2026-10-30): The level holds walls 3 m tall, open on the learner's side (x -20), and the template floor grid. The sun enters through that open side, so it was the face's key light. `StationView`'s top edge reaches about 2.25 m at the back wall, so no ceiling at 3 m can show from the seat: S3 needs a hanging fixture. #431's `MenuView` must frame the doctor from the patient's side, which looks at the open side, so S2 needs a fourth wall; `WallFront` was added.
- L4 (2026-10-30): Blender was opened by hand; its addon auto-starts the MCP server. `SM_CeilingLight` is a 2.2 x 0.16 m suspended linear luminaire with its pivot at the ceiling. It runs along the view so one fixture can sit over the patient's zone and still reach the frame.
- L5 (2026-10-30): `set_properties` takes `values` as a JSON string. A dict fails silently with `False`. `overrideMaterials` set that way is stored but only renders after a level reload. Console commands, including `py <file>`, go through the status bar's Cmd box with `SlateInspectorToolset.Type`.
- L6 (2026-10-30): Removed DirectionalLight, SkyLight, SkyAtmosphere, VolumetricCloud, ExponentialHeightFog and SM_SkySphere. No source references them and none can be seen in a closed room. `Floor` moved from the template grid to `M_Floor_Vinyl`, because S1 says the room must no longer look like a blockout.
- L7 (2026-10-30): 4300 K read as orange, so all lights moved to 5000 K. A 14 cm wide source cast hard shadows on the desk; `sourceWidth` went to 60 cm. `CeilingUplight` lifted the upper walls and ceiling through Lumen. The patient's orange skin comes from the template MetaHuman and belongs to #474.
- L8 (2026-10-30): The HUD's timer panel is centred at the top of the screen (`UStationHudWidget::RebuildWidget`), so a fixture on the view axis would be hidden during a run. The fixture moved to y 90 and was lowered 6 cm so its far end shows at the top right. That darkened the eye sockets, so `FaceFill` moved to (115, 0, 172) and rose to 2600 lm.
- L9 (2026-10-30): Level diff after the edit: `StationViewCamera` stays at (70, 0, 120), pitch -6.5, FOV 80, tag `StationView`; `Patient` stays at (200, 0, -38), yaw 90. No `BuiltData` asset exists. 19/19 `ProyectoMed.PatientGaze` specs pass, including both `Scene` specs on the real MetaHuman.
- L10 (2026-10-30): Frame time with the #319 command, read from its CSV metadata. Dropping the first 60 frames reproduces the baseline exactly (15.4 mean, 22.3 p95, 23.0 worst). Final scene, two runs: 14.9 and 15.0 ms mean, 15.4 and 15.5 ms p95, 42.2 and 19.9 ms worst, 14.3 ms GPU, 1.4 ms game thread. Other sessions were building and running Unreal on the same Mac.

# Doctor's Office Scene (#319)

Objective: seat the MetaHuman patient across a desk in a believable doctor's office. Branch `feat/319-doctors-office` from `origin/develop`, PR to `develop` with `Closes #319`.
Delivery: `ask-on-risk`. Checks: the Unreal automation specs that touch the scene or camera, a frame-time measurement, and human PIE plus packaged checks.

## Specs

- S1 (issue, business): "The scene reads as a doctor's office at first glance: a desk between learner and patient, the doctor's chair, the patient's chair, an exam couch, and typical office props."
- S2 (issue, business): "The patient is seated in the patient's chair across the desk, facing the learner."
- S3 (issue, business): "While seated, the patient keeps an idle, alive presence: breathing, small posture shifts and natural blinking, never a frozen pose and never a visible loop seam."
- S4 (issue, business): "The learner sees the scene from a seated doctor's eyes, about 1.2 m from the patient, with the patient's face and upper body framed as in a real consultation."
- S5 (issue, business): "Nothing in the room (props, monitor, desk edge) hides the patient's face or mouth from the learner's view."
- S6 (issue, business): "Props carry no readable clinical content: no charts, posters, screens or documents that suggest findings, diagnoses or case facts the Station Package did not provide."
- S7 (issue, business): "The office adds no interaction: props and the exam couch are scenery only."
- S8 (issue, technical): "The camera tagged `StationView` sits at a seated eye height of about 1.20 m (tunable, documented) and about 1.2 m from the patient's head; the station client module and its public interface do not change."
- S9 (issue, technical): "during a spoken turn the face lip-syncs from the `PatientVoice` Live Link subject exactly as in #191 while the body plays the seated idle. Verified by a human in PIE and in a packaged build on macOS and Windows."
- S10 (issue, technical): "Seated animations are retargeted to the MetaHuman body skeleton; the patient's hands, hips and feet rest on the chair, desk or floor without visible interpenetration."
- S11 (issue, technical): "The scene holds a stable frame rate on the reference Mac (24 GB Apple Silicon) with the MetaHuman seated and the office lit; the measured frame time is recorded."
- S12 (issue, technical): "Every asset the scene loads lives in Git LFS under `unreal/`"; "raw sources (DCC files, capture takes) stay outside the repository"; "The size added to LFS by props and animations is measured and recorded in `docs/unreal-setup.md` against the 10 GiB budget before the assets are committed."
- S13 (issue, technical): "Every third-party asset is listed with its source, author, licence and a link".
- S14 (decisions, 2026-10-28): Mixamo animations retargeted with the IK Retargeter; furniture "(desk, both chairs, exam couch, cabinet) is modeled in Blender with Claude through the Blender MCP server"; small props from CC0 sources; "a neutral Brazilian consultation room"; "Look-around: none."
- S15 (session brief): leave room beside the patient's chair for #322 (a companion) and a desk spot for #425 (a desk clock), without implementing either. Do not change StationClient, `StationRunFlow.cpp` (PR #430) or `StationScreens.cpp` (PR #435).
- S16 (human, 2026-10-29): "usá Sitting Idle-2 como loop principal y Sitting Idle-3 como variación".

## Tasks

| ID | Specs | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S16 | inline | done | Clip comparison in Blender (Log L3) |
| T2 | S1, S5, S7, S14, S15 | inline (Blender MCP) | done | Log L5, L7, L8; 1264b5e |
| T3 | S12, S13 | inline | done | about 36 MB of LFS; licences in docs; 3d839c6 |
| T4 | S2, S3, S9, S10, S16 | inline (Unreal MCP + headless Python) | done; S9 needs the human PIE and packaged check | Log L9; 1437242, 608a602 |
| T5 | S4, S5, S6, S8 | inline (Unreal MCP) | done | Log L10; 2cf708f |
| T6 | S11, S12, S13, docs | inline | done | Log L11; 98/98 specs |

## Log

- L1 (2026-10-29, request): Implement GitHub issue #319 in ChordanDev/proyectoMed: "Seat the patient across a desk in a believable doctor's office" (full brief in the session; decisions in issue comment 6480781664).
- L2 (2026-10-29): Blender connected (addon protocol 15, Blender 5.4.0 Alpha); unreal-mcp refuses connections. Raw Mixamo clips live in `~/Documents/Programacion/proyectoMedMixamo`, outside the repository.
- L3 (2026-10-29): Clip comparison. Sitting Idle-2 (6.4 s) and Sitting Idle-3 (3.0 s) share one base pose: hips at 0.617 m, feet 0.416 m apart, seat contact at 0.434 m on the Y Bot. Both loop without a seam and keep the hands at least 55 cm from the head. Sitting Idle has a lower, different pose; Sitting is a 1.2 s loop. Both were discarded.
- L4 (2026-10-29): The human chose Idle-2 as the main loop and Idle-3 as the variation (S16).
- L5 (2026-10-29): Furniture modeled in Blender through the MCP:
  - Owned pieces: SM_Desk (1.20 x 0.60 x 0.75 m, with a modesty panel at mid-depth), SM_Chair_Patient (seat at 0.44 m), SM_Chair_Doctor (swivel chair), SM_ExamCouch (1.85 x 0.62 x 0.80 m, head section raised 25°), SM_StepStool, SM_Cabinet (closed two-door, 0.80 x 0.40 x 1.60 m), SM_Laptop (screen off), SM_PaperPad (blank), SM_PedalBin and SM_SanitizerDispenser.
  - CC0 props from Poly Haven: SM_Plant_Floor (Potted Plant 02 by Rico Cilliers, https://polyhaven.com/a/potted_plant_02; the soil decimated to 8%) and SM_PenCup (the cup and three pens from Stationery Supplies by Mateusz Sadek, https://polyhaven.com/a/stationery_supplies).
  - A desktop monitor was tried and replaced with a laptop, because the monitor filled the left third of the view. The keyboard and a succulent were dropped to keep the frame light.
  - Layout preview (Blender metres, the camera looks along +Y): room 3.7 x 4.2 m; desk at the origin; patient chair at y 0.668; Y Bot reference at y 0.70, head centre about (0, 0.60, 1.15); couch along the left wall; cabinet on the back wall, right.
  - Free for #322: x 0.4-1.0 beside the patient's chair. Free for #425: the doctor's right front desk corner, around (0.40, -0.15).
  - StationView preview: (0, -0.60, 1.20), 1.20 m from the head, pitched 10° down so the desk's far edge shows, 70° horizontal FOV. A level camera at this FOV leaves the desk out of the frame.
- L6 (2026-10-29): Each piece exported as FBX with its pivot at the bottom centre: about 13.3 MB in total, of which 10.3 MB is the plant (embedded 1k textures). They live in `~/Documents/Programacion/proyectoMedBlender/fbx`, with `doctors_office_319.blend` and `layout.json` (Blender placements). No editor is running and nothing listens on :8000, so T4 and T5 wait for the human to open this worktree in Unreal.
- L7 (2026-10-29, human): "igual fijate que hay cosas que ni se van a ver, osea solo hay que dejar lo que se vé. La silla del doctor en las estaciones no se ve, solo se vería en el menú que dijimos que se vea al doctor sentado esperando algun paciente. Despues, el monitor está flotando, ponele algo que lo sostenga y eso que lo sostiene va a tapar la esclaerita para subirse a la camilla asi que tambien la podemos sacar" / "Na, pero la camilla está bueno que se vea, solo dije que saques la escalerita para subir".
  Applied:
  - SM_StepStool was removed.
  - A 21.5" monitor on a stand hid the whole couch from StationView, so the laptop stays instead. It moved back to (-0.40, 0.17) so its base and keyboard rest visibly on the desk and nothing floats. Its lid tops out at 0.99 m, below the couch in the view.
  - SM_Chair_Doctor stays: S1 names it, and #431 needs it for the seated doctor on the menu.
  - FBX set re-exported: 11 pieces, 13.3 MB.
- L8 (2026-10-29, human): "Na pero no utilizan laptop, suele ser un monitor, haz que sea un monitor, le pones un pie pequeño y listo".
  Applied:
  - The laptop was replaced with SM_Monitor: a 19.5" panel (0.45 x 0.27 m) on a short neck and a small foot, 1.065 m tall overall on the desk.
  - It sits at the desk's left corner (-0.53, -0.04), turned 42° toward the doctor. In StationView it enters the frame from the bottom-left edge, so it never reads as floating, and the couch pad and frame stay visible above it.
- L9 (2026-10-29): Idle-2 and Idle-3 were joined in Blender into one seamless 9.4 s loop and retargeted in a headless editor with auto-generated IK Rigs (RTG_YBot_To_Patient). The seated pose fixes the distance from the hips to the feet, so the patient actor sits at z -38 and SM_VisitorChair has a 41.5 cm seat. Human (2026-10-29): "fijate que el respaldar de la silla está como desfasado y la persona está todavía volando un poco"; the backrest and uprights now tilt together, and the seat was refitted.
- L10 (2026-10-29): Human: "Tenés que fijarte que después el cartel de la estación que dice finalizar estación y eso no tape al metahumano". At FOV 70 and pitch -10, the HUD's timer panel covered the forehead. Human: "Usá la opción B: FOV 80° y cámara a −6,5°."
- L11 (2026-10-29): 98/98 automation specs pass on the merged develop code (PatientVoice, StationHud, StationCards, StationRun.Unit, StationTalkKey). Frame time on the M4 Pro with 24 GB: 15.4 ms mean, 22.3 ms p95, GPU-bound.

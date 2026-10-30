# Screen designs — "Cine" visual language

Approved mockups for every screen of the Unreal client, in one visual language called **Cine**. The 3D consultation room stays on screen, and the UI sits over it as text and controls on a dark scrim. Each implementation issue links the screen it builds from this folder.

## Quick path

1. Look at the PNG of a screen in [`png/`](png/) (1600×900).
2. Open its HTML in [`html/`](html/) in any browser for the exact layout, copy and interactions. Links between screens work, so you can walk the flow.
3. To see another state, add the prop to the URL, for example `HudTraining.dc.html?overtime=true` (props are listed in each file's `data-props`).
4. After editing a mockup, regenerate the images with `docs/design/screens/render-png.sh` (needs Google Chrome).

## Flow

```text
Microphone → Login → Main menu → Notice (once) → Catalog → Brief (Treino | Prova simulada)
  → Station HUD (Treino | Prova simulada) ⇄ Exams and document → Result (Treino | Prova simulada)
  → Main menu · History list → History detail · Settings · Quota / subscription
Any running station → Invalidated (technical failure)
```

## Screens

| Screen | PNG | HTML | Status | Related |
|--------|-----|------|--------|---------|
| Microphone (first launch) | [png](png/Microphone.png) | [html](html/Microphone.dc.html) | Restyle of `UStationMicrophoneWidget` | |
| Login with device code | [png](png/Login.png) | [html](html/Login.dc.html) | New in Unreal | #337, #326 |
| Main menu | [png](png/Main.png) · [exam selected](png/Main--exam-selected.png) | [html](html/Main.dc.html) | Restyle of `UStationMenuWidget` | #421, #431 |
| Notice — educational tool | [png](png/Notice.png) | [html](html/Notice.dc.html) | Restyle of `UStationNoticeWidget`, adds provider list | |
| Catalog — choose a station | [png](png/Catalog.png) | [html](html/Catalog.dc.html) | New | #326 |
| Brief — Treino | [png](png/BriefTraining.png) · [mic blocked](png/BriefTraining--mic-blocked.png) | [html](html/BriefTraining.dc.html) | Restyle of `UStationBriefWidget` | |
| Brief — Prova simulada | [png](png/BriefExam.png) · [mic blocked](png/BriefExam--mic-blocked.png) | [html](html/BriefExam.dc.html) | Restyle of `UStationBriefWidget` | #425 |
| HUD — Treino | [png](png/HudTraining.png) · [overtime](png/HudTraining--overtime.png) · [voice lost](png/HudTraining--voice-lost.png) | [html](html/HudTraining.dc.html) | Restyle of `UStationHudWidget` | #323, #444 |
| HUD — Prova simulada | [png](png/HudExam.png) | [html](html/HudExam.dc.html) | New exam HUD | #425, #423, #364 |
| Exams and document | [png](png/Document.png) | [html](html/Document.dc.html) | Restyle of the HUD exams drawer and document viewer | |
| Invalidated | [png](png/Invalidated.png) · [training](png/Invalidated--training.png) | [html](html/Invalidated.dc.html) | Restyle of `UStationInvalidatedWidget` | #447 |
| Result — Treino | [png](png/ResultTraining.png) | [html](html/ResultTraining.dc.html) | Restyle of `UStationFeedbackWidget` | #323 |
| Result — Prova simulada | [png](png/ResultExam.png) · [level 1](png/ResultExam--level-1.png) | [html](html/ResultExam.dc.html) | New | #426 |
| History list | [png](png/History.png) · [empty](png/History--empty.png) | [html](html/History.dc.html) | New | #338 |
| History detail | [png](png/HistoryDetail.png) | [html](html/HistoryDetail.dc.html) | New | #338 |
| Settings | [png](png/Settings.png) | [html](html/Settings.dc.html) | New, content not specified yet | #423 |
| Quota / subscription | [png](png/Quota.png) · [subscription](png/Quota--subscription.png) | [html](html/Quota.dc.html) | New | |

## Visual language

| Token | Value | Use |
|-------|-------|-----|
| Font | Manrope 400–800 | All text |
| Ink | `#FFFFFF` titles, `#E8EEF2` text, `#C9D4DB` body, `#A9B7C1` muted | Text on the scrim |
| Treino accent | `#5FD0BF` | Treino marks, primary buttons |
| Prova simulada accent | `#F2A65A` | Exam marks and buttons |
| Danger | `#C2413A` button, `#FF8A7A` text | Finish station, failures |
| Scrim | `rgba(9,13,17,.92)` → transparent, left to right | Text over the scene |
| Panel | `rgba(12,17,22,.84)`, border `#2F3D48`, radius 12 | HUD panels, cards |
| Paper | `#F6F3EC`, ink `#1D2833` | Document viewer |
| Mode mark | 32×4 px bar in the mode accent | Before every mode title |

All shared rules live in [`html/cine.css`](html/cine.css). The Unreal client builds them from one place, `StationUi` (see [the Cine style kit](../../unreal-station-client.md#the-cine-style-kit-issue-455)).

## Rules for implementers

- **Copy is spec.** The Brazilian Portuguese text in the mockups is the intended UI copy. Existing strings from the code are kept verbatim.
- **Placeholders are not content.** `[Tema do caso]`, `[valor]`, `[n] de [n]` and `[Cena …]` mark data that comes from the server or the 3D scene.
- **Sample data is labelled.** Screens marked "EXEMPLO — DADOS FICTÍCIOS" show invented results only to fill the layout.
- **Main menu interaction.** Both modes are always visible. The unselected one is dimmed (about 45% opacity). Selecting a mode by click, arrow keys or focus lights it up and fades in its round arrow button. Nothing moves or resizes.
- **History keeps only cited phrases.** As decided on 2026-10-29, history shows the correction and the learner phrases cited in it, never the full conversation or audio (CONTEXT.md "MVP Data Retention").

## Out of scope

- The 3D office behind the menu (#431) and the analog desk clock: the mockups only mark where they go.
- Settings content beyond what the mockup shows: it has no spec yet.
- The `html/support.js` renderer exists only to open these mockups in a browser. It is not product code.

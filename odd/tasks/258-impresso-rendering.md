# 258 — Render impresso content as formatted text and localize the category label

Issue: #258 (parent #237). Branch: `fix/258-impresso-rendering` from `feat/237-clinician-demo-readiness`.

## Objective

The "Documentos liberados" drawer shows impresso content as formatted text (no raw Markdown markers) and shows a pt-BR category label instead of the package key.

## Why

In the 2026-10-19 rehearsal the drawer showed `- **Estado geral:** regular…` and the English key `physical_exam`. A clinician notices both in the demo.

## Constraints

- Web-only; code stays in `web/src/features/station`.
- No `dangerouslySetInnerHTML`, no raw HTML, no new dependency: render to React elements.
- Supported subset is what the packages use today (checked across `backend/priv/stations/*/package.json`): `### ` headings, `**bold**`, `- ` bullets, paragraphs separated by blank lines and single line breaks.
- Categories (validator allows exactly these, all present in packages): `physical_exam`, `laboratory`, `imaging`, `report`. Unknown category renders no label, never the raw key.
- Learner-facing copy in pt-BR; artifacts in English.

## Checklist

- [ ] T1 — Markdown-subset renderer (`ImpressoContent`) used by the drawer viewer, with unit tests (bold, bullets, headings, paragraphs, line breaks, HTML-injection safety) and the supported subset documented in `docs/content/authoring-guide.md`.
- [ ] T2 — pt-BR category labels in the drawer (`physical_exam` → "Exame físico", `laboratory` → "Exames laboratoriais", `imaging` → "Exame de imagem", `report` → "Laudo ou registro"; unknown → no label), with tests.
- [ ] T3 — Drawer screenshots at desktop 1280x900 and mobile 390x844; local CI; PR.

## Routing

All tasks inline in this bounded writer (one feature slice, small files).

## Checks

- Focused: `npm --prefix web test -- src/features/station`.
- Full: local CI script (mirrors `.github/workflows/pr-validation.yml`).

## Progress

- Created feature document before the first source write.

## Next step

T1.

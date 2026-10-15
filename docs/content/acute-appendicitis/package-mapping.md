# Acute appendicitis: source-to-package mapping

This record shows where each part of the Content Partner's station went in the package, which fields the transcriber had to derive, and which source rules the package contract cannot express. It states facts only and makes no clinical judgement.

| | |
|---|---|
| Source | `docs/content/acute-appendicitis/partner-source.pt-BR.md` (unmodified) |
| Package | `backend/priv/stations/acute-appendicitis/package.json` |
| Contract | `backend/priv/stations/package.schema.json`, `backend/lib/backend/stations/station_package.ex` |
| Status | `placeholder: true`. Not the active station. Nothing here is partner-confirmed. |

## How the text was transcribed

- Authored prose was copied from the source by line, not retyped. Each prose string in the package is a substring of the source.
- Markdown emphasis markers (`**`) were removed in plain-text fields. Impresso `content` keeps the source Markdown.
- List markers (`- `, `1. `), the `(n)` criterion markers, and the `;` or `.` that closes a criterion were dropped where a field holds one list entry.
- Decimal commas became JSON numbers only in `points` (`0,2` → `0.2`). Numbers inside prose are unchanged.
- "Regra de liberação" sentences are release rules, not handout text, so they are not part of any impresso `content`.

## Mapping

| Source | Package field | Notes |
|---|---|---|
| §1 Área, Nível de atenção, Infraestrutura disponível | Not carried | No field. See G12. |
| §1 Tema | `display_title` | Verbatim. See D1, G13. |
| §1 Cenário/descrição do caso | `patient_profile.presenting_context`, `patient_profile.age` | Paragraph verbatim; age `27` read from it. See G12. |
| §1 Tarefas a realizar (1–5) | `expected_actions` `tarefa-1` … `tarefa-5` | Verbatim. The "10 minutos" duration is not carried. |
| §2 Perfil do paciente | `patient_profile.persona` (first four sentences), `patient_profile.tone` (last sentence) | Sentences verbatim; the split is derived (D3). |
| §2 HDA — respostas padronizadas (9 bullets) | `revealable_facts` `hda-01` … `hda-09` | One fact per bullet, `on_request`. |
| §2 Antecedentes, medicações e hábitos (5 bullets) | `revealable_facts` `antecedentes-01` … `-05` | One fact per bullet, `on_request`. |
| §2 Informações que o ator só revela se o candidato perguntar explicitamente (5 bullets) | `revealable_facts` `pergunta-explicita-01` … `-05` | One fact per bullet, `on_request`. See G9. |
| §2 Comportamento durante o exame | `response_rules` `comportamento-durante-o-exame` | Verbatim. See G11. |
| §2 Dúvidas obrigatórias do ator nos minutos finais (2) | `revealable_facts` `duvida-final-01`, `-02` | Quoted questions verbatim, `timed`. See G10. |
| §2 "O candidato deve responder com empatia…" | `expected_actions` `resposta-as-duvidas-do-paciente` | Verbatim. See G15. |
| §3 Impresso 1 | `impressos` `impresso-1-exame-fisico` (`physical_exam`) | Content verbatim. See G8. |
| §3 Impresso 2 | Seven `laboratory` impressos: `impresso-2-hemograma`, `-pcr`, `-eletrolitos`, `-ureia`, `-creatinina`, `-glicemia`, `-urina-tipo-1` | Lines verbatim, each under its source subheading. See G5. |
| §3 Impresso 3 | `impressos` `impresso-3-exame-de-imagem` (`imaging`) | Content verbatim. See G6. |
| §3 Impresso 4 | `impressos` `impresso-4-receituario` (`report`) | Content verbatim; never released. See G7. |
| §4 Items 1–11 | `rubric` `item-01` … `item-11` | See the rubric table below. |
| §4 Conferência aritmética, Pontuação total | Not a field | The eleven `adequado` values sum to exactly 10 (tested). |

### Rubric

For every item: `description` is the item title line and the "Critérios avaliados" line; each numbered criterion is one action `criterio-n` with its verbatim text; each level `description` is the verbatim level text; `points` are the partner's.

| Item | Points (inad. / parc. / adeq.) | `min_actions` (inad. / parc. / adeq.) | Actions | Roles | Exact? |
|---|---|---|---|---|---|
| `item-01` | 0 / 0.1 / 0.2 | 0 / 1 / 2 | 2 | — | Yes |
| `item-02` | 0 / 0.4 / 0.8 | 0 / 3 / 5 | 6 | — | Yes |
| `item-03` | 0 / 0.4 / 0.8 | 0 / 2 / 4 | 6 | — | Yes (G4) |
| `item-04` | 0 / 0.3 / 0.6 | 0 / 2 / 4 | 5 | — | Yes |
| `item-05` | 0 / 0.6 / 1.2 | 0 / 2 / 3 | 4 | — | Yes (G4, G14) |
| `item-06` | 0 / 0.4 / 0.8 | 0 / 2 / 3 | 4 | — | Yes |
| `item-07` | 0 / 0.4 / 0.8 | 0 / 2 / 3 | 4 + 1 | `atribuicao-a-infeccao-urinaria`: `forbidden`; `veto: true` | Yes (G3) |
| `item-08` | 0 / 0.7 / 1.4 | 0 / 1 / 4 | 4 | `criterio-4`: `mandatory` | No (G2) |
| `item-09` | 0 / 0.6 / 1.2 | 0 / 2 / 4 | 5 | — | Yes |
| `item-10` | 0 / 0.6 / 1.2 | 0 / 2 / 3 | 3 | — | No (G1) |
| `item-11` | 0 / 0.5 / 1 | 0 / 2 / 3 | 4 | — | Yes, but see G10 |

All items: `order`, `count_cap`, `first_n`, `modality_requirement` and `rule` are `null`; `exclusion` is `false`; `evidence_questions` is `[]`.

## Derived fields (derived by the transcriber, need partner confirmation)

None of the following is partner-authored.

| ID | Field | What was derived |
|---|---|---|
| D1 | `display_title` | The choice of "Tema" as the title. |
| D2 | `patient_profile.age` | `27`, read from the scenario paragraph. |
| D3 | `patient_profile.persona`, `.tone` | The split of the "Perfil do paciente" paragraph across the two required fields. |
| D4 | `patient_profile.presenting_context` | The choice of the scenario paragraph for this field (it is written to the participant, in the second person). |
| D5 | `revealable_facts[].id`, `.topic` | Positional ids; `topic` is the source section heading. One fact per bullet. |
| D6 | `revealable_facts[].disclosure_condition` | `on_request` for the 19 answers, `timed` for the two final doubts. |
| D7 | `response_rules` | The id and the choice of this field for "Comportamento durante o exame". |
| D8 | `expected_actions` | The ids and the choice of this field for the five tasks and the answer guidance. |
| D9 | `rubric[].id`, `rubric[].actions[].id` | Positional ids. |
| D10 | `rubric[].description` | Composition: title line, newline, criteria line. |
| D11 | `rubric[].evidence_questions` | Empty list on every item. The source authors none. |
| D12 | `rubric[].practice_recommendation` | The item title, used as a placeholder. The source authors no recommendation, and this text is shown to learners. |
| D13 | `rubric[].levels[].min_actions` | The integer thresholds, read from each level sentence (table above). |
| D14 | `item-07` action `atribuicao-a-infeccao-urinaria`, `veto: true` | A fifth, `forbidden` action whose text is a fragment of the "Inadequado" sentence. |
| D15 | `item-08` `criterio-4` role `mandatory`; partial threshold `1` | Read from the "Parcialmente adequado" and "Inadequado" sentences. |
| D16 | `rubric[].order`, `count_cap`, `first_n`, `exclusion`, `modality_requirement`, `rule` | Left unset (`null` / `false`): the source authors none of them. |
| D17 | `impressos[].id`, `.category` | Ids; `report` for Impresso 4 (the contract has no prescription category). |
| D18 | `impressos[].title` for the seven Impresso 2 parts | Source title, " — ", and the line label or subheading. |
| D19 | `impressos[].keywords` | Every keyword (table below). |
| D20 | `approved_templates` | `null`. The source authors no template. |
| D21 | `rubric[].actions[].impresso_ids` on `item-06` `criterio-1`–`4` and `item-08` `criterio-1` (issue #228) | Each lab group names the Impresso 2 parts that answer it (`criterio-4`: `-ureia`, `-creatinina`, `-eletrolitos`); the imaging request names `impresso-3-exame-de-imagem`. A verified request that releases one of them grades the action performed without a provider. `item-05` names none: its actions are authorization and verbalized findings, not the exam request. |

### Keywords (D19)

Matching is a substring test on lower-cased, accent-stripped learner text (`backend/lib/backend/stations/impressos.ex:37`). It cannot tell a request from a mention.

| Impresso | Keywords | Words deliberately left out |
|---|---|---|
| `impresso-1-exame-fisico` | `exame físico` | — |
| `impresso-2-hemograma` | `hemograma` | — |
| `impresso-2-pcr` | `PCR`, `proteína C-reativa` | — |
| `impresso-2-eletrolitos` | `eletrólitos` | `sódio` (substring of "episódio" once accents are stripped), `potássio` |
| `impresso-2-ureia` | `ureia` | `função renal` |
| `impresso-2-creatinina` | `creatinina` | `função renal` |
| `impresso-2-glicemia` | `glicemia` | — |
| `impresso-2-urina-tipo-1` | `urina tipo 1` | `EAS` (substring of words such as "áreas") |
| `impresso-3-exame-de-imagem` | `ultrassonografia de abdome e pelve`, `tomografia computadorizada de abdome e pelve` | `TC`, `ultrassom`, shorter phrasings |
| `impresso-4-receituario` | none | See G7 |

## Gaps

"Direction" compares the package with the source: **lower** means the package can award less than the source, **higher** means it can award more.

| ID | Source rule | What the contract can express | Encoding chosen | Direction | Partner must decide |
|---|---|---|---|---|---|
| G1 | Item 10: "Parcialmente adequado" is two criteria **or** an antibiotic without adequate anaerobic coverage. "Inadequado" is no surgical evaluation **and** no pertinent antimicrobial conduct. | One count threshold per level. No disjunction, no level tied to a specific pair of absences. | Thresholds 0 / 2 / 3 over the three criteria. | **Lower.** A learner who only prescribes an antibiotic without anaerobic coverage scores 0, not 0.6. A learner who meets exactly one criterion scores 0; the source defines no level for "surgical evaluation only". | The level for each single-criterion case, and whether the second half of the partial rule should be its own criterion. |
| G2a | Item 8: "Adequado" needs all four; "Parcialmente adequado" needs the hypothesis and a failed image finding; "Inadequado" is no hypothesis. | A `mandatory` action plus count thresholds. | `criterio-4` `mandatory`; thresholds 0 / 1 / 4. | **Equal** in the cases the source defines. The source defines no level for "hypothesis, both findings interpreted, imaging not requested"; the package scores it 0.7. | The level for that case. |
| G2b | Item 8: criterion 4 says "formula a hipótese de apendicite aguda"; the levels say "hipótese principal". | The mandatory action carries one text. | The criterion 4 text, verbatim. The level sentences reach the classifier in the criterion description. | **Possibly higher.** If appendicitis is named but not as the main hypothesis and the classifier marks criterion 4 performed, the package scores 0.7 or more where the source says 0. | Whether criterion 4 should say "principal". |
| G3 | Item 7: also "Inadequado" when the learner wrongly attributes the picture to urinary infection. | A `forbidden` action scores the zero-point level when performed with evidence. | Fifth action, `forbidden`, `veto: true`. | **Equal.** | Confirm the action text (D14). |
| G4 | Criteria with inner logic: Item 5 criterion 4 ("ao menos uma manobra entre Rovsing, psoas e obturador"), Item 5 criterion 1, Item 3 criterion 4, "ou"/"e" groups. | An action is performed or not; code does not count inside an action. | One action per numbered criterion, verbatim. The classifier judges the inner condition from the text. | **Equal** at the threshold level; the inner condition is not verified in code. | Whether any compound criterion should be split. |
| G5 | Impresso 2: release on a nominal request per test; ask which tests when the learner asks for "exames laboratoriais". | An impresso is released whole on a keyword match. No clarifying question. | Seven impressos, one per named test (sodium and potassium together). A generic request matches nothing and returns "unavailable". | **Lower.** Requests worded as "função renal", "sódio", "potássio" or "EAS" release nothing, which limits Item 7. | The split, the grouping of sodium and potassium under "eletrólitos", and the keywords. |
| G6 | Impresso 3: release on a pertinent ultrasound or CT request; the content is a CT report. | One content per impresso; no pertinence check. | One impresso with two full-phrase keywords. An ultrasound request releases the CT report, as in the source. | **Lower.** "TC de abdome", "ultrassom" and similar wordings release nothing, which limits Item 8 criteria 2 and 3. | The keywords, whether "de abdome e pelve" applies to the ultrasound, and whether an ultrasound request should get a CT report. |
| G7 | Impresso 4: made available when the participant indicates a prescription or records support measures. | Keyword match only; an act cannot be detected. The content lists the measures scored in Items 9 and 10. | No keywords: the impresso is in the package and is never released. | **Lower or equal.** Items 9 and 10 are scored from what the learner says. | Whether and how this impresso is shown. |
| G8 | Impresso 1: release when the participant verbalises that they will perform or request the physical exam. | Keyword substring match. | Keyword `exame físico`. | **Lower** for other wordings ("vou examinar o abdome"). Any mention of the phrase releases it, including a negated one. | The keywords. |
| G9 | Standard answers versus information revealed only when asked explicitly. | One enum; both are `on_request`. | All 19 answers `on_request`; the source heading is kept in `topic`. | No scoring rule depends on it. The patient prompt lists every fact without its condition (`backend/lib/backend/stations/station_ai.ex:176`); the condition is only forwarded to the decision model. | Whether the distinction must be enforced. |
| G10 | Two mandatory patient questions in the final minutes. | `timed` has no time parameter; the patient never starts a turn; template predicates count learner turns only. | Two `timed` facts holding the quoted questions. No approved template, because a turn count would be invented. | **Lower.** If the patient never asks, Item 11 criterion 3 cannot be met; "Adequado" stays reachable through criteria 1, 2 and 4. | How and when the questions are asked. |
| G11 | Behaviour during the exam, conditional on how the learner proceeds. | Prose instructions to the patient model. No physical exam, no nonverbal acting, no conditional rule in code. | One response rule, verbatim. | None on scoring. | Whether this behaviour is needed in a voice or text station. |
| G12 | Scenario and instructions shown to the participant before the station, including vital signs. | No learner-facing scenario field. | Scenario paragraph in `presenting_context`, which feeds the patient model's prompt. Área, Nível de atenção, Infraestrutura and the duration are not carried. | None on scoring. The learner sees the vital signs only through Impresso 1. | Where the scenario and tasks are shown. |
| G13 | — | `display_title` and `station_id` are returned to the client. | "Tema" as title; `acute-appendicitis` as id. | None on scoring. Both name the diagnosis. | The learner-visible title. |
| G14 | Item 5 criterion 2 says "verbaliza"; no item names a modality. | One `modality_requirement` per criterion. | `null` on every item: any learner evidence is valid. | Not determined by the source. | Whether any item must be verbal only. |
| G15 | Expected content of the answer to the two doubts. | No field for per-action marking guidance. | Verbatim in `expected_actions`; the rubric assessment does not read it. | None in code; the classifier does not receive it for Item 11. | Whether it belongs in Item 11. |
| G16 | Facts written as actor script ("Nega…", "Se perguntado…", "a menos que perguntado"). | `content` is free prose. | Verbatim. `antecedentes-05` says family history is available if asked but the source gives none. | None on scoring. | The family history content, if any. |
| G17 | The five tasks are numbered. | `order` and a `task_order` criterion. | Not used: the source scores no order. | **Equal.** | — |

## Not changed

The schema, the validator and the active station id in `backend/lib/backend/stations/station_loader.ex` are untouched.

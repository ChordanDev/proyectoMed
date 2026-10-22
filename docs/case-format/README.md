# Tagged case format

A case is one Markdown file. Tags mark every piece the backend needs, so `Backend.Stations.parse_case/1` turns it into a Station Package without an LLM. Everything else in the file (Markdown headings, text before the first tag) is for human readers and is ignored.

- **Reference case:** [`backend/priv/stations/acute-appendicitis/case.md`](../../backend/priv/stations/acute-appendicitis/case.md). It parses into the same Station Package as the hand-tuned `package.json` next to it.
- **Parser:** `backend/lib/backend/stations/case_format.ex` (issue #330, spec #326).
- **Output:** `{:ok, package}` or `{:error, [%{line: n, message: "..."}]}`, errors sorted by line.

## Tag syntax

```
[NAME id key=value FLAG] value on the same line
more value lines, up to the next tag line or Markdown heading
```

| Part | Rule |
|---|---|
| `NAME` | Uppercase tag name. Accents are optional: `[ESTAÇÃO]` and `[ESTACAO]` are the same tag. |
| `id` | Lowercase id: letters, digits, `-` and `_`. At most one per tag. |
| `key=value` | Attribute. No spaces inside the value; lists are comma-separated (`impressos=a,b`). Keys ignore accents (`após=` is `apos=`). |
| `FLAG` | Uppercase word such as `EXPLÍCITO`. |
| value | The rest of the line plus the following lines, verbatim, up to the next tag or heading. Leading and trailing blank lines are dropped; blank lines inside are kept. |

A line that starts with `[` and an uppercase letter but is not a valid tag is an error. A heading (`#`) ends the value of the tag before it.

## Station tags

Each appears once.

| Tag | Required | Becomes |
|---|---|---|
| `[ESTAÇÃO id]` | yes | `station_id` |
| `[ÁREA] text` | yes | `area` |
| `[TEMA] text` | yes | `theme` and `display_title` |
| `[PROVISÓRIO] sim\|não` | no (default `não`) | `placeholder` |
| `[CENÁRIO] text` | yes | `candidate_brief.scenario`, the learner-facing "cenário de atuação" |

```
[ESTAÇÃO acute-appendicitis]
[ÁREA] Cirurgia Geral
[TEMA] Abdome agudo inflamatório — apendicite aguda
[PROVISÓRIO] sim
[CENÁRIO] Você é o médico ou a médica de plantão em um pronto-socorro de hospital geral. …
```

### `[TAREFA id] text`

A learner task, in order. At least one. Each becomes a `candidate_brief.tasks` entry and an `expected_actions` entry with the same id.

```
[TAREFA tarefa-1] Apresentar-se, confirmar a identificação do paciente e obter anamnese dirigida.
```

### `[CONDUTA-ESPERADA id] text`

Examiner-only description of what the learner should do, added to `expected_actions` after the tasks.

```
[CONDUTA-ESPERADA resposta-as-duvidas-do-paciente] O candidato deve responder com empatia, …
```

## Actors

### `[ATOR id papel=… idade=… voz=…] name`

At least one actor, and exactly one with `papel=paciente`. `papel` is `paciente` or `acompanhante`; `idade` is a non-negative integer; `voz` is the voice key the voice worker maps to a TTS voice. The child tags below must follow their `[ATOR]`.

| Child tag | Required | Becomes |
|---|---|---|
| `[PERFIL] text` | yes | `persona` |
| `[TOM] text` | yes | `tone` |
| `[CONTEXTO] text` | patient only | `presenting_context` |

The patient fills `patient_profile`. Every actor is listed in `actors` with its facts, explicit-question facts and mandatory questions.

```
[ATOR paciente papel=paciente idade=27 voz=masculina-adulta] Rafael Nogueira
[PERFIL] Rafael está sentado na maca, um pouco curvado e com expressão de desconforto. …
[TOM] Fala em português claro, com escolaridade compatível com ensino médio completo.
[CONTEXTO] Você está atendendo Rafael Nogueira, 27 anos, …

[ATOR mae papel=acompanhante idade=34 voz=feminina-adulta] Juliana Souza
[PERFIL] Mãe de Lucas, preocupada e colaborativa.
[TOM] Fala de forma direta, com vocabulário simples.
```

## Actor script

### `[TÓPICO] text`

Sets the topic of the facts and mandatory questions that follow, until the next `[TÓPICO]`. A fact before any topic is an error.

```
[TÓPICO] HDA — respostas padronizadas
```

### `[FATO id ator=… pep=… EXPLÍCITO] text`

One thing an actor may say when asked (`disclosure_condition: on_request`).

| Part | Required | Rule |
|---|---|---|
| `ator=` | yes | An `[ATOR]` id. |
| `pep=` | no | The PEP criterion the fact answers, as `item-id.criterion-id`. It must be a `tipo=PERGUNTA` criterion. |
| `EXPLÍCITO` | no | The actor reveals it only when the learner asks explicitly. |

```
[FATO hda-01 ator=paciente pep=item-02.criterio-1] A dor começou ao redor do umbigo.
[FATO pergunta-explicita-01 ator=paciente EXPLÍCITO] Nega episódio semelhante anterior.
```

### `[PERGUNTA-OBRIGATÓRIA id ator=…] text`

A question the actor must ask near the end (`disclosure_condition: timed`). A `tipo=COMUNICAÇÃO` criterion can check the learner's answer with `perguntas=`.

```
[PERGUNTA-OBRIGATÓRIA duvida-final-01 ator=paciente] “Doutor, isso pode ser tratado só com remédio, sem cirurgia?”
```

### `[REGRA id] text`

A response rule for the actors (`response_rules`).

```
[REGRA comportamento-durante-o-exame] Se o candidato explicar o que fará e pedir autorização, o paciente coopera, …
```

## Impressos

### `[IMPRESSO id categoria=…] title`

`categoria` is `exame-fisico`, `laboratorio`, `imagem` or `registro`. Both child tags are required and must follow their `[IMPRESSO]`.

| Child tag | Becomes |
|---|---|
| `[LIBERAÇÃO] kw; kw; …` | `keywords`: the semicolon-separated phrases whose request releases the impresso. May be empty for an impresso released only by the examiner. |
| `[CONTEÚDO]` + lines | `content`, verbatim Markdown. |

```
[IMPRESSO impresso-2-pcr categoria=laboratorio] IMPRESSO 2 — EXAMES LABORATORIAIS — PCR
[LIBERAÇÃO] PCR; proteína C-reativa; proteína C reativa
[CONTEÚDO]
**Inflamação e função renal/metabólica:**

- PCR: 86 mg/L. Referência: inferior a 5 mg/L.
```

## PEP

### `[ITEM id] title`

One PEP item (a package rubric criterion). The title is also its `practice_recommendation`. The package `description` is generated from the title, the item number (its position), the top level's points and the criteria: `ITEM 1: Apresentação e identificação (Total: 0,2 ponto)` followed by `Critérios avaliados: (1) …; (2) ….`

Each item needs at least one `[CRITÉRIO]` and one `[NÍVEL]` after it.

### `[CRITÉRIO id tipo=… OBRIGATÓRIO|PROIBIDO] text`

One criterion of the item (a package action). Ids are unique within the item.

| `tipo=` | Meaning | Attributes |
|---|---|---|
| `PERGUNTA` | The learner asks an actor. | At least one `[FATO]` must link to it with `pep=`. |
| `SOLICITAÇÃO` | The learner requests an impresso. | `impressos=` (required): the impressos whose release proves the request. |
| `VERBALIZAÇÃO` | The learner interprets an impresso. | `após=` (required): only turns after one of these impressos was released count. |
| `COMUNICAÇÃO` | The learner explains, prescribes or answers. | `perguntas=` (optional): the mandatory questions it checks. |

`OBRIGATÓRIO` makes the item score zero without it (`role: mandatory`). `PROIBIDO` makes the item score zero when it happens (`role: forbidden`, and the item becomes a veto); it does not count toward `mínimo` and is left out of the generated description.

```
[CRITÉRIO criterio-1 tipo=SOLICITAÇÃO impressos=impresso-2-hemograma] Hemograma completo
[CRITÉRIO criterio-4 tipo=VERBALIZAÇÃO após=impresso-3-exame-de-imagem OBRIGATÓRIO] formula a hipótese de apendicite aguda
[CRITÉRIO criterio-3 tipo=COMUNICAÇÃO perguntas=duvida-final-01,duvida-final-02] responde às duas dúvidas do paciente …
[CRITÉRIO atribuicao-a-infeccao-urinaria tipo=COMUNICAÇÃO PROIBIDO] atribui incorretamente o quadro a infecção urinária
```

### `[NÍVEL label pontos=… mínimo=…] description`

A performance level. `label` is `adequado`, `parcialmente_adequado` or `inadequado`, once per item. `pontos` is a non-negative multiple of 0,025 (comma or dot). `mínimo` is the number of criteria (not `PROIBIDO`) the learner must perform to reach the level. Levels may be written in any order.

```
[NÍVEL adequado pontos=0,2 mínimo=2] Realiza as duas ações.
[NÍVEL parcialmente_adequado pontos=0,1 mínimo=1] Realiza uma ação.
[NÍVEL inadequado pontos=0 mínimo=0] Não realiza nenhuma ação.
```

## Validation rules

Every rule reports an error at the line of the tag that breaks it; a missing station tag is reported at line 1.

| Rule | Example error |
|---|---|
| Known tags, attributes and flags | `unknown attribute cor= on [FATO]` |
| Required tag | `missing [TEMA] tag`, `missing [CONTEÚDO] for impresso impresso-2-pcr` |
| Required attribute or id | `[FATO] requires the attribute ator=` |
| Missing actor | `missing actor: the case declares no [ATOR]` |
| Unique ids (one namespace for tasks, expected conducts, rules, actors, facts, questions, impressos and items; criterion ids and level labels per item) | `duplicate id hda-01 (first defined on line 28)` |
| Links resolve | `unknown actor medico`, `unknown PEP criterion item-02.criterio-9; …`, `unknown impresso impresso-9`, `unknown mandatory question duvida-9` |
| Criterion types | `tipo=SOLICITAÇÃO requires the attribute impressos=` |
| Points | `pontos=0,01 is not a multiple of 0,025` |
| Total | `the item maximums sum to 9,8; the PEP must total 10,0` |
| Thresholds | `a level with pontos=0 must set mínimo=0`, `mínimo must not decrease as pontos increase in item item-02`, `mínimo=7 exceeds the 6 criteria that are not PROIBIDO` |

The parsed package is finally checked by `Backend.Stations.StationPackage.validate/1`; any gap between the two is reported at line 1 as `Station Package: …`.

## Package fields that the format does not set

`version` is always the current contract (`2.0.0`), `language` is `pt-BR` and `approved_templates` is `null`. Rubric items set `evidence_questions: []`, `order`, `count_cap`, `first_n`, `modality_requirement` and `rule` to `null`, and `exclusion: false`; the format has no tag for them yet.

## Proof that the reference case is equivalent

- `backend/test/backend/stations/case_format_test.exs`: the package parsed from `case.md` equals `package.json` on every field of `package.json`.
- `backend/test/backend/stations/case_format_grade_equivalence_test.exs`: on the stored transcripts of the #228 and #243 regression harnesses (five scenarios), both packages yield the same criterion statuses, levels, points, evidence and estimates.

## Inserting a case (n8n contract)

n8n inserts each generated case as one pending row of the `cases` table (`Backend.Content`, issue #331). It sets only three columns; Postgres fills the rest. The n8n prompts that write cases in this format, and the insert node configuration, are in [`docs/n8n`](../n8n/README.md) (issue #335).

```sql
INSERT INTO cases (area, theme, markdown)
VALUES ($1, $2, $3)
RETURNING number;
```

| Column | Type | Set by | Rule |
|---|---|---|---|
| `area` | `text`, not null | n8n | The `[ÁREA]` of the case, written the same way for every case of an area: the admin panel filters on the exact text. |
| `theme` | `text`, not null | n8n | The `[TEMA]` of the case. |
| `markdown` | `text`, not null | n8n | The whole case in this tagged format, UTF-8. |
| `number` | `bigint`, `GENERATED ALWAYS AS IDENTITY`, unique | Postgres | The sequential human number doctors split work by. An insert that sets it is refused. Numbers grow in insertion order and may skip a value after a failed insert. |
| `status` | `text`, default `pending` | Postgres | `pending`, `approved` or `disapproved` (check constraint). n8n never sets it: only the admin panel changes it. |
| `lock_version` | `integer`, default `1` | Postgres | The optimistic lock of admin edits (#332). n8n never sets it. |
| `approved_by_id` | `bigint` references `users(id)`, nullable | Postgres | Set on approval (#333); nilified on admin deletion. |
| `approved_by_email` | `text`, nullable | Postgres | Email snapshot of the approving admin. |
| `approved_at` | `timestamp` without time zone, nullable | Postgres | UTC timestamp when the case was approved. |
| `inserted_at`, `updated_at` | `timestamp` without time zone, default `timezone('utc', now())` | Postgres | |
| `id` | `bigint` primary key | Postgres | Internal; use `number` to talk about a case. |

The insert does not validate the format: a case with format errors is stored as pending, and the admin panel shows its errors.

### Format errors are computed on read

The admin panel runs `Backend.Stations.parse_case/1` on a case's Markdown each time it shows the case; errors are not stored.

- n8n writes the row directly, so Phoenix has no insert hook where it could compute and store errors.
- Stored errors would go stale when the parser rules change (#330 follow-ups) or when an admin edits the case (#332); reading them from the current Markdown and the current parser is always right.
- Parsing is pure and fast (milliseconds for one case), and the panel parses only the case being shown.
- `Backend.Content` calls no other context (ADR-007 #92 amendment), so the panel LiveView composes `Backend.Content` (the row) and `Backend.Stations.parse_case/1` (the errors).

## Editing a case (admin panel)

Any admin edits a case's Markdown in place on its panel page (issue #332, `Backend.Content.update_case_markdown/3`).

- **Every save re-validates.** The save stores the Markdown even when it has format errors (a pending case may be fixed over several saves), and the page then shows the parser errors of the saved text, computed on read as above.
- **Optimistic locking.** A save applies only over the `lock_version` the admin loaded, and increments it. If another admin saved the case in between, the save is refused with "Este caso mudou desde que você o abriu: recarregue a página antes de salvar." and nothing is overwritten; the admin's text stays in the editor so it can be copied before reloading.
- **Revisions.** Each save keeps the Markdown it replaces as a row of `case_revisions`: `markdown`, the `lock_version` that Markdown had, `editor_id` and an `editor_email` snapshot of the admin whose save replaced it, and `inserted_at` (when it was replaced). Revisions are never updated; deleting a case deletes its revisions, and deleting an admin account keeps its revisions with `editor_id` null. The panel lists them newest first. Saving an unchanged Markdown keeps no revision.
- **Published versions stay as they are.** A save writes only `cases.markdown`, `cases.lock_version` and a new `case_revisions` row; it never changes the status, area or theme. A published Station version is an immutable copy made at approval, so an edit can never change one; republishing an edited approved case is the approval step's job.

## Approving and publishing a case (admin panel, issue #333)

Any admin approves or disapproves a case from its panel page (`Backend.Content.approve_case/3`, `Backend.Content.disapprove_case/1`).

- **Approval requires valid format.** A case cannot be approved while it has parser errors; the button is disabled in the UI, and `Content.approve_case/3` returns `{:error, :invalid_case}` if called with parser errors or an invalid package.
- **Immutable station versions.** Approving inserts a new immutable row in `station_versions`: sequential `version_number` per case, `station_id` (from `[ESTAÇÃO id]`), `area`, `theme`, `markdown`, the full parsed `package`, approver metadata (`approved_by_id`, `approved_by_email`, `approved_at`), and `case_revision_id` pointing to the latest revision (if the case was edited).
- **Case status and metadata.** Approving sets `status = :approved`, stores `approved_by_id`, `approved_by_email` snapshot, `approved_at` timestamp, increments `lock_version`, and syncs `area` and `theme` with the parsed package.
- **Disapprove hides the case.** Disapproving sets `status = :disapproved` with optimistic locking.
- **Re-approving after edits.** When an approved case is edited and approved again, a new `StationVersion` row is created (`version_number: 2`). Previous versions are immutable and remain readable (`Content.get_station_version!/1`, `Content.list_station_versions/1`).
- **Station catalog.** `Backend.Stations.list_catalog_stations/0` (backing `GET /stations`) returns the latest published version of each currently approved case (`id`, `area`, `theme`, `actors`), stripped of examiner secrets. Pending and disapproved cases do not appear in the catalog.


# Authoring a station package

For Content Partners. This guide says what a station must contain to load, and what each rubric field can and cannot express. It describes what the code enforces today; it gives no clinical guidance.

Citations use these short names:

| Short name | File |
|---|---|
| `schema` | `backend/priv/stations/package.schema.json` |
| `validator` | `backend/lib/backend/stations/station_package.ex` |
| `rules` | `backend/lib/backend/stations/rubric_assessment/authored_rules.ex` |
| `first_n` | `backend/lib/backend/stations/rubric_assessment/first_n.ex` |
| `evidence` | `backend/lib/backend/stations/rubric_assessment/evidence.ex` |
| `predicates` | `backend/lib/backend/stations/template_applicability.ex` |
| `impressos` | `backend/lib/backend/stations/impressos.ex` |

## Quick path

1. Write the station in pt-BR as your own original work (see [Originality](#originality)).
2. Fill every required field below.
3. Use points that are multiples of 0.025 and the three level labels.
4. Check each rubric rule against [What a rubric rule can express](#what-a-rubric-rule-can-express). If a rule does not fit, say so; do not approximate it.
5. Hand over the source with a provenance and rights record and expect a field-by-field clinical review. The station stays `placeholder: true` until a qualified human completes that review.

A worked example: `docs/content/acute-appendicitis/` (source, mapping with its gaps, review records).

## Originality

- [ ] The station is original work by its author.
- [ ] Official INEP PEP material is a **structural reference only**. No item, case text, checklist wording or score table is copied or adapted from it.
- [ ] No real patient data: no real names, dates, record numbers, images or case details that could identify a person.
- [ ] Sources consulted and any generative tool used are declared in the provenance and rights record.

## Required fields

A package is one JSON file at `backend/priv/stations/<station_id>/package.json`.

| Field | Rule | Enforced at |
|---|---|---|
| `station_id`, `display_title` | Non-empty strings. Both are returned to the learner's client. | `validator:115` |
| `version` | Exactly `"2.0.0"`. | `validator:125` |
| `language` | Exactly `"pt-BR"`. | `validator:128` |
| `placeholder` | Boolean. `true` until the human review is complete. | `validator:131` |
| `patient_profile` | `persona`, `presenting_context`, `tone`: non-empty strings. `age`: integer ≥ 0. | `validator:134`–`158` |
| `revealable_facts` | List. Each fact: `id`, `topic`, `content`, `disclosure_condition`. Ids unique. | `validator:160`–`179` |
| `response_rules` | List (may be empty). Each: `id`, `instruction`. | `validator:61` |
| `expected_actions` | List (may be empty). Each: `id`, `description`. | `validator:62` |
| `rubric` | List of criteria. Ids unique. | `validator:206`–`233` |
| `approved_templates` | Optional: `null` or a list. | `validator:605` |
| `impressos` | Optional: `null` or a list. | `validator:662` |
| `candidate_brief` | Object with exactly `scenario` (non-empty string) and `tasks` (non-empty ordered list of non-empty strings). Returned to the learner's client and shown before and during the station. | `validate_candidate_brief` |

`candidate_brief` is the only text shown to the learner before the station. `patient_profile` feeds the simulated patient, not the learner, and is never shown. Write the brief in the candidate's voice ("Você é…"), and keep out anything the learner must obtain in the station: facts the patient reveals on request, impresso contents (including vital signs when an impresso carries them), rubric wording and examiner answer keys. Available resources and the station duration have no field yet.

## Facts and disclosure conditions

Each fact is one thing the patient may say. `disclosure_condition` is one of four values (`schema:65`, `validator:26`).

| Value | Intended meaning |
|---|---|
| `on_request` | Revealed when the learner asks. |
| `after_action` | Revealed after a learner action. |
| `timed` | Revealed at a point in time. |
| `unconditional` | May be revealed at any time. |

What the contract cannot carry:

- Which action triggers `after_action`, or what time triggers `timed`. There is no parameter for either.
- A difference between a standard answer and one given only to an explicit question. Both are `on_request`.
- A patient who speaks first. The patient only answers learner turns.

The validator checks only that the value is one of the four.

## Points and levels

| Rule | Enforced at |
|---|---|
| Level labels are `inadequado`, `parcialmente_adequado`, `adequado`. Each label at most once per criterion. | `schema:231`, `validator:281`, `validator:265` |
| A criterion has at least one level. | `validator:260` |
| `points` is a multiple of 0.025 (so tenths such as `0.2` and `1.4` are valid). Values are never rounded to fit. | `schema:233`, `validator:286` |
| Each level has a non-empty `description`. | `validator:429` |

Write points as JSON numbers with a decimal point (`0.2`, not `0,2`). Do not author negative points: the assessment rejects them.

## What a rubric rule can express

A criterion lists `actions` (the things the learner may do) and `levels`. These fields turn actions into a level.

| Field | Can express | Cannot express | Enforced at |
|---|---|---|---|
| `levels[].min_actions` | "At least N of the listed actions" per level. The level is the highest one whose threshold the count of performed actions reaches (`rules:19`). | "A or B" between different kinds of condition; a level that depends on **which** actions were performed; an upper bound. | All levels or none `validator:317`; zero-point level is `0` `validator:339`; positive level ≥ 1 `validator:348`; never decreases as points rise `validator:356`; highest threshold ≤ countable actions `validator:386` |
| `actions[].role: counted` | The default: the action counts toward thresholds. | — | `validator:454` |
| `actions[].role: mandatory` | "Without this action the criterion scores its zero-point level" (`rules:13`). It also counts toward thresholds. | "Required for the top level only". | `validator:454`; needs a zero-point level `validator:523` |
| `actions[].role: forbidden` | "Doing this scores the criterion's zero-point level" (`rules:12`). Never counts toward thresholds. | A penalty outside its own criterion; a partial deduction. | Needs `veto: true` `validator:513`; needs a zero-point level `validator:523` |
| `actions[].impresso_ids` | Optional. The authored impressos whose release means the learner requested what the action asks ("Requests a blood count" → `["impresso-2-hemograma"]`). A verified Impressos request that released one of them makes the action performed, citing that request, without asking the classifier. An action without a matching release is still judged from the conversation. | Partial credit for a request; a request that released nothing; use on a `first_n` criterion. | Non-empty list of authored impresso ids; not on a `first_n` criterion (`backend/lib/backend/stations/station_package.ex`, `validate_action_impresso_ids`) |
| `actions[].interprets_impresso_ids` | Optional. The authored impressos the action interprets ("Recognizes elevated CRP" → `["impresso-2-pcr"]`). Only learner turns sent after a verified Impressos request released one of them count as its evidence; an earlier turn, or the request itself, is dropped from its citations, and a performed action left with none is not performed. | Interpreting an impresso the station never releases; a request action (use `impresso_ids`). | Non-empty list of authored impresso ids; not together with `impresso_ids` on one action (`backend/lib/backend/stations/station_package.ex`, `validate_action_impresso_ids`) |
| `veto` | Must be `true` when the criterion has a `forbidden` action. The role applies the veto, not this flag. | A veto without a forbidden action. | `validator:485`, `validator:513` |
| `count_cap` | A maximum on the counted actions before thresholds apply (`rules:246`). | — | Integer ≥ 1 or `null` `validator:461`, `validator:473`; highest threshold ≤ cap `validator:401` |
| `first_n` | "Only the learner's first N answers to this criterion are eligible" (`first_n:3`). | Use without thresholds. | Integer ≥ 1 or `null`; requires thresholds when there are actions `validator:416`; highest threshold ≤ N `validator:407` |
| `order` and `rule: "task_order"` | `order` ranks a criterion as a step. One separate criterion with `rule: "task_order"` is scored on whether the ranked steps happened in order. | Order inside a criterion. | At most one, with two or more ranked criteria `validator:580`; its own fields `validator:543` |
| `exclusion` | `true` cancels the criterion: it is not assessed. | — | Boolean `validator:485` |
| `modality_requirement` | `null` (any learner evidence), `"verbal"`, `"impressos"`, or an impresso category (`evidence:138`). One value per criterion. | A requirement on a single action. Any other string loads but makes the criterion not observable. | Non-empty string or `null` `validator:493` |
| `evidence_questions` | Optional questions that help the classifier (list, may be empty). | Scoring logic. | `validator:248` |
| `practice_recommendation` | Required non-empty text shown with the result. | — | `validator:238` |

Three things to know before you write a level:

- **Without thresholds, the classifier chooses the level** from your level descriptions (`rules:24`). With thresholds, the count decides and the description is explanatory.
- **An action is performed or not.** "At least one of X, Y, Z" inside one action is judged by the classifier from the action text; code does not count inside an action. Split it into separate actions if the count matters.
- **A rule that needs "or"** between a count and a specific finding ("two criteria, or X without Y") has no exact encoding. Report it; the reviewer will record it as a gap.

Also enforced: action ids are unique within a criterion (`validator:448`); `order`, `count_cap`, `first_n`, `veto`, `exclusion` and `modality_requirement` must all be present, with `null` or `false` when unused (`schema:126`).

## Approved templates

An approved template is an exact reply the patient may give without a further check. Each needs `template_id`, `text` and an `applicability` predicate (`validator:605`–`643`).

| Predicate | True when |
|---|---|
| `{"type": "unconditional"}` | Always. |
| `{"type": "first_learner_turn"}` | The learner has taken exactly one turn. |
| `{"type": "min_learner_turns", "count": N}` | The learner has taken at least N turns. |
| `{"type": "max_learner_turns", "count": N}` | The learner has taken at most N turns. |

Rules (`predicates:24`, `predicates:87`–`148`): the predicate is an object, never a sentence or `true`; `count` is an integer ≥ 1; no extra keys. Predicates see only the number of learner turns. They cannot express elapsed time, a topic, or a prior action.

## Impressos

An impresso is a handout released when the learner asks for it.

| Field | Rule | Enforced at |
|---|---|---|
| `id`, `title` | Non-empty strings; ids unique. | `validator:688`, `validator:738` |
| `category` | `physical_exam`, `laboratory`, `imaging` or `report`. | `validator:698` |
| `keywords` | List of non-empty strings (the list may be empty: never released). | `validator:714` |
| `content` | Non-empty string (Markdown) or a non-empty object. | `validator:726` |

The web drawer renders a Markdown subset in string `content` (`web/src/features/station/screens/ImpressoContent.tsx`): `### ` headings, `**bold**`, `- ` bullet lists, paragraphs separated by a blank line, and single line breaks. Anything else, including HTML, is shown as literal text. Keep to this subset.

How release works (`impressos:42`): the learner's text is lower-cased and stripped of accents; an impresso is released, whole, when any keyword occurs in it starting at the beginning of a word.

- A keyword cannot tell a request from a mention, or a pertinent request from an impertinent one.
- A keyword never starts inside a word, so short abbreviations are safe to author (`eas` does not match "áreas", `sódio` does not match "episódio"). It may end inside one: `radiografia` matches "radiografias", and `eletro` would match "eletrólitos".
- Never author a generic word such as `exame` alone: it would release the impresso on almost every request. Author each common clinical phrasing as its own keyword instead.
- An impresso whose content is the expected answer (for example a receituário listing the conduct a rubric scores) must keep `keywords: []`. The learner verbalizes the conduct; the handout is never released.
- One impresso is one unit. To release results test by test, author one impresso per test.
- There is no "ask which tests" step. A request that matches no keyword is answered as unavailable.

## What to hand over

- [ ] The station source, in pt-BR.
- [ ] A provenance and rights record (template: `docs/content/acute-appendicitis/provenance-and-rights.md`).
- [ ] Any rule you know does not fit the tables above, stated in plain words.

The project then produces the package, a mapping record with derived fields and gaps, and a clinical review checklist for a qualified human to complete.

## After the review: qualification

A reviewed package is not yet qualified. Before any pilot use, humans also define acceptance thresholds, adjudicate the station's fictional qualification cases, and review how learners read the result. For the worked example see `docs/content/acute-appendicitis/qualification-results.md` (harness, cases, thresholds, observed results, activation gates) and `docs/content/acute-appendicitis/result-comprehension-review.md` (review template).

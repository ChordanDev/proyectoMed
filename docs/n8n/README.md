# n8n case pipeline

The n8n flow that generates Revalida-style cases in the [tagged case format](../case-format/README.md) and stores them in Neon as pending cases for doctor review (issue #335, spec #326). The prompts live here, next to the format spec; the user applies them in n8n by hand.

| File | Node |
|---|---|
| [generator-prompt.md](generator-prompt.md) | AI Agent that writes one case (OpenAI + Pinecone RAG) |
| [reviewer-prompt.md](reviewer-prompt.md) | Reviewer that returns `APROVADO` or a list of fixes |
| [neon-insert.md](neon-insert.md) | Postgres node that inserts the pending case |

## Flow

```
Trigger (área, tema) → Pinecone retrieval → Generator (AI Agent)
  → Reviewer → IF output starts with "APROVADO"
      yes → Code (area, theme from the case) → Postgres insert → number
      no  → attempts < 2 ? Generator again with ESTAÇÃO ANTERIOR + CORREÇÕES
                         : Code → Postgres insert (stored as pending; the admin panel shows the errors)
```

- **Regeneration loop.** On `CORRIGIR`, call the generator again with the same área and tema plus `ESTAÇÃO ANTERIOR:` (the case it wrote) and `CORREÇÕES:` (the reviewer's list). Cap it at two regenerations so a stubborn case cannot loop forever; after the cap, insert it anyway: the admin panel parses every case on read and shows its errors, and a doctor can fix or disapprove it.
- **Numbering.** The generator never numbers cases. Postgres assigns the sequential `number` on insert; doctors split work by number range.
- **Originality.** The generator prompt allows public cases as inspiration and forbids reproducing official INEP cases verbatim (spec #326 user story 6). Doctors still check it.

## Models

Production n8n uses **OpenAI** for both nodes. The prompts use no provider-specific feature, so they also run on other chat models. The three sample cases in `backend/test/backend/stations/fixtures/case_format/` (`n8n-sample-*.md`) were generated with the generator prompt through the Anthropic API, only to prove that the prompt yields cases the parser accepts; `case_format_n8n_samples_test.exs` parses them with zero errors. They are saved exactly as the model returned them (`claude-opus-5-5`, effort `medium`, no RAG context, 2026-10-26, with the generator prompt merged with the live n8n prompt). They have 12, 12 and 13 PEP items, 3 mandatory questions each, the last item "Comunicação e Resolução de Dúvidas", and 2,251 to 2,444 words of text without the tags (2,705 to 2,971 counting the tags). The 2026-10-22 bronquiolite sample stays as `resolver-comparison-bronquiolite.md`, because the resolver model comparison transcripts (#343) are written against its ids.

The first run produced one case with a Cyrillic `е` inside an id (`iеca-sublingual`), which the parser rejects. The prompts now require ASCII-only ids (generator rule 9, reviewer rule A4), and the three samples come from the run after that change. Expect this class of error from any model; the reviewer and the admin panel's parser errors catch it.

## Rules merged from the live n8n prompt (2026-10-26)

The generator prompt now keeps every clinical-content rule of the owner's live AI Agent prompt (see the bullets at the top of [generator-prompt.md](generator-prompt.md)). The rule changes against the previous version of this prompt:

- **Scenario:** `[CENÁRIO]` now carries the level of care, the infrastructure (including surgical backup or transfer), the patient data, the chief complaint and the baseline vital signs. Detailed exam findings and results stay in the impressos.
- **Counts:** 4 to 6 tasks, 2 or 3 mandatory questions, 10 to 14 PEP items (was 8 to 12, advisory), at least 20 facts, 1,500 to 2,500 words.
- **PEP:** coverage (a)–(f); the last item is "Comunicação e Resolução de Dúvidas" (one criterion per mandatory question plus empathy); numbered explicit sub-items, one per criterion; no vague terms.
- **Sources:** DCN, PCDT and the named Brazilian societies; internal-knowledge fallback when the RAG returns nothing, with no apologies or notes.
- **Not carried over:** "estação oficial" (the case is original and in the Revalida style, never a reproduction of an official case), and the live prompt's Google Docs list layout, which the tags replace.

The reviewer prompt checks the countable ones (section F): tasks, mandatory questions, PEP items, the last item, vague terms and the elements of the scenario.

## Voice keys

The generator chooses `voz=` from `infantil`, `masculina-adulta`, `feminina-adulta`, `masculina-idosa`, `feminina-idosa`. The voice worker must map each of these keys to a TTS voice (multiple-actor work of #326).

## Applying the prompts in n8n (HITL checklist)

The user does these steps; the issue closes when they confirm the flow is updated.

- [x] Compare the generator prompt with the live n8n system prompt and carry over any clinical rule of the live prompt that is missing here (merged on 2026-10-26, see above).
- [ ] Paste the generator prompt into the AI Agent node's System Message, and set its user message to área, tema and the Pinecone context.
- [ ] Add the reviewer node with the reviewer prompt, and an IF node on `APROVADO`.
- [ ] Add the regeneration branch (ESTAÇÃO ANTERIOR + CORREÇÕES, at most two attempts).
- [ ] Configure the Postgres node as in [neon-insert.md](neon-insert.md): Neon credential with SSL required, the `INSERT … RETURNING number` query, query parameters as an array expression.
- [ ] Make sure the área values the trigger sends are exactly the five in the generator prompt (the admin panel filters on the exact text).
- [ ] Run the flow for one theme and open the case in the admin panel (`/admin`): it shows its number, area and theme and no format errors.
- [ ] Confirm on issue #335 that the flow is updated.

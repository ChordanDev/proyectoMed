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

Production n8n uses **OpenAI** for both nodes. The prompts use no provider-specific feature, so they also run on other chat models. The three sample cases in `backend/test/backend/stations/fixtures/case_format/` (`n8n-sample-*.md`) were generated with the generator prompt through the Anthropic API, only to prove that the prompt yields cases the parser accepts; `case_format_n8n_samples_test.exs` parses them with zero errors.

## Voice keys

The generator chooses `voz=` from `infantil`, `masculina-adulta`, `feminina-adulta`, `masculina-idosa`, `feminina-idosa`. The voice worker must map each of these keys to a TTS voice (multiple-actor work of #326).

## Applying the prompts in n8n (HITL checklist)

The user does these steps; the issue closes when they confirm the flow is updated.

- [ ] Compare the generator prompt with the live n8n system prompt and carry over any clinical rule of the live prompt that is missing here (the live prompt is not in the repo; these rules were reconstructed from spec #326 and the reference case).
- [ ] Paste the generator prompt into the AI Agent node's System Message, and set its user message to área, tema and the Pinecone context.
- [ ] Add the reviewer node with the reviewer prompt, and an IF node on `APROVADO`.
- [ ] Add the regeneration branch (ESTAÇÃO ANTERIOR + CORREÇÕES, at most two attempts).
- [ ] Configure the Postgres node as in [neon-insert.md](neon-insert.md): Neon credential with SSL required, the `INSERT … RETURNING number` query, query parameters as an array expression.
- [ ] Make sure the área values the trigger sends are exactly the five in the generator prompt (the admin panel filters on the exact text).
- [ ] Run the flow for one theme and open the case in the admin panel (`/admin`): it shows its number, area and theme and no format errors.
- [ ] Confirm on issue #335 that the flow is updated.

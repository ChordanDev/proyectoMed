## Parent

Part of #22

## What to build

A `Backend.StationAI` module that, given the Station Package and the conversation so far, produces the next reply from the simulated patient. The module is constrained to `revealable_facts` and `response_rules`. It never invents clinical facts and never roleplays outside the case.

## Acceptance criteria

- [ ] `Backend.StationAI.next_reply/2` returns `%{text, used_facts}` where `used_facts` is the subset of `revealable_facts` actually surfaced in the reply.
- [ ] Any reply that would require a fact not in `revealable_facts` returns a neutral pt-BR refusal text ("Não tenho essa informação") instead of inventing.
- [ ] `response_rules` (politeness, length caps, refusal patterns) are applied before returning.
- [ ] The implementation choice between a deterministic rule engine and a thin LLM adapter is documented in the PR description; either is acceptable as long as the safety contract holds.
- [ ] ExUnit coverage: `Backend.StationAITest` covers happy-path reveal, refusal on missing fact, refusal on out-of-scope roleplay, length-cap rule, polite-tone rule.
- [ ] `bash scripts/test.sh` exits 0.

## Blocked by

- #25 (Conversation ETS)

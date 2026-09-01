# Domain Docs

This repository has a single domain context.

## Before exploring

- Read root-level `CONTEXT.md` when it exists.
- Read relevant ADRs in `docs/adr/` when they exist.
- If either path does not exist, proceed silently. Do not create domain documentation until `/domain-modeling` resolves a term or a decision.

## Layout

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
└── src/
```

## Consumer rules

- Use domain terms exactly as defined in `CONTEXT.md` in issues, proposals, hypotheses, and tests; do not substitute glossary-avoided synonyms.
- If a needed concept is absent from the glossary, reconsider whether the repository already uses another term; otherwise note the gap for `/domain-modeling`.
- If proposed work contradicts an ADR, surface that conflict explicitly rather than silently overriding the recorded decision.

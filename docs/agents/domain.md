# Domain Docs

This repository has a single domain context.

## Architecture Decision Records (ADRs)

ADRs in this repository are recorded as GitHub Issues using the Architecture Decision Record issue template (`.github/ISSUE_TEMPLATE/architecture-decision.yml`) and labeled `type:docs` with titles prefixed by `ADR-NNN:`. Do not introduce a markdown directory under `docs/adr/`.

## Before exploring

- Read root-level `CONTEXT.md` when it exists.
- Query accepted and proposed ADR issues via `gh issue list --label type:docs --search "ADR-"`.
- If no ADR issues exist, proceed silently. Do not record an ADR until an architectural decision or significant structural shift is made.

## Layout

```text
/
├── CONTEXT.md
├── AGENTS.md
├── backend/
│   └── lib/
│       ├── backend/
│       │   ├── stations.ex          # Deep public interface module
│       │   └── stations/            # Internal implementation modules
│       └── backend_web/             # Thin delivery layer (HTTP, JSON)
└── web/
    └── src/
        ├── App.tsx                  # Thin root shell
        ├── app/                     # Routing, providers, app initialization
        ├── features/                # Vertical feature slices (e.g. features/station/)
        └── shared/                  # Reused UI primitives, hooks, utils
```

## Consumer rules

- Use domain terms exactly as defined in `CONTEXT.md` in issues, proposals, hypotheses, and tests; do not substitute glossary-avoided synonyms.
- If a needed concept is absent from the glossary, reconsider whether the repository already uses another term; otherwise note the gap for `/domain-modeling`.
- If proposed work contradicts an ADR recorded in GitHub Issues, surface that conflict explicitly rather than silently overriding the recorded decision.

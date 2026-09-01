# Issue tracker: GitHub

Issues and specs for this repository live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, fetching labels as needed.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

Infer the repository from `git remote -v`; `gh` does this automatically when run inside this clone.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: Create one issue labelled `wayfinder:map`. Its body holds the Destination, Notes, Decisions so far, Not yet specified, and Out of scope sections.
- **Child ticket**: Create an issue labelled `wayfinder:<type>`, where `<type>` is `research`, `prototype`, `grilling`, or `task`. Link it to the map as a GitHub sub-issue using `gh api` and the sub-issues endpoint.
- **GitHub sub-issue fallback**: If sub-issues are unavailable, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body.
- **Dependencies**: Use GitHub's native issue dependencies as the canonical, UI-visible blocker relationship. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. Obtain `<blocker-db-id>` with `gh api repos/<owner>/<repo>/issues/<number> --jq .id`; do not use the issue number or `node_id`.
- **Dependency fallback**: If native dependencies are unavailable, add `Blocked by: #<number>, #<number>` at the top of the child body. A ticket is unblocked only when every blocker is closed.
- **Frontier**: List the map's open children, exclude tickets with an open blocker or assignee, then take the first ticket in map order.
- **Claim**: Before any work, assign the ticket to the driving developer with `gh issue edit <number> --add-assignee @me`. An open unassigned ticket is unclaimed.
- **Resolve**: Post the answer as a resolution comment, close the ticket, then append a linked one-line context pointer to the map's Decisions so far section.

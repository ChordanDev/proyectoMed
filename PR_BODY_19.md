## Summary

- Implement the frozen contract from #12 against the merged Expo + Phoenix scaffold from #16, under issue #19.
- Add six Phoenix modules, four controllers, ExUnit coverage for all 11 frozen scenarios, and an Expo capture client with golden-vector parity.
- Author the SDD artifacts (proposal, spec, design, tasks) for the new `station-attempt-capture-implementation` capability.
- No application behavior change until a follow-up apply PR lands; this commit ships only the planning artifacts and the branch setup.

## Linked Issue

Closes #19

## Test Plan

- [x] `bash scripts/test.sh` still green at branch tip (no behavior change yet)
- [x] Frozen #12 spec remains byte-identical
- [x] Implementation spec uses only ADDED requirements; no MODIFIED/REMOVED on the frozen capability

## Changes

| File | Change |
|------|--------|
| `openspec/changes/implement-station-attempt-capture/proposal.md` | New |
| `openspec/changes/implement-station-attempt-capture/exploration.md` | New |
| `openspec/changes/implement-station-attempt-capture/design.md` | New |
| `openspec/changes/implement-station-attempt-capture/tasks.md` | New |
| `openspec/changes/implement-station-attempt-capture/specs/station-attempt-capture-implementation/spec.md` | New (ADDED-only delta) |

## Contributor Checklist

- [x] Linked an approved issue
- [x] Conventional commit format
- [x] No `Co-Authored-By` trailers
---
name: Tech debt / refactor
about: Improve internal code quality while preserving existing behavior.
title: "[Area] Refactor ..."
labels: ''
assignees: ''

---

## Goal

What should become cleaner, safer, or easier to maintain?

## Current problem

Why is the current structure not ideal?

## Non-goals

- No user-facing behavior change unless explicitly listed
- No unrelated rewrites

## Acceptance criteria

- [ ] Existing behavior is preserved
- [ ] Tests still pass
- [ ] New regression tests added if behavior could accidentally change
- [ ] Public API impact is documented, if any

## Suggested approach

Files, types, or functions likely involved.

## Risks

What could accidentally break?

## Areas for the title
Core, iOS, Import, Classification, Reconciliation, Persistence, Sync

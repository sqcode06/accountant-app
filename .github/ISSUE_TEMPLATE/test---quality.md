---
name: Test / quality
about: Add tests, improve CI determinism, or harden quality checks.
title: "[DevEx] Add tests for ..."
labels: ''
assignees: ''

---

## Goal

What risk should this test or quality work reduce?

## Current gap

What is not covered or unstable?

## Acceptance criteria

- [ ] New test covers the missing behavior
- [ ] Test is deterministic across platforms
- [ ] CI passes on Ubuntu and Windows
- [ ] No unrelated behavior changes

## Cases to cover

- [ ] Happy path
- [ ] Invalid input
- [ ] Edge case
- [ ] No partial mutation, if relevant
- [ ] Persistence/import/merge behavior, if relevant

## Notes

Existing tests, flakes, logs, or suspicious files.

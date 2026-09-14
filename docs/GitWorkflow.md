# Working with the repository

Use `main` for a fresh clone, the next iPhone build, and the starting point for
new work. The repository's default branch is `main`.

## What was consolidated

The September 2026 consolidation brings the personal app from
`stabilize/ios-tests-data-protection` at `114f39a` onto `main`. Before that,
`main` was at `119d433`, 55 commits behind the tested app. A signed snapshot
keeps main's history linear without changing the original commits.

The consolidation adds repository guidance and Claude attribution settings.
App code, core code, assets, project configuration, workflows, and tests are
unchanged from the verified baseline. No new feature or TestFlight release is
part of this update.

The existing branches are retained:

| Branches | Purpose now |
| --- | --- |
| `main` | Current app; start new changes here |
| `stabilize/ios-tests-data-protection` | Full reliability-work history through `114f39a` |
| `redesign/ia-design-core` | Earlier app redesign history through `7037459` |
| `core/*` and `issue/*` | Earlier core work and pull-request history |

Those old branches are historical records, not parallel versions to keep
updating. Squashing does not make their commits ancestors of the new main
commit, so GitHub can still describe them as ahead or unmerged. That alone
does not mean their changes are missing. No branch deletion or force push is
needed for this workflow.

## Starting the next change

In a clean checkout:

```sh
git fetch origin
git switch main
git pull --ff-only
git switch -c fix/short-description
```

Keep unrelated local edits safe before switching branches. Open a focused pull
request to `main`, include relevant validation, and use a signed squash commit
for a completed batch. Main's existing rules require verified signatures and
linear history and block force pushes and deletion. Do not weaken those rules
to merge unsigned commits; arrange signing before publishing a new branch.

## Attribution

The project's `.claude/settings.json` disables Claude Code's automatic commit
and pull-request attribution. Keep human authorship and third-party notices
intact. Disclose generated material when relevant to a review, as required by
[CONTRIBUTING.md](../CONTRIBUTING.md); that does not require an AI co-author
trailer. Delegation modes that ignore project settings must receive this
instruction explicitly.

The new main snapshot omits AI co-author trailers. Original trailers remain
in historical commits on the retained branches. Removing those too would
require rewriting published history, which this consolidation does not do.

## Verification carried forward

The app and build inputs match tested revision `9bda415`:

- [Core CI](https://github.com/sqcode06/accountant-app/actions/runs/34881928836):
  339 tests on each of Linux and Windows.
- [Native CI](https://github.com/sqcode06/accountant-app/actions/runs/34881928860):
  Release builds, 92 app tests and nine UI tests on each of iOS 18.5 and 26.2,
  plus the unsigned device archive and privacy metadata check.

The consolidation uses `[skip ci]` because these inputs are unchanged; those
runs are evidence for `9bda415`, not new executions against the consolidation
commit. The tree comparison carries that evidence forward. Physical-device
checks and publication decisions remain in [OwnerReview.md](OwnerReview.md).

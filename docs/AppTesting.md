# App testing

The iOS app sits above `AccountantCore`. The core package already protects the accounting rules, but the app layer still owns important workflow behavior:

- loading a ledger into `AppState`;
- saving successful mutations through `LedgerRepository`;
- surfacing failed writes without losing the user's change;
- mapping app/domain errors into user-facing messages;
- connecting account and transaction workflows to the core.

This document describes the first app-level testing layer.

## Current strategy

The app tests use Swift Testing in `AccountantAppTests`.

The first test layer focuses on `AppState`, not simulator UI automation. This is intentional. `AppState` is the boundary where SwiftUI intent becomes persisted ledger state, and it can be tested quickly without launching the app.

## Test repository

App tests use an in-memory `LedgerRepository`.

This gives each test a clean ledger and avoids the real Application Support JSON file used by the app at runtime.

The in-memory repository can also inject load/save failures.

**Note the contract here changed.** Writes used to save first and commit to `AppState` afterwards, so a failed save left the visible ledger untouched. That ordering put a suspension point between reading the ledger and writing it back, which meant two quick actions could each save over the other and one change was silently lost.

Mutations now commit synchronously on the main actor and the write is debounced behind them. A failed write keeps the change visible, keeps it marked dirty so the next flush retries it, and reports the error. Reverting the change would not have saved the data either — it would only have hidden that nothing was saved, and invited the user to repeat the action into the same failure.

Two consequences for tests:

- **Anything asserting on what reached the repository must `await appState.flushPendingWrites()` first**, or it is racing a 400ms debounce.
- A burst of mutations with no flush between them is deliberately *one* write. `archiveAndRestoreAccountRoundTrip` flushes between its two mutations for exactly this reason.

## What belongs here

Good app-state tests:

- account creation rejects empty names;
- account creation saves a cleaned name;
- rename/archive/restore mutate and persist;
- a failed write keeps the change visible and reports the failure;
- concurrent mutations all survive rather than overwriting each other;
- a burst of mutations coalesces into a single write;
- restoring a backup replaces ledger, budget and rules together;
- manual transaction entry creates draft transactions;
- save-and-finalize creates finalized transactions;
- invalid transaction amounts are surfaced as user-facing errors.

## What does not belong here yet

Do not use app-state tests for:

- pixel-perfect SwiftUI layout;
- full simulator navigation;
- visual theme validation;
- broad end-to-end UI coverage.

Those belong to later UI-test work once the app has deterministic launch/reset hooks.

## Running tests

Core package tests:

```bash
swift test
```

On a machine where the toolchain is not on `PATH` — which is the case on the Linux box this is largely developed on:

```bash
PATH="$HOME/.local/share/swift/swift-6.2-RELEASE-debian12/usr/bin:$PATH" swift test
```

App tests from Xcode:

```text
Product -> Test
```

## Checking app code without Xcode

The app target cannot be compiled without the iOS SDK, but two checks catch a useful amount before you get to a Mac.

**Syntax.** `swiftc -parse` only parses, so it does not need SwiftUI or UIKit to resolve:

```bash
find AccountantApp -name '*.swift' -exec swiftc -parse {} \;
```

Silence means every file is syntactically valid. It says nothing about types.

**Symbols.** Grepping the design-system definitions against their uses catches the most common remaining class of error — a `Theme.` or `Font` or `Metrics.` token that does not exist:

```bash
grep -rho "Theme\.[a-zA-Z]*" AccountantApp | sort -u
grep -o "static var [a-zA-Z]*" AccountantApp/AccountantApp/DesignSystem/Theme.swift | sort -u
```

Neither replaces a build. Both are worth running before pushing work that someone else will build on a Mac.


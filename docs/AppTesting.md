# App testing

The iOS app sits above `AccountantCore`. The core package already protects the accounting rules, but the app layer still owns important workflow behavior:

- loading a ledger into `AppState`;
- saving successful mutations through `LedgerRepository`;
- keeping failed mutations out of visible app state;
- mapping app/domain errors into user-facing messages;
- connecting account and transaction workflows to the core.

This document describes the first app-level testing layer.

## Current strategy

The app tests use Swift Testing in `AccountantAppTests`.

The first test layer focuses on `AppState`, not simulator UI automation. This is intentional. `AppState` is the boundary where SwiftUI intent becomes persisted ledger state, and it can be tested quickly without launching the app.

## Test repository

App tests use an in-memory `LedgerRepository`.

This gives each test a clean ledger and avoids the real Application Support JSON file used by the app at runtime.

The in-memory repository can also inject load/save failures. This matters because failed saves should not update visible app state. A failed transaction should not appear in the UI as if it was safely persisted.

## What belongs here

Good app-state tests:

- account creation rejects empty names;
- account creation saves a cleaned name;
- rename/archive/restore mutate and persist;
- save failure leaves the visible ledger unchanged;
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

App tests from Xcode:

```text
Product -> Test
```


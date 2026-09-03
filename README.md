# Accountant

A personal budgeting app for iOS, and the accounting engine underneath it.

Two things live in this repository:

- **`Sources/AccountantCore`** — a UI-free Swift package that knows how money moves. No SwiftUI, no bank APIs, no platform persistence. It builds and tests on Linux, which is what makes the fast development loop possible.
- **`AccountantApp/`** — the iOS app. SwiftUI, six themes, quick capture, an evening review queue, budgets, statement import, reconciliation, export and restore.

The split is deliberate and load-bearing. Every accounting rule is in the package and covered by tests that run in under a second on any machine; the app target holds views and app state and nothing that decides what a balance means.

## Status

The app builds and runs. It is usable day to day and is not yet something to put on the App Store.

**Working:**

- four-tab structure: Overview, Activity, Budget, Settings, with a capture button in the middle;
- quick capture — type an amount, tap a category, two gestures, everything lands as a draft;
- an evening review queue where drafts get checked and confirmed as a batch;
- budgets: monthly limits per category, with unbudgeted spending shown rather than hidden;
- statement import from a file, with presets for Swedbank, LHV and Revolut;
- deterministic classification rules applied at import;
- reconciliation against a statement balance, by ticking entries off;
- six themes and matching alternate app icons;
- an onboarding guide, a danger zone, and per-account currency;
- CSV export and a complete backup that can be restored;
- a daily review reminder, scheduled only when something is actually waiting.

**Not there yet:**

- multi-device sync. The merge primitives exist and are tested, but nothing in the app calls them — see [Merge and sync foundation](#merge-and-sync-foundation);
- currency conversion. Amounts are never converted, anywhere, on purpose;
- recurring transactions;
- charts.

**Verified how:** the core has 270 XCTest plus 3 Swift Testing tests, all runnable on Linux. The app target's tests need Xcode. See [`docs/AppTesting.md`](docs/AppTesting.md).

Architecture notes for the app layer: [`docs/AppArchitecture.md`](docs/AppArchitecture.md). Redesign working notes: [`docs/Redesign.md`](docs/Redesign.md). Voice and palette: [`docs/Brand.md`](docs/Brand.md).

## Mental model

The original idea behind Accountant is a transaction-account matrix:

```text
rows    = transactions
columns = accounts / money buckets
cells   = how a transaction changes an account
```

In code, the full matrix is stored sparsely. A transaction only stores the accounts it actually touches:

```text
Transaction: "Rimi"
  Bank       -42 EUR
  Groceries  +42 EUR
```

That is classic double-entry thinking, adapted for personal budgeting.

A purchase is not “money disappears.” It is:

```text
asset account decreases
expense account increases
```

An income event is:

```text
asset account increases
income account decreases
```

A transfer is:

```text
one asset decreases
another asset increases
```

The important invariant is simple:

```text
sum(transaction.postings.amount) == 0
```

Money does not appear from fog. It moves.

## Quick start

```bash
swift test
```

This is a Swift Package Manager project. The package defines the `AccountantCore` library target and the `AccountantCoreTests` test target. It has no dependencies and builds on Linux, so the core loop needs nothing but a toolchain.

The iOS app is separate. Open `AccountantApp/AccountantApp.xcodeproj` and run it from Xcode. The project uses Xcode 16 synchronized file groups, so new source files are picked up without editing the project file.

A typical development loop is:

```bash
swift test
swift test --filter ImportClassificationTests
swift test --filter MVPWorkflowTests.testImportClassifyApplyFinalizeAndReconcileWorkflow
```

## A small manual-entry example

```swift
import AccountantCore
import Foundation

let eur = Currency("EUR")

let bank = Account(name: "Swedbank", kind: .asset)
let groceries = Account(name: "Groceries", kind: .expense)

var ledger = Ledger()
ledger.addAccount(bank)
ledger.addAccount(groceries)

let tx = try Transaction.draftExpense(
    paidFrom: bank.id,
    category: groceries.id,
    amount: Money(Decimal(42), currency: eur),
    date: Date(),
    memo: "Rimi"
)

try ledger.addTransaction(tx)
try ledger.finalizeTransaction(id: tx.id)

let bankBalance = ledger.balance(of: bank.id, currency: eur)
```

The convenience constructor creates the postings:

```text
Bank       -42 EUR
Groceries  +42 EUR
```

The ledger still validates the transaction before accepting it.

## Core domain concepts

### Currency and Money

`Currency` stores an uppercase currency code such as `EUR` or `USD`.

`Money` stores a `Decimal` amount and a `Currency`.

```swift
let eur = Currency("EUR")
let amount = Money(Decimal(12), currency: eur)
```

The core currently treats regular transactions as single-currency. Multi-currency behavior should later be implemented through explicit conversion transactions, not silent hidden exchange rates.

### Accounts

An `Account` is a named bucket with a stable ID, a kind, and a status.

```swift
let bank = Account(name: "Bank", kind: .asset)
let salary = Account(name: "Salary", kind: .income)
let groceries = Account(name: "Groceries", kind: .expense)
```

Supported account kinds:

```swift
.asset
.liability
.income
.expense
.equity
.clearing
```

Supported account statuses:

```swift
.active
.archived
```

Archived accounts remain available for historical queries and balances, but new transactions cannot be added to archived accounts.

### Postings

A `Posting` is one account-level effect inside a transaction:

```swift
Posting(accountID: bank.id, money: Money(Decimal(-42), currency: eur))
```

Transactions are built from postings.

### Transactions

A `Transaction` has:

- stable `TransactionID`;
- effective `date`;
- optional `memo`;
- optional `origin`;
- one or more postings;
- lifecycle state: `.draft` or `.finalized`;
- timestamps: `createdAt`, `updatedAt`, `finalizedAt`.

Transactions start as drafts when they are manually entered or imported. Drafts can be edited or deleted. Finalized transactions are treated as trusted accounting facts and cannot be edited through the normal ledger API.

### Transaction origins

`TransactionOrigin` links a transaction to an external source:

```swift
TransactionOrigin(source: "Swedbank", externalID: "ABC123")
```

Origins make imports idempotent and help merge logic avoid duplicates across devices or snapshots.

## Ledger invariants

The ledger is the gatekeeper. Frontends should not mutate raw arrays directly.

Current invariants:

- transactions must have at least two postings;
- regular transactions must use one currency only;
- posting amounts must sum to zero;
- transaction IDs must be unique within a ledger;
- postings must reference known accounts;
- new or edited transactions cannot reference archived accounts;
- finalized transactions cannot be edited or deleted through normal APIs;
- imports and merges avoid partial mutation where atomic behavior matters;
- queries derive balances from transactions instead of storing duplicate balance state.

These rules are not decoration. They are what keep the app from becoming a stylish spreadsheet with a knife taped to it.

## Draft and finalized lifecycle

The lifecycle is designed around real manual bookkeeping:

```text
draft      = editable, reviewable, local working copy
finalized  = trusted, immutable accounting fact
```

Typical flow:

```swift
let tx = try Transaction.draftExpense(
    paidFrom: bank.id,
    category: groceries.id,
    amount: Money(Decimal(12), currency: eur),
    memo: "Snacks"
)

try ledger.addTransaction(tx)

// Edit while draft if needed.
try ledger.updateDraftTransaction(id: tx.id) { draft in
    draft.memo = "Rimi snacks"
}

// Trust it.
try ledger.finalizeTransaction(id: tx.id)
```

This keeps the app humane. Mistakes are allowed while entering data, but trusted history stays stable once finalized.

## Import workflow

Import is intentionally a preview-first workflow.

```text
BankLine[]
  -> ImportPreview
  -> proposed / skipped duplicate / failed outcomes
  -> apply selected proposed drafts
  -> finalize after review
```

A simple import pipeline:

```swift
let pipeline = ImportPipeline(
    source: "Swedbank",
    statementAccountID: bank.id,
    defaultCounterpartyAccountID: uncategorized.id
)

let lines = [
    BankLine(
        date: Date(),
        amount: Decimal(-42),
        currency: eur,
        description: "RIMI EESTI",
        externalID: "RIMI-001"
    )
]

let preview = pipeline.previewImport(lines: lines, into: ledger)
let report = try pipeline.applyImportPreview(preview, to: &ledger)
```

Import preview handles:

- duplicate external IDs already present in the ledger;
- duplicate external IDs inside the same batch;
- missing external IDs as warnings;
- unknown accounts;
- archived accounts;
- invalid generated transactions.

`applyImportPreview` inserts proposed drafts atomically: if insertion fails, the original ledger remains unchanged.

## Classification workflow

Classification is deterministic and suggestion-based.

Rules inspect imported bank lines and draft transactions, then return suggestions. They do not mutate the ledger.

```swift
let classifier = TransactionClassifier(rules: [
    DescriptionContainsRule(
        "rimi",
        counterpartyAccountID: groceries.id,
        cleanedMemo: "Rimi"
    ),
    DescriptionContainsRule(
        "bolt food",
        counterpartyAccountID: foodDelivery.id,
        cleanedMemo: "Bolt Food"
    )
])
```

Classified import preview:

```swift
let preview = pipeline.previewImport(
    lines: lines,
    into: ledger,
    classifier: classifier
)
```

Only proposed drafts are classified. Skipped duplicates and failed import outcomes remain untouched. Existing import warnings, such as missing external IDs, are preserved.

Classification is deliberately not machine learning yet. The current goal is explainable, deterministic, testable bookkeeping assistance.

## Reconciliation

Reconciliation compares the ledger balance for one account against an external statement balance.

```swift
let report = try ledger.reconcileAccount(
    bank.id,
    statementBalance: Money(Decimal(940), currency: eur),
    asOf: Date(),
    includeDrafts: false
)
```

The report contains:

- account ID;
- currency;
- as-of date;
- ledger balance;
- statement balance;
- difference, computed as `statementBalance - ledgerBalance`;
- status: `.matched` or `.mismatched`;
- whether drafts were included.

Archived accounts can still be reconciled because historical balances remain meaningful after an account is closed.

## Query layer

### Account balance

```swift
let balance = ledger.balance(
    of: bank.id,
    currency: eur,
    asOf: Date(),
    includeDrafts: false
)
```

### Account statement

```swift
let lines = ledger.statement(
    for: bank.id,
    currency: eur,
    includeDrafts: true
)
```

Each statement line contains:

- transaction ID;
- date;
- memo;
- delta;
- running balance.

### Account summaries

```swift
let summaries = ledger.accountBalanceSummaries(
    currency: eur,
    asOf: Date(),
    includeDrafts: false,
    includeArchived: false
)
```

Summaries are ordered deterministically by account kind, lowercased name, then stable ID.

Archived accounts are excluded by default, but historical transactions involving archived accounts still affect balances of active accounts.

### Account kind summaries

```swift
let kindSummaries = ledger.accountKindBalanceSummaries(
    currency: eur,
    asOf: Date()
)
```

Kind summaries use raw accounting balances. For example, income accounts usually have negative balances under the current double-entry convention. UI code can invert signs for presentation if needed, but the core does not hide accounting truth.

## Merge and sync foundation

`mergeFinalized(from:)` merges finalized transactions from another ledger into the local ledger.

Important properties:

- incoming drafts are ignored;
- finalized transactions can deduplicate by transaction ID or origin;
- account conflicts are handled according to merge options;
- transaction conflicts are explicit;
- merge mutates a working copy and commits only at the end;
- merge reports added, skipped, updated, and conflicting items.

**Nothing in the app calls any of this.** The merge stack is written, tested and unreachable — it was built for multi-device sync that has no transport behind it yet. Worth knowing before reading it as a working feature, and worth keeping, because the hard part of sync is the conflict rules and those are done.

## Persistence

`JSONLedgerStore` saves and loads ledgers using a versioned `PersistedLedger`.

Current persistence is intentionally simple:

- human-readable JSON;
- sorted keys;
- schema version;
- backwards-compatible decoding for older model shapes where supported.

This is good enough for the core MVP and early app prototypes. SQLite, CloudKit, or other storage layers can be added later without changing the accounting model.

An unreadable file is **quarantined rather than overwritten**: it is renamed aside before the load returns, and the app refuses every write until the user chooses to start fresh or retry. That path is the one that used to silently destroy data, so it is tested from both ends.

`LedgerBackup` is the export format — ledger, budget and classification rules in one document, with its own format version separate from the ledger schema version. `LedgerExport` writes the same data as CSV for spreadsheets. Both share the store's date strategy, because a backup written with a different encoding is one this app cannot read back.

## Repository structure

```text
Sources/AccountantCore
├── Budget
│   ├── Budget.swift
│   ├── BudgetPeriod.swift
│   └── BudgetReport.swift
│
├── Classification
│   ├── ClassificationError.swift
│   ├── ClassificationRule.swift
│   ├── ClassificationRuleConfiguration.swift
│   ├── ClassificationSuggestion.swift
│   ├── DescriptionContainsRule.swift
│   └── TransactionClassifier.swift
│
├── Export
│   ├── LedgerBackup.swift
│   └── LedgerExport.swift
│
├── Import
│   ├── BankLine.swift
│   ├── CSVBankLineParser.swift
│   ├── ImportClassification.swift
│   ├── ImportPipeline.swift
│   ├── ImportSession.swift
│   └── StatementFormat.swift
│
├── Persistence
│   ├── FileQuarantine.swift
│   ├── JSONFileStore.swift
│   ├── LedgerDateCoding.swift
│   ├── LedgerStore.swift
│   └── PersistedLedger.swift
│
├── Query
│   ├── AccountSummary.swift
│   └── LedgerQuery.swift
│
├── Reconciliation
│   └── Reconciliation.swift
│
├── Sync
│   ├── LedgerMerge.swift
│   ├── LedgerMergeError.swift
│   └── TransactionFingerprint.swift
│
├── AccountantCore.swift
├── Currency.swift
├── DecimalParsing.swift
├── Ledger.swift
├── LedgerError.swift
├── Models.swift
├── Money.swift
└── TransactionCreation.swift
```

Tests live in:

```text
Tests/AccountantCoreTests
```

The most important “whole system” test is:

```text
MVPWorkflowTests
```

It exercises the main user-facing flow:

```text
create accounts
import bank lines
classify drafts
apply import preview
finalize transactions
reconcile bank balance
verify account and category balances
```

Account summary behavior is covered separately by `AccountSummaryTests`, where filtering, archived-account handling, deterministic ordering, and kind totals are easier to check precisely.

`PublicAPISurfaceTests` is worth knowing about. Every other test file uses `@testable import`, which sees `internal` symbols — so a missing `public` is invisible in the package and fatal in the app, where the whole suite passes and then Xcode reports "cannot find type X in scope". That one file imports the module the way the app does. Add to it whenever the app starts using new core API.

## Development philosophy

This project is being built test-first where possible.

Preferred workflow:

```text
1. Decide the behavior.
2. Write tests for happy paths and edge cases.
3. Implement the smallest clean design that passes.
4. Refactor carefully.
5. Keep the public API honest.
```

Things we care about:

- explicit accounting over hidden magic;
- domain errors instead of vague failures;
- preview/report workflows before mutation;
- deterministic ordering;
- atomic behavior where partial mutation would be dangerous;
- UI-free core logic;
- readable tests that document intent.

## What to work on next

In rough order of how much it matters:

1. **A clean LHV export.** The LHV preset's column names are a guess made from a copy-pasted sample whose columns were shifted, and every row was correctly rejected. Swedbank and Revolut are verified against real files.
2. **Reminders on a real device.** The logic is tested, but permission prompts, delivery and the Settings toggle have only been checked by inspection.
3. **Sync.** The merge rules are done and tested. What is missing is a transport and the UX around conflicts.
4. **Recurring transactions.** Rent and subscriptions are the entries most worth not typing every month.
5. **Charts.** Deliberately last. A budget app earns trust by being right before it earns attention by being pretty.

Longer-term and deliberately not started: OCR receipts, bank API integration, learned classification, multi-currency conversion, SQLite.

## Design warning for future work

Do not let the UI mutate the ledger internals directly.

Good direction:

```swift
let tx = try Transaction.draftExpense(...)
try ledger.addTransaction(tx)
try ledger.finalizeTransaction(id: tx.id)
```

Risky direction:

```swift
ledger.transactions.append(...)
```

The core is useful because it acts as a controlled accounting kernel. Keep the kernel boring, explicit, and stubborn. The app can be beautiful on top.

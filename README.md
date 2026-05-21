# AccountantCore

AccountantCore is the accounting engine for a future personal budgeting app. The planned app may eventually have an iOS interface, Liquid Glass polish, import screens, reconciliation tools, and all the pleasant dashboard furniture. This package is the quieter thing underneath it: a small, testable Swift domain core that knows how money moves.

It is intentionally UI-free. No SwiftUI views. No bank API assumptions. No platform-specific persistence. Just accounts, transactions, imports, classification, reconciliation, summaries, and a ledger that tries very hard not to let nonsense through the door.

## Status

Core MVP: **feature-complete enough to power a first local budgeting app prototype**.

Current core capabilities:

- account taxonomy: assets, liabilities, income, expenses, equity, clearing;
- draft/finalized transaction lifecycle;
- same-currency double-entry transaction validation;
- manual transaction convenience constructors;
- JSON persistence with schema versioning;
- query layer for balances, statements, account summaries, and kind summaries;
- bank-line import preview and atomic apply;
- deterministic rule-based classification;
- classified import preview;
- finalized snapshot merge foundation;
- account reconciliation;
- an end-to-end MVP workflow test.

The next major work should be app integration, documentation refinement, and UX-facing workflows, not more hidden core features.

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

This is a Swift Package Manager project. The package defines the `AccountantCore` library target and the `AccountantCoreTests` test target.

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

This is not full sync UX yet. It is the core merge primitive future sync can build on.

## Persistence

`JSONLedgerStore` saves and loads ledgers using a versioned `PersistedLedger`.

Current persistence is intentionally simple:

- human-readable JSON;
- sorted keys;
- schema version;
- backwards-compatible decoding for older model shapes where supported.

This is good enough for the core MVP and early app prototypes. SQLite, CloudKit, or other storage layers can be added later without changing the accounting model.

## Repository structure

```text
Sources/AccountantCore
├── Classification
│   ├── ClassificationError.swift
│   ├── ClassificationRule.swift
│   ├── ClassificationSuggestion.swift
│   ├── DescriptionContainsRule.swift
│   └── TransactionClassifier.swift
│
├── Import
│   ├── BankLine.swift
│   ├── ImportClassification.swift
│   ├── ImportPipeline.swift
│   └── ImportSession.swift
│
├── Persistence
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
├── Currency.swift
├── Ledger.swift
├── LedgerError.swift
├── Models.swift
├── Money.swift
├── Money+Ops.swift
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

## Current MVP scope

The core MVP supports:

- manually creating draft expense, income, and transfer transactions;
- validating and finalizing transactions;
- managing accounts and archiving old accounts;
- importing bank-like lines into draft transactions;
- classifying imported drafts using deterministic rules;
- applying import previews safely;
- querying balances and statements;
- summarizing accounts and account kinds;
- reconciling balances against external statement values;
- persisting ledgers to JSON;
- merging finalized snapshots.

This is enough to start building a first local app prototype.

## Not implemented yet

These are intentionally outside the current core MVP:

- iOS app UI;
- account setup wizard;
- import review screen;
- reconciliation screen;
- classification rule editor;
- bank CSV parser zoo;
- OCR receipts;
- automatic bank API integration;
- learned/adaptive classification;
- machine-learning suggestions;
- recurring transactions;
- budgeting/envelope planning;
- multi-currency conversion transactions;
- CloudKit or multi-device sync UX;
- SQLite persistence;
- charts and dashboard presentation logic.

## Future roadmap parking lot

These should later become GitHub Project issues or cards.

### Import

- Bank statement format parsers.
- Import preview highlighting and correction tools.
- Better duplicate review UX.
- Statement-line source metadata.
- Batch finalization from import review.

### Classification

- Rule editor in the app.
- Merchant normalization.
- Learned rules from user corrections.
- Confidence and explanation display.
- Optional semantic or ML-based suggestions later.

### Reconciliation

- Cleared/uncleared transaction state.
- Statement line matching.
- Difference investigation tools.
- Highlight likely missing or duplicate transactions.
- Reconciliation history.

### Multi-currency

- Explicit conversion transaction type.
- Stored effective rate metadata.
- Optional fee handling.
- Reporting in native and selected display currencies.
- No silent auto-conversion inside ordinary transactions.

### App layer

- SwiftUI app skeleton.
- Local store wiring.
- Account setup flow.
- Manual transaction entry.
- Import review screen.
- Summary dashboard.
- Reconciliation screen.
- Liquid Glass visual design.

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

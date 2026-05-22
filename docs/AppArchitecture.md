# Accountant iOS App Architecture

This document defines how the future iOS app should sit on top of `AccountantCore`.

The goal is simple: keep the accounting kernel boring, explicit, and correct while allowing the iOS app to become pleasant, fast, and eventually beautiful. The UI can wear Liquid Glass. The core should remain steel.

## Status

This document belongs to roadmap issue `#3 [Docs] Add app architecture notes`.

It is intentionally written before the first iOS app shell so the app does not grow around accidental decisions.

## Principles

### 1. AccountantCore owns accounting truth

`AccountantCore` already knows how to:

- create and validate transactions;
- manage accounts;
- preserve draft/finalized lifecycle rules;
- import and classify bank-like lines;
- reconcile balances;
- calculate account summaries;
- persist ledgers through `JSONLedgerStore`.

The iOS app should not reimplement those rules.

Good:

```swift
let tx = try Transaction.draftExpense(
    paidFrom: bank.id,
    category: groceries.id,
    amount: Money(Decimal(42), currency: eur),
    memo: "Rimi"
)

try ledger.addTransaction(tx)
try ledger.finalizeTransaction(id: tx.id)
```

Bad:

```swift
// Do not treat a detached ledger snapshot as app state and persist it directly.
var editedLedgerSnapshot = appState.ledger
// ...mutate or replace state outside AppState's user-intent methods...
let data = try JSONEncoder().encode(editedLedgerSnapshot)
try data.write(to: ledgerURL)
```

The ledger is a gatekeeper, and AppState / LedgerRepository are the app's controlled doorway. Do not build parallel mutation or persistence paths around them.

### 2. SwiftUI views should display state and send intent

Views should not calculate balances, decide transaction validity, deduplicate imports, or reconcile accounts. Views should show data and call intent-shaped methods on app state or view models.

Good direction:

```text
Button tap
  -> ViewModel.recordExpense(...)
  -> Transaction.draftExpense(...)
  -> Ledger.addTransaction(...)
  -> LedgerRepository.save(...)
```

Risky direction:

```text
Button tap
  -> View manually edits ledger arrays
  -> View recalculates balances
  -> View saves raw JSON directly
```

### 3. Mutations should be explicit

Every user-visible change should pass through a named operation:

- create account;
- rename account;
- archive account;
- create draft transaction;
- update draft transaction;
- finalize transaction;
- import preview;
- apply import preview;
- reconcile account.

If a future UI action cannot be described as a clear operation, the design probably needs another thinking pass.

### 4. Persistence should sit below app state

Views should not know file paths. Most view models should not know file paths either.

A small repository layer should wrap storage:

```text
SwiftUI View
  -> AppState / ViewModel
  -> LedgerRepository
  -> JSONLedgerStore
  -> local file
```

This makes it easier to replace JSON with SQLite, CloudKit, or a test repository later.

## Proposed high-level architecture

```text
┌─────────────────────────────────────────────┐
│ SwiftUI Views                               │
│ screens, controls, navigation, formatting   │
└──────────────────────┬──────────────────────┘
                       │ user intent
                       ▼
┌─────────────────────────────────────────────┐
│ App State / View Models                     │
│ observable state, commands, error mapping   │
└──────────────────────┬──────────────────────┘
                       │ domain operations
                       ▼
┌─────────────────────────────────────────────┐
│ AccountantCore                              │
│ Ledger, accounts, transactions, queries     │
│ import, classification, reconciliation      │
└──────────────────────┬──────────────────────┘
                       │ load / save
                       ▼
┌─────────────────────────────────────────────┐
│ LedgerRepository                            │
│ app-specific persistence boundary           │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│ JSONLedgerStore or future storage adapter   │
└─────────────────────────────────────────────┘
```

The boundary between `App State / View Models` and `AccountantCore` is the most important one. That is where UI intent becomes accounting behavior.

## Suggested app target layout

The exact Xcode structure can evolve, but the first app should roughly follow this shape:

```text
AccountantApp
├── AccountantApp.swift
├── App
│   ├── AppState.swift
│   ├── AppRoute.swift
│   └── AppError.swift
│
├── Persistence
│   ├── LedgerRepository.swift
│   └── LocalJSONLedgerRepository.swift
│
├── Features
│   ├── Dashboard
│   │   ├── DashboardView.swift
│   │   └── DashboardViewModel.swift
│   │
│   ├── Accounts
│   │   ├── AccountListView.swift
│   │   ├── AccountEditorView.swift
│   │   └── AccountSetupViewModel.swift
│   │
│   ├── Transactions
│   │   ├── ManualTransactionEntryView.swift
│   │   └── ManualTransactionEntryViewModel.swift
│   │
│   ├── ImportReview
│   │   ├── ImportPreviewView.swift
│   │   └── ImportPreviewViewModel.swift
│   │
│   └── Reconciliation
│       ├── ReconciliationView.swift
│       └── ReconciliationViewModel.swift
│
└── Shared
    ├── Formatters
    ├── Components
    └── ViewState
```

Early on, this can be much smaller. The goal is not ceremony. The goal is to avoid putting persistence, navigation, formatting, and accounting rules into the same file.

## App state

For the first local prototype, one top-level observable app state is enough.

Conceptually:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published var lastError: AppError?

    private let repository: LedgerRepository

    init(repository: LedgerRepository) async {
        self.repository = repository

        do {
            self.ledger = try await repository.loadOrCreate()
        } catch {
            self.ledger = Ledger()
            self.lastError = AppError(error)
        }
    }

    func save() async {
        do {
            try await repository.save(ledger)
        } catch {
            lastError = AppError(error)
        }
    }
}
```

This is not final code. It is the intended responsibility split:

- `AppState` owns the loaded ledger for the session;
- it exposes read-only ledger state to views;
- it offers methods that perform safe mutations;
- it saves after successful mutations;
- it maps thrown domain/storage errors into user-facing app errors.

### Why `private(set)`?

Views should be able to read the ledger, but not freely replace it. Mutations should go through methods that can validate, save, and report errors.

Good:

```swift
try await appState.recordExpense(...)
```

Bad:

```swift
appState.ledger = someRandomLedger
```

## Repository boundary

Define an app-level repository protocol instead of letting the app call `JSONLedgerStore` everywhere.

```swift
protocol LedgerRepository: Sendable {
    func loadOrCreate() async throws -> Ledger
    func save(_ ledger: Ledger) async throws
}
```

Then a local implementation can wrap the current core store:

```swift
struct LocalJSONLedgerRepository: LedgerRepository {
    let store: JSONLedgerStore

    func loadOrCreate() async throws -> Ledger {
        do {
            return try store.load()
        } catch LedgerStoreError.fileNotFound {
            return Ledger()
        }
    }

    func save(_ ledger: Ledger) async throws {
        try store.save(ledger)
    }
}
```

For the first version, this may be synchronous internally. The protocol still gives the app a clean seam for future storage changes.

### Missing-file behavior

The app-level repository should decide what happens when no ledger file exists.

Recommended behavior:

```text
loadOrCreate()
  if file exists:
      return saved ledger
  if file does not exist:
      return empty ledger
  otherwise:
      throw storage error
```

Do not put this policy in every view.

## User-intent operations

The app should expose operations that match what users actually do.

### Create account

```swift
func createAccount(name: String, kind: AccountKind) async {
    let account = Account(name: name, kind: kind)
    ledger.addAccount(account)
    await save()
}
```

### Archive account

```swift
func archiveAccount(_ id: AccountID) async {
    do {
        try ledger.archiveAccount(id: id)
        await save()
    } catch {
        lastError = AppError(error)
    }
}
```

### Record expense

```swift
func recordExpense(
    paidFrom: AccountID,
    category: AccountID,
    amount: Money,
    date: Date,
    memo: String?
) async {
    do {
        let tx = try Transaction.draftExpense(
            paidFrom: paidFrom,
            category: category,
            amount: amount,
            date: date,
            memo: memo
        )

        try ledger.addTransaction(tx)
        await save()
    } catch {
        lastError = AppError(error)
    }
}
```

### Finalize transaction

```swift
func finalizeTransaction(_ id: TransactionID) async {
    do {
        try ledger.finalizeTransaction(id: id)
        await save()
    } catch {
        lastError = AppError(error)
    }
}
```

Keep this shape: app method, core call, save, error mapping.

## Dashboard data

The dashboard should not compute its own balances. It should ask the core query layer.

Recommended view model data:

```swift
struct DashboardState {
    var accountSummaries: [AccountBalanceSummary]
    var kindSummaries: [AccountKindBalanceSummary]
}
```

Computed from:

```swift
let accountSummaries = ledger.accountBalanceSummaries(
    currency: selectedCurrency,
    asOf: Date(),
    includeDrafts: false,
    includeArchived: false
)

let kindSummaries = ledger.accountKindBalanceSummaries(
    currency: selectedCurrency,
    asOf: Date(),
    includeDrafts: false,
    includeArchived: false
)
```

Formatting decisions, such as whether income appears as positive in charts, belong in the presentation layer. Core balances remain raw accounting balances.

## Manual transaction entry

The first manual-entry UI should support three modes:

```text
Expense
Income
Transfer
```

Each mode maps to one convenience constructor:

```text
Expense  -> Transaction.draftExpense(...)
Income   -> Transaction.draftIncome(...)
Transfer -> Transaction.draftTransfer(...)
```

The UI should collect:

- amount;
- currency;
- date;
- memo;
- source/destination/category accounts depending on mode.

It should not manually build postings unless the future split-transaction UI explicitly requires it.

## Import review

Import is a preview workflow, not a direct mutation workflow.

Recommended app flow:

```text
User chooses/imports lines
  -> parser produces [BankLine]
  -> pipeline.previewImport(..., classifier: ...)
  -> ImportPreview screen displays outcomes
  -> user applies proposed drafts
  -> app saves ledger
```

Only `applyImportPreview` mutates the ledger. Preview itself should be read-only.

The UI should display:

- proposed transactions;
- warnings, such as missing external ID;
- skipped duplicates;
- failed lines and error reasons.

Do not finalize imported drafts automatically in the first version. Imported data should remain reviewable.

## Classification rules

For the first app version, deterministic rules are enough.

A future app-level rule model might look like:

```swift
struct StoredClassificationRule: Codable, Identifiable {
    var id: UUID
    var containsText: String
    var counterpartyAccountID: AccountID?
    var cleanedMemo: String?
}
```

It can be converted into core rules:

```swift
let classifier = TransactionClassifier(
    rules: storedRules.map {
        DescriptionContainsRule(
            $0.containsText,
            counterpartyAccountID: $0.counterpartyAccountID,
            cleanedMemo: $0.cleanedMemo
        )
    }
)
```

Do not add adaptive/ML classification until deterministic rules and their review UI are comfortable.

## Reconciliation screen

The first reconciliation screen should be balance-level only.

Inputs:

- account;
- currency;
- as-of date;
- external statement balance;
- include drafts toggle, probably off by default.

Core call:

```swift
let report = try ledger.reconcileAccount(
    accountID,
    statementBalance: statementBalance,
    asOf: asOf,
    includeDrafts: includeDrafts
)
```

Output:

- ledger balance;
- statement balance;
- difference;
- matched/mismatched status.

Do not implement cleared/uncleared transaction state in the first reconciliation UI. That is a later model decision.

## Error handling

Domain errors should be mapped into app-level messages.

Recommended shape:

```swift
enum AppError: Equatable {
    case invalidAmount
    case accountNotFound
    case accountArchived
    case transactionNotFound
    case transactionFinalized
    case importFailed
    case storageFailed
    case unknown
}
```

The exact enum can evolve. The important rule is that SwiftUI should not display raw debug descriptions from thrown errors.

Good:

```text
"This account is archived. Restore it before adding new transactions."
```

Bad:

```text
"accountArchived(AccountID(rawValue: ...))"
```

## Testing strategy for app work

Keep `AccountantCoreTests` as the main domain correctness suite.

For the app target, add lighter tests around:

- view model commands;
- repository missing-file behavior;
- error mapping;
- state changes after core operations;
- persistence smoke tests.

A good app-level test does not need to re-test double-entry accounting. The core already does that. It should test that the app calls the core correctly and responds to outcomes correctly.

## First iteration plan

The current roadmap iteration should land in this order:

```text
#3 [Docs] Add app architecture notes
#1 [iOS] Create SwiftUI app shell
#2 [Persistence] Wire local JSON ledger store
```

Why this order:

1. Document the boundary.
2. Create the shell.
3. Wire storage into the shell.

Do not start with import UI. The app needs a skeleton and persistence first.

## Non-goals for the first app shell

The first app shell should not include:

- import review UI;
- reconciliation UI;
- rule editor;
- charts;
- OCR;
- CloudKit;
- SQLite;
- multi-currency conversion;
- adaptive classification.

Those belong to later roadmap cards.

## Architectural guardrails

Before merging app-layer changes, check:

- Does SwiftUI call public `AccountantCore` APIs instead of mutating internals?
- Are balances and summaries computed by the core?
- Is persistence hidden behind a repository?
- Is every mutation followed by an intentional save or explicit non-save reason?
- Are errors mapped into app-level messages?
- Are tests added where the app makes decisions?
- Did docs/examples change if the architecture changed?

If the answer to any of these is no, the branch needs another pass.

## Future evolution

This architecture is intentionally local-first.

Possible future upgrades:

- SQLite repository;
- CloudKit repository;
- import parser registry;
- rule editor and saved classification rules;
- reconciliation history;
- cleared/uncleared transaction state;
- explicit FX conversion transactions;
- dashboard charts;
- Liquid Glass visual layer.

These should extend the structure, not invert it.

# App redesign — working notes

Living document for the `redesign/ia-design-core` work. Kept in the repo so the
plan survives any particular machine or session.

## Why this exists

The core was good and the app on top of it was not, for a structural reason: the
app's information architecture mirrored the Swift package's folder layout.
`Sources/AccountantCore/{Query, Import, Reconciliation, Classification}` became the
tabs `Summary / Import / Reconcile / Accounts / Transactions`. PRs #4–#10 each
added a core module and a tab to match. Five screens were bolted to a `TabView`;
nobody designed an app.

Each screen was individually competent, which is why it was hard to name what felt
wrong.

## Decisions

**Audience.** Built for someone who knows double-entry. The accounting model stays
precise and visible; the *language* is human. Equity and Clearing move behind an
Advanced disclosure rather than being removed.

**No implicit currency conversion, ever.** Balances group by currency. Multi-currency
goes through explicit conversion transactions, per the core README.

**Schema may break.** Currently version 4. In practice every added field has a
default, so v3 files still load correctly.

**Money colour is not "negative = red".** Spending is the ordinary case in a
budgeting app; colouring every expense red turns a normal month into a wall of
alarm. Green marks money in. Red is reserved for a balance actually in deficit.

**`Account.currency` is optional, not required.** Balance-bearing accounts (asset,
liability, clearing) declare one and are protected against foreign-currency
postings. Category accounts (income, expense, equity) leave it nil and accept any
currency — groceries bought in euros and in dollars are both groceries. Forcing a
single currency onto a category would be wrong.

Known gap: an asset account with `currency == nil` is still unprotected. The app
always sets one on creation, but the core does not force it. Tightening this means
rewriting ~177 test fixtures for no additional correctness today.

## Status

### Done — core (verified, 270 XCTest + 3 Swift Testing tests passing)

- `Account.currency`, `sortOrder`, `symbolName`, `colorToken`.
- `Posting.cleared`, orthogonal to `Transaction.state`:
  - `state` — *have I confirmed this is correct?* (governs editability)
  - `cleared` — *has the bank seen it?* (governs reconciliation)
- `ReconciliationReport.clearedBalance` + `uncleared`; `Ledger.setCleared`, which
  works on finalized transactions because clearing is a statement fact, not an edit.
- `accountBalanceSummaries` rewritten O(A·T) → O(T+P), single pass.
- CSV parsing collects per-row errors instead of aborting the batch.
- **Budgets**: `BudgetPeriod`, `BudgetTarget`, `BudgetReport`. Monthly category
  targets, deliberately outside `Ledger` — an intention is not an accounting fact.
- **Batch confirmation**: `finalizeTransactions(ids:)`, atomic, backing the
  end-of-day review.
- Schema v4.
- **Statement parsing for real exports**: `DecimalParsing` (decimal commas,
  grouping, trailing minus, accounting parentheses), `StatementFormat` with sign
  conventions and structural-row filters, presets for Swedbank, LHV and Revolut.
- **Bank fees as a third posting** on the same transaction rather than a fabricated
  second one.
- **Quarantine on unreadable file** — renamed aside before the load returns, so the
  data survives even if every layer above misbehaves.
- **Export and backup**: `LedgerExport` (CSV) and `LedgerBackup` (ledger + budget +
  rules in one restorable document), sharing the store's date strategy.
- `ClassificationRuleConfiguration` moved down from the app target — it is pure
  domain, and the core could not otherwise describe a third of the app's own state.

Four real defects fixed, not just design work:

1. **Money vanished.** A posting in the wrong currency was accepted by the ledger,
   then filtered out of every balance query. No error, no trace.
2. **Reconciliation could not reconcile.** Net difference only — no way to find out
   *why* you disagreed with the bank.
3. **Merge fingerprint regression** (introduced and caught within this branch).
   `TransactionFingerprint` compared whole `Posting` values, so once `cleared` was
   added, reconciling on one device made the same transaction read as a sync
   *conflict*. Under `.preferIncoming` that silently overwrote a completed
   reconciliation.
4. **A `Double` round-trip in the capture keypad**, caught in self-review. Money
   arithmetic is exact `Decimal` throughout now.

### Done — app

- `DesignSystem/` — modern premium fintech. Bold tightly-tracked tabular figures;
  explicit hex per appearance rather than system semantic colours; elevation on
  dark from lighter surfaces, not shadows. Two earlier passes were discarded:
  system-native read stock iOS, editorial private-bank read old-world.
- **Capture → review loop.** `QuickEntryView` (two gestures, minor-unit entry,
  usage-ordered categories) writes drafts; `ReviewView` confirms them as a batch.
  The draft/finalized lifecycle stopped being exposed machinery and became the
  product.
- **Budget UI** — limits, bars, month stepping, unbudgeted spending surfaced.
- **IA**: four tabs — Overview, Budget, Activity, Settings. Import moved behind a
  menu and Settings; Reconcile moved into the account it belongs to.
- `AccountDetailView`, `TransactionDetailView`, `AccountReconcileView`.
- **Import rewritten** as a three-step sheet — bank preset, accounts, review — over
  a real `.fileImporter`, replacing the 1,079-line paste-a-CSV screen.
- **Six themes and matching alternate app icons**, onboarding guide, danger zone.
- **Export and restore screens** in Settings.
- Undo for a deleted draft; themed transaction editor; Equity and Clearing behind
  an Advanced disclosure.

### Next

- **A clean LHV export.** The preset's column names are a guess from a sample whose
  columns were shifted by copy-paste; every row was correctly rejected. Swedbank
  and Revolut are verified against real files.
- **Sync.** The merge stack is written and tested and nothing calls it. Missing: a
  transport and conflict UX.
- Inline errors instead of the single global alert — but keep `AppError.swift`,
  whose case-by-case mapping is the best-written part of the app layer.
- Recurring transactions. Charts, last.

### Resolved since

- Snapshots are computed once per render and threaded down, rather than
  recomputed on every reference — Budget was building its full report sixteen
  times per render.
- Writes commit in memory first and are debounced behind that, which closed a
  lost-update window and stopped a reconciliation costing one whole-file rewrite
  per tick.
- Undo exists for the one destructive action reachable from a bare swipe.
- **Review reminders exist.** The open question resolved in favour of building
  them, with the permission ask moved to after the first confirmed review rather
  than onto launch — iOS allows one prompt, and spending it before the app has
  recorded anything spends it on a no. Scheduled one occurrence at a time so the
  count stays honest and an empty queue cancels instead of firing.
- Export and backup exist, and a backup can be restored.

## Dev loop

Core, on any platform including Linux:

```bash
swift test
```

The core is deliberately UI-free, so it builds and tests without Xcode. On Linux a
toolchain drops into `$HOME` with no sudo — all of Debian 12's runtime deps are
usually already present:

```bash
curl -fL -o swift.tar.gz \
  https://download.swift.org/swift-6.2-release/debian12/swift-6.2-RELEASE/swift-6.2-RELEASE-debian12.tar.gz
tar xzf swift.tar.gz
export PATH="$PWD/swift-6.2-RELEASE-debian12/usr/bin:$PATH"
```

App, macOS only: open `Accountant.xcworkspace` (or `AccountantApp/AccountantApp.xcodeproj` — the workspace only wraps that project, so they are equivalent), then `Cmd+R`.

The clone directory **must** be named `accountant-app` — the Xcode project
references the package by relative path (`../../accountant-app`).

The project uses Xcode 16 filesystem-synchronized groups (`objectVersion = 77`), so
new source files are picked up automatically. No `.pbxproj` editing to add files.

## Verification worth keeping

Flows that were impossible before this branch, and should stay working:

1. Two accounts in different currencies; net position never silently converts.
2. Tap an account → detail → its transactions.
3. Tap a transaction → see its postings → delete a draft.
4. Import a CSV with one malformed row; the good rows still import.
5. Reconcile from account detail, ticking until the difference is zero.
6. Dark mode on every screen: no white-on-white strokes.
7. Largest Dynamic Type setting: hero figures scale.
8. Capture spending in two gestures; it lands in review, not straight into history.
9. Confirm a review batch; an invalid entry fails the whole batch rather than
   committing half of it.
10. Set a monthly limit, overspend it, confirm the bar and copy both flip.

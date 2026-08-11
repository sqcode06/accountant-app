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

### Done — core (verified, 181 tests passing)

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

### Done — app (builds unverified beyond AccountDetailView)

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

### Next

- Decompose `ImportPreviewScreen` (1,079 lines, 14 view structs) into a sheet flow
  with a real `.fileImporter`. Pasting CSV into a `TextEditor` is still the only
  way to get a statement in.
- Language pass: Equity/Clearing behind an Advanced disclosure; replace the single
  global alert with inline errors — but keep `AppError.swift`, whose case-by-case
  mapping is the best-written part of the app layer.
- State: cache snapshots instead of recomputing in `body`; coalesce saves (~500ms —
  every mutation currently rewrites the whole JSON file); add undo.
- Optional, unresolved: a daily reminder to review. Deliberately not built — a
  notification permission prompt is a big ask for something the in-app prompts on
  Overview and Activity already do.

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

App, macOS only: open `Accountant.xcworkspace`, `Cmd+R`.

The clone directory **must** be named `accountant-app` — the Xcode project
references the package by relative path (`../../accountant-app`).

The project uses Xcode 16 filesystem-synchronized groups (`objectVersion = 77`), so
new source files are picked up automatically. No `.pbxproj` editing to add files.

## Verification worth keeping

Flows that were impossible before this branch, and should stay working:

1. Two accounts in different currencies; net position never silently converts.
2. Tap an account → detail → its transactions.
3. Tap a transaction → edit → delete a draft. *(still pending — Phase 2)*
4. Import a CSV with one malformed row; the good rows still import.
5. Reconcile from account detail, ticking until the difference is zero.
   *(core done; UI pending — Phase 2)*
6. Dark mode on every screen: no white-on-white strokes.
7. Largest Dynamic Type setting: hero figures scale.

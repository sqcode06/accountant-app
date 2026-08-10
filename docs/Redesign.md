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

### Done — Phase 1, core (verified, 145 tests passing)

- `Account.currency`, `sortOrder`, `symbolName`, `colorToken`.
- `Posting.cleared`, orthogonal to `Transaction.state`:
  - `state` — *have I confirmed this is correct?* (governs editability)
  - `cleared` — *has the bank seen it?* (governs reconciliation)
- `ReconciliationReport.clearedBalance` + `uncleared`; `Ledger.setCleared`, which
  works on finalized transactions because clearing is a statement fact, not an edit.
- `accountBalanceSummaries` rewritten O(A·T) → O(T+P), single pass.
- CSV parsing collects per-row errors instead of aborting the batch.
- Schema v4.

Three real defects fixed, not just design work:

1. **Money vanished.** A posting in the wrong currency was accepted by the ledger,
   then filtered out of every balance query. No error, no trace.
2. **Reconciliation could not reconcile.** Net difference only — no way to find out
   *why* you disagreed with the bank.
3. **Merge fingerprint regression** (introduced and caught within this branch).
   `TransactionFingerprint` compared whole `Posting` values, so once `cleared` was
   added, reconciling on one device made the same transaction read as a sync
   *conflict*. Under `.preferIncoming` that silently overwrote a completed
   reconciliation. The fingerprint now compares only account, currency, amount.

### Done — Phase 1.5, app foundation (builds and runs; not yet reviewed in depth)

- `DesignSystem/` — `Theme`, `Metrics`, `Typography`, `MoneyText`.
- `AccountDetailView` + `AccountDetailSnapshot`. Accounts now navigate here instead
  of opening a rename sheet. Swipe a row to clear it.
- Account editor sets currency for balance-bearing kinds.

### Next

**Phase 2 — information architecture.** Five tabs → three:

| Tab | Contains | Replaces |
|---|---|---|
| Overview | Net position per currency, tappable account list | Summary + Accounts |
| Activity | All transactions, searchable, tappable | Transactions |
| Settings | Display prefs, classification rules, import entry | — |

- Import stops being a tab. It becomes `.fileImporter` plus a sheet flow. The
  paste-CSV `TextEditor` survives only as a debug affordance.
- Reconcile stops being a tab and moves into `AccountDetailView`, where you already
  are when holding a statement. (A placeholder comment marks the spot.)
- New: `TransactionDetailView` — `updateDraftTransaction` and
  `deleteDraftTransaction` exist in the core and are still unreachable from the UI.

**Phase 3 — design system adoption.** Dashboard, transaction list and import still
use the old per-screen gradients and ad-hoc radii.

**Phase 4 — language.** Equity/Clearing behind Advanced. `draft` → "Pending",
`finalized` → "Posted" in UI only. Rewrite developer copy shipped as UI, e.g.
"Raw ledger groups, with income shown as positive for readability". Replace the
single global alert with inline errors — but keep `AppError.swift`, whose
case-by-case mapping is the best-written part of the app layer.

**Phase 5 — state.** Cache the dashboard snapshot instead of recomputing in `body`.
Coalesce saves (~500ms); every mutation currently rewrites the whole JSON file. Add
undo for draft edits and deletes.

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

# App testing

The iOS app sits above `AccountantCore`. The core package already protects the accounting rules, but the app layer still owns important workflow behavior:

- loading a ledger into `AppState`;
- saving financial snapshots through `AppDataRepository`;
- surfacing failed writes without losing the user's change;
- mapping app/domain errors into user-facing messages;
- connecting account and transaction workflows to the core.

This document describes the app-level testing layer. The
[reliability review and testing plan](AppReliabilityPlan.md) records the gaps
found on 2026-09-13, the repair priorities, native CI prerequisites, and the
expected-behavior matrix. The native gate covers the empty-category Budget
regression, capture and confirmation, import rules, restore/erase, account
management, and statement clearing. The
dated sections below record each revision and its verification results;
the reliability plan retains the earlier milestones. Broader workflow
coverage and hardware checks remain in that plan. Documentation-only changes
do not alter tested code; new code changes need their own results.

## Current strategy

The app tests use Swift Testing and XCTest in `AccountantAppTests`.

Most app tests focus on `AppState`. It is the boundary where SwiftUI intent
becomes persisted ledger state, and it can be tested quickly without launching
the app. UI tests cover the smaller set of contracts that require actual taps,
presentation, visible amounts, app lifecycle events, and process relaunch.

## Import rules and statement review

Import rules are global case-insensitive substring matches. They run top to
bottom; a later matching rule wins separately for category and transaction
description. The rule manager supports creation, editing, pausing, reordering,
and trying a sample description without changing a transaction. Rule writes wait
for rule storage, so an unsuccessful create, edit, reorder, pause, or delete
returns failure while leaving the visible state available for retry.

Rule numbers follow the saved order and identify the winner even when several
rules match the same text. The preview keeps that order with its rule snapshot.
An unavailable category stops the whole rule, including description changes;
the manager labels this state as not running even if the enable toggle is on.

The import preview shows the original bank description, the proposed category
and transaction description, and which matching rule supplied each change. Tests also cover the accounting boundaries:
an imported purchase or income can have a separate fee posting, malformed CSV
fee values are rejected exactly, and a legacy split with an ambiguous
counterparty is left unchanged rather than guessed.

The native import journey uses a real five-row Revolut CSV in the Debug-only
isolated fixture. It bypasses only the OS document picker. Both runtimes passed
CSV parsing, category and description previews, purchase recategorization with
its fee preserved, income and refund checks, batch confirmation, and persisted
Activity/search results after relaunch. A separate UI journey passed rule
creation, editing, pausing, try-match, a real drag to reorder, and relaunch.

On iOS 18, SwiftUI's review-menu accessibility wrappers report non-hittable
even when the menu responds to touch. The test checks that the enabled menu's
whole frame is between the navigation and tab bars, then taps its centre when
needed. It requires the category menu to open and the intended purchase to
change category while retaining its separate fee. Screenshots capture the open
menu and corrected review. Physical-device file selection remains a manual check.

## Accounts and reconciliation — 2026-09-14

`AccountDetailSnapshotTests` checks currency filtering, draft visibility,
newest-first entries with chronological running balances, and cleared/pending
amounts. It reproduced a bug where a partly cleared transaction contributed
nothing to the cleared balance. The screen now sums each cleared posting;
the row remains pending until all its postings for this account are cleared.
Zero-net pending entries remain visible without inventing a nonzero balance.

`ReconciliationWorkflowTests` checks clearing and undo for one side of a
transfer, unknown IDs, and real-file failure/retry/relaunch. Clearing one
account leaves the other account's confirmation status alone. These ordinary
edits still debounce saving; the tests explicitly flush before asserting disk
contents and prove a failed flush leaves the previous saved version intact.

`ReconciliationDateTests` reproduced exclusion of a transaction at 23:59:59.5.
The corrected calendar-day cutoff includes the final fractional second and
excludes the next midnight, including on short and long daylight-saving days.
A second reproduction found that adding a day to a 01:00 start could include
an hour of the following day when a clock change skips midnight. The helper
now uses the calendar day interval's actual end; that regression is also covered.

All 92 app-logic checks (87 Swift Testing tests and five XCTest cases) pass in
the portable Linux harness. It substitutes only observation declarations and
does not validate SwiftUI rendering or navigation.

The native account-management journey covers create, rename, archive, restore,
and reopening after the app's real background flush. The reconciliation journey
starts with EUR 100 cleared, an uncleared EUR 25 purchase at 23:59:59.5, a EUR 10
draft, and a EUR 5 purchase at the next midnight. Account activity totals EUR 60;
reconciliation for the selected date excludes the draft and next-day entry. A
EUR 75 statement starts at a EUR -25 difference. Ticking the purchase reaches
zero, and the test reopens the app to verify that cleared state survived. It
then checks an empty checklist with a EUR 5 mismatch, marks the purchase pending
again, and reopens once more to verify the reversal. Amount assertions compare
exact signed values. Short swipes reveal actions before explicit taps, and the
statement field's Done action dismisses the keyboard before continuing.

The screen now labels the cleared figure “On statement” and says “Balance
matches” when the difference is zero. Confirming drafts in Review is a separate
step. An empty checklist or matching totals does not establish that every
individual posting was checked.

The [first native run](https://github.com/sqcode06/accountant-app/actions/runs/34879092558)
at `7c61231` passed both Release builds, the unsigned device archive, all 92 app
tests, and eight of nine UI tests on each runtime. The reconciliation journey
reached clearing and relaunch successfully, then XCTest rejected a lookup using
the full mismatch sentence: string-subscript queries have a 128-character limit.
The screenshot showed the correct EUR 5 mismatch. The test now finds the stable
identifier and compares its complete label, retaining the wording assertion.

A separate Opus review inspected the matched, mismatched, and restored-account
screenshots from both runtimes. The amounts, full copy, and active account state
were correct, with no clipping at the tested size. It raised three remaining
usability checks: “Statement balance” versus “On statement” can sound similar;
positive differences have no explicit plus sign or extra emphasis; and the raw
balance input has no currency symbol beside the formatted totals. These are
recorded in [OwnerReview.md](OwnerReview.md) for the next phone review. The six
screenshots cover portrait iPhone 16, default text size, light appearance, and
English/EUR; they do not establish accessibility or other-layout coverage.

The corrected iOS 18.5 pending-again screenshot also shows the long transaction
description shortened to one line. Identifying the correct entry despite that
truncation is another owner readability check. The screenshot shows the expected
EUR -25 difference and pending row after relaunch.

Revision `9bda415` passed the complete corrected
[native run](https://github.com/sqcode06/accountant-app/actions/runs/34881928860):
both Release builds, all 92 app tests (87 Swift Testing and five XCTest cases),
and all nine UI tests on each of iOS 18.5 and iOS 26.2. That includes the complete
clearing, mismatch, undo, and both relaunch checks. Xcode 26.2 also passed the
unsigned Release device archive and packaged privacy/identity validation. The
same revision passed all 339 core tests on each of Linux and Windows in
[core CI](https://github.com/sqcode06/accountant-app/actions/runs/34881928836).
Later documentation-only changes preserve this tested code.

## Budget saves and reminders — 2026-09-14

Budget set, Stop, and clear, plus Clear all transactions, now await the complete
snapshot save before returning success. A failed write keeps the accepted
change pending. Stop shows a saving state and then a Retry action if needed;
Retry saves the current snapshot without repeating the original Stop.

`BudgetDurabilityTests` reloads real JSON immediately after acknowledged saves.
It covers new and inherited limits, with and without spending, preserves other
categories and earlier history, and injects failures for set/Stop/clear and
transaction clearing. The older-writer barrier test now also waits for the
budget operation's result. The native Budget journey retains its existing
background/liveness assertions, then stops the limit and immediately relaunches.
A second journey injects a failed Stop save, checks the error and Retry button,
retries, and relaunches. The fault repository is Debug-only and confined to the
isolated UI-test directory.

The [first native attempt](https://github.com/sqcode06/accountant-app/actions/runs/34867253543)
at `2de896b` passed both Release builds, the unsigned device archive, and all
81 app tests on each runtime. Four UI journeys passed; all three Budget journeys
failed before Stop because a new row-level accessibility identifier replaced
the amount labels' identifiers. The iOS 26.2 screenshot showed the correct
EUR 20 limit, and its accessibility hierarchy showed the overwritten IDs.
The correction puts identifiers on individual labels and finds the containing
cell for the swipe. It also keeps the Retry button's identifier separate from
the warning text. The amount, failure, and relaunch assertions are preserved;
the corrected run below passed all of them.

`ReviewReminderControllerTests` uses the actual controller with an injected
notification service, clock, and calendar. It checks latest-queue replacement,
empty-queue cancellation, disable winning over an in-flight add or permission
reply, foreground permission changes, visible failures and retry, simultaneous
permission offers, and time/time-zone handling. Controlled barriers establish
the relevant async ordering. The Settings switch shows the persisted choice;
system denial is explained separately, so a blocked reminder can still be
switched off. Confirmation from batch, swipe, and detail routes uses the same
offer/refresh behavior.

Revision `20319eb` passed a fresh
[native run](https://github.com/sqcode06/accountant-app/actions/runs/34869844950):
Release builds, all 81 app tests, and all seven UI tests on each of iOS 18.5 and
iOS 26.2, plus the unsigned Release device archive and privacy/identity metadata
validation on Xcode 26.2. The Stop/Retry and Stop/relaunch screenshots were
inspected. The same revision passed 333 XCTest and six Swift Testing tests on
each of Linux and Windows in
[core CI](https://github.com/sqcode06/accountant-app/actions/runs/34869844949).
Later documentation-only changes preserve this tested code.

All 81 app-logic tests in 11 suites also passed in the portable Linux harness.
That harness substitutes only observation declarations; native evidence for
SwiftUI and UserNotifications comes from the run above. Actual
notification delivery, Files, and the share sheet remain device checks in
[What needs your review](OwnerReview.md). Reminders are one-shot, refreshed as
the app is used; they do not repeat daily indefinitely while it stays unopened.

## Restore and erase stabilization — 2026-09-14

REL-04 now saves a single validated financial snapshot. The local Linux run
passed 64 app tests, including real-file interruption cases and controlled
writer barriers. Code revision `ad7f40e` passed 333 XCTest and six Swift Testing
tests on each of Linux and Windows in
[core CI](https://github.com/sqcode06/accountant-app/actions/runs/34848732975).
That same revision passed a Release build, all 64 app tests, and all six UI
tests on each of iOS 18.5 and iOS 26.2 in
[native CI](https://github.com/sqcode06/accountant-app/actions/runs/34848732888).
The successful final run includes the Budget background/relaunch check that
timed out once during validation, as described below. Later documentation-only
commits preserve this tested code.

Distribution preparation at revision `e777dea` passed a fresh
[native run](https://github.com/sqcode06/accountant-app/actions/runs/34858251856):
Release simulator builds, 64 app tests, and six UI tests on each runtime, plus
an unsigned Release device archive on Xcode 26.2. The archive validator read the
packaged privacy manifest and app identity, confirming app-only UserDefaults
access (`CA92.1`), no tracking or collected data, bundle ID
`dev.sqcode.AccountantApp`, version `1.0`, build `1`, iPhoneOS, and iPhone/iPad
device families. The metadata report and archive log are in that run's
`xcode26.2-ios26.2` diagnostics artifact. The same revision passed all 339 core
tests on each of Linux and Windows in
[core CI](https://github.com/sqcode06/accountant-app/actions/runs/34858252541).
Signed archive validation, upload, and physical-device checks remain separate
steps in [TestFlight preparation](TestFlight.md). Later documentation-only
commits preserve this tested code and packaging.

The new UI journey decodes a backup, checks the replacement counts, confirms
restore, and verifies both a finalized transaction and a draft awaiting review.
After relaunch it checks transactions, accounts, budget limits, and import rules;
it then erases, relaunches again, and verifies all four counts are zero. The
fixture bypasses only the OS document picker. Physical-device file selection
remains a manual check. The erase description and confirmation explicitly say
that existing backups and recovery files remain.

Two native-test findings are preserved:

- iOS 26.2 exposes nested confirmation buttons with the same identifier. The
  test originally failed before tapping Restore. It now selects the unique leaf
  inside the presented sheet and still requires it to be enabled and hittable.
  The corrected restore/erase journey passed on both runtimes at `4a03594`.
- In [the first `4a03594` attempt](https://github.com/sqcode06/accountant-app/actions/runs/34845977914/attempts/1),
  the existing iOS 18.5 Budget test timed out waiting for a background process
  state after Home. The final screenshot showed SpringBoard, and the same
  helper succeeded four later times in that run. No crash diagnostic identifies
  the cause; raw process-state observations were not recorded. This is an
  unresolved intermittent lifecycle-test result, not evidence that the reported
  Stop exit has been fixed. A recurrence needs process-state and simulator
  diagnostics, not a weaker assertion. All 64 app tests and the other five UI
  tests passed; iOS 26.2 passed all 64 app and six UI tests at that revision.

The [storage contract](PersistenceRecovery.md) records migration, post-commit
errors, preserved recovery files, and the limits of fault-injection evidence.

## Test repository

Product code uses `AppDataRepository`. Recovery and snapshot-replacement tests
use isolated real files and controlled repositories, never the app's real
Application Support directory. `ComponentRepositoryFixture` is a test-only
adapter retaining older component mocks for focused unit tests; it is not the
production persistence path. Preview repositories also use the unified API.

**Note the contract here changed.** Writes used to save first and commit to `AppState` afterwards, so a failed save left the visible ledger untouched. That ordering put a suspension point between reading the ledger and writing it back, which meant two quick actions could each save over the other and one change was silently lost.

Mutations now commit synchronously on the main actor. Ordinary edits debounce
the write; budget actions, import rules, and destructive actions await saving
before acknowledging success. A failed write keeps the change visible and
marked dirty so the next flush retries it, and reports the error. Reverting the
change would only hide the fact that nothing was saved.

Two consequences for tests:

- **Anything asserting on what reached the repository must await persistence**, or it is racing a 400ms debounce. `await appState.flushPendingWrites()` joins an active writer and returns whether the complete pending snapshot reached disk. Tests that exercise concurrency use controlled write barriers; a fixed sleep is not a substitute.
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

`DataProtectionTests` additionally uses isolated real JSON files to check retry
and relaunch after damage, all seven combinations of damaged stores, failed
replacement/completion, and preservation of quarantined bytes. Concurrent edits
and a second recovery action are refused while replacement is running. The
healthy restore/erase path is now covered by `SnapshotReplacementTests` and
`AppDataStoreTests`, including interruption before/after the atomic commit and
recovery completion. Whole-state replacements keep the old visible state until
saving succeeds; they do not use the ordinary edit debounce.

## What remains outside the first native gate

Do not use app-state tests for:

- pixel-perfect SwiftUI layout;
- full simulator navigation;
- visual theme validation;
- broad end-to-end UI coverage.

Those belong to focused later UI-test work. The deterministic fixture described
below is now available for adding them without reading or resetting production
data.

## Native test configuration

`AccountantApp.xcodeproj` has a shared `AccountantApp` scheme. Its default
`AccountantApp.xctestplan` includes both `AccountantAppTests` and
`AccountantAppUITests`, with English/US formatting for stable visible assertions.
The local `AccountantCore` package reference is `..` from the project directory,
so a checkout keeps building when its outer folder is renamed. All three native
targets declare the app's iOS 18.0 minimum. CI exercises iPhone 16 with Xcode
16.4 / iOS 18.5 and Xcode 26.2 / iOS 26.2.

The UI launch fixture is available only in Debug builds. It requires
`--accountant-ui-testing`, a per-run `ACCOUNTANT_UI_TEST_RUN_ID`, and optionally
`--accountant-ui-testing-reset` on the first launch. Each ID gets separate ledger,
budget, classification-rule, and UserDefaults storage. Relaunching without reset
reuses those files. The fixture supplies stable EUR `Fixture Bank` and
`Eating out` accounts, fixes the app clock at 2026-09-13, skips onboarding, and
prevents the notification permission prompt. Release builds compile out all
argument parsing, seeding, and reset behavior.

`ACCOUNTANT_UI_TEST_LEDGER_SEED=no-active-expense` selects a second fixture with
bank/savings assets, income, and an archived expense, but no active expense
category. It checks that both Budget add controls offer category creation,
canceling is harmless, and creating Groceries allows a EUR 20 limit. Both Budget
fixtures assert a labelled, enabled, tappable horizontal action and retain an
initial screenshot so an empty-state layout regression is visible in diagnostics.

The first UI workflow creates a EUR 20 September limit through the interface,
captures EUR 0.10, checks EUR 19.90 remaining while the entry is a draft, confirms
it, checks the same amount again, allows the normal debounced write to settle,
exercises a background/foreground transition, terminates the process, relaunches
against the same fixture files, and checks the amounts once more. This establishes
settled persistence; it is not an abrupt-termination durability claim. The test
also verifies that the month title is inert and that tapping the remaining figure
or progress track opens the correct September editor, whose cancellation returns
to the unchanged card. Screenshots are attached at each accounting boundary.

## Running tests

### Budget regressions

`BudgetMonthSelectionTests` covers opening the current month, browsing back and
returning, calendar rollover, and clock corrections. `BudgetWorkflowTests`
covers a recurring EUR 20 limit, a EUR 0.10 draft purchase in September,
confirmation without double counting, and persistence after reload. The core
`BudgetTests` also checks that the allowance repeats while spending stays in the
transaction's month.

On an iPhone or simulator, check the budget controls separately:

1. Set a EUR 20 limit for a category in the current month. Tap the month title,
   remaining amount, and progress bar. None should change the selected month.
2. Use the previous-month arrow to reach a month before the first limit. The
   month header and its navigation must remain visible on the empty screen.
3. Use the next arrow or **Back to this month**. The original limit should
   reappear without creating it again. Each arrow should move exactly one month.
4. Capture EUR 0.10 in that category, dated in the current month. Remaining
   should become EUR 19.90 while it is still a draft and stay EUR 19.90 after
   confirmation. Relaunch and check that both the limit and spending persist.
5. Check that the current-month view follows a month change when the app resumes.
   An intentionally selected historical month should stay selected, with the
   shortcut returning to the new current month. An editor already open during
   the date change should retain the month it was opened for.

These interaction checks need iOS; a passing core suite or syntax-only parse
does not verify SwiftUI hit testing or sheet presentation.

### Commands

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

App tests from Terminal on a Mac with Xcode 16.4 and the iOS 18.5 simulator:

```bash
xcodebuild \
  -project AccountantApp/AccountantApp.xcodeproj \
  -scheme AccountantApp \
  -testPlan AccountantApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  test
```

`.github/workflows/ios.yml` runs a Release app build before the Debug test plan on the pinned
`macos-15` runner for both pinned Xcode/runtime pairs above. The runner
checks the repository out under `renamed-ios-checkout`, so the build also guards
the package reference against assumptions about the checkout folder's name. The
image currently publishes those toolchains and simulators in its
[installed-software manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
The job has read-only repository permissions and always uploads the revision,
toolchain inventory, build/test console logs, `.xcresult`, and exported screenshot
attachments for 14 days. Apple documents that an `xcodebuild` test run's result
bundle contains test results, screenshots, and logs in
[Running tests and interpreting results](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results).

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

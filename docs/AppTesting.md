# App testing

The iOS app sits above `AccountantCore`. The core package already protects the accounting rules, but the app layer still owns important workflow behavior:

- loading a ledger into `AppState`;
- saving successful mutations through `LedgerRepository`;
- surfacing failed writes without losing the user's change;
- mapping app/domain errors into user-facing messages;
- connecting account and transaction workflows to the core.

This document describes the app-level testing layer. The
[reliability review and testing plan](AppReliabilityPlan.md) records the gaps
found on 2026-09-13, the repair priorities, native CI prerequisites, and the
expected-behavior matrix. A native CI gate and the first behavioral UI workflow
are checked in. They still need their first macOS run; Linux cannot validate an
iOS build or simulator interaction.

## Current strategy

The app tests use Swift Testing in `AccountantAppTests`.

Most app tests focus on `AppState`. It is the boundary where SwiftUI intent
becomes persisted ledger state, and it can be tested quickly without launching
the app. UI tests cover the smaller set of contracts that require actual taps,
presentation, visible amounts, app lifecycle events, and process relaunch.

## Test repository

App tests use an in-memory `LedgerRepository`.

This gives each test a clean ledger and avoids the real Application Support JSON file used by the app at runtime.

The in-memory repository can also inject load/save failures.

**Note the contract here changed.** Writes used to save first and commit to `AppState` afterwards, so a failed save left the visible ledger untouched. That ordering put a suspension point between reading the ledger and writing it back, which meant two quick actions could each save over the other and one change was silently lost.

Mutations now commit synchronously on the main actor and the write is debounced behind them. A failed write keeps the change visible, keeps it marked dirty so the next flush retries it, and reports the error. Reverting the change would not have saved the data either — it would only have hidden that nothing was saved, and invited the user to repeat the action into the same failure.

Two consequences for tests:

- **Anything asserting on what reached the repository must await persistence**, or it is racing a 400ms debounce. `await appState.flushPendingWrites()` joins an active writer and returns whether every pending store reached disk. Tests that exercise concurrency use controlled write barriers; a fixed sleep is not a substitute.
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
previously healthy three-file restore/erase transaction remains a separate open
repair; these tests do not establish atomic replacement for that path.

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
targets declare the app's iOS 18.0 minimum; CI currently exercises them on the
hosted iOS 18.5 runtime because that is the compatible runtime pinned with Xcode
16.4.

The UI launch fixture is available only in Debug builds. It requires
`--accountant-ui-testing`, a per-run `ACCOUNTANT_UI_TEST_RUN_ID`, and optionally
`--accountant-ui-testing-reset` on the first launch. Each ID gets separate ledger,
budget, classification-rule, and UserDefaults storage. Relaunching without reset
reuses those files. The fixture supplies stable EUR `Fixture Bank` and
`Eating out` accounts, fixes the app clock at 2026-09-13, skips onboarding, and
prevents the notification permission prompt. Release builds compile out all
argument parsing, seeding, and reset behavior.

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
`macos-15` runner, Xcode 16.4, iOS 18.5, and iPhone 16 combination. The runner
checks the repository out under `renamed-ios-checkout`, so the build also guards
the package reference against assumptions about the checkout folder's name. The
image currently publishes that exact toolchain and simulator combination in its
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

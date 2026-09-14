# Reliability review and testing plan

Review date: 2026-09-13. Baseline: `7037459e6337a146332cde280f31d1d3ccfbccd2`,
with the local budget changes considered separately. Three independent Sol
reviews at extra-high effort covered budget interactions, persistence, and test
coverage. An Astra review at extra-high effort challenged their findings and
independently reproduced the principal persistence failures.

**Status: the Budget, import-rule, and restore/erase workflows passed native CI
on iOS 18.5 and iOS 26.2; further stabilization remains open.** The disabled, stretched
empty-budget action has a regression test on both runtimes. The user can no
longer reproduce the reported Stop exit after the month fixes; its cause and
any connection to those fixes remain unconfirmed. REL-04 now has passing interruption and native relaunch
tests; one intermittent Budget background-state test timeout remains recorded.

For the short work order, use the [roadmap](Roadmap.md). This file retains the
technical evidence and historical findings.

## Implementation update — 2026-09-14

- REL-01: ledger/backup validation now rejects duplicate IDs and invalid
  accounting contents through errors. Valid archived history and supported
  older ledgers remain readable. Regression tests are in
  `DecodedFinancialDataValidationTests`.
- REL-02: concurrent flush callers join the active writer, wait for dirty
  changes to drain, and receive an explicit success/failure result. Tests use
  controlled write barriers and exercise failure followed by retry.
- REL-03/05: unresolved quarantine records persist across retry, relaunch, and
  movement of the data directory. Ordinary saves cannot overwrite protected
  originals. Start fresh clears ledger, budget, and rules; recovery remains
  locked until the complete financial snapshot is saved and recovery completion succeeds.
  `DataProtectionTests` exercises all seven nonempty damaged-store combinations,
  replacement/completion failures, concurrent recovery actions, and invalid
  restore input using isolated real files and controlled repositories.
- REL-07/08: a shared scheme, test plan, debug-only isolated launch fixture,
  behavioral budget UI test, and [macOS workflow](../.github/workflows/ios.yml)
  have been added. The stale load fixture and debounced-save assertion are
  corrected. Code revision `d87a44d` passed a Release build, 58 app tests, and
  five UI tests on each runtime in
  [native CI](https://github.com/sqcode06/accountant-app/actions/runs/34794280441).
- Import-rule stabilization: rules can be edited, paused, reordered, and tried
  against sample statement text. Matching is a global case-insensitive substring
  check in saved order, with the later match winning each field it changes. Rule
  writes wait for rule storage and retain unsuccessful changes for retry. The
  preview shows the original bank description, the proposed category and memo,
  and which matching rule supplied each change. Imported purchases and income
  retain separate fee postings; malformed CSV fee values are rejected, and
  ambiguous legacy splits are left unchanged. Both runtimes passed the real
  CSV import, review correction, confirmation, and relaunch journey, plus rule
  editing, pausing, try-match, drag reordering, and persisted order. The OS
  document picker is the only bypass in that fixture and still needs a device
  check. [AppTesting.md](AppTesting.md) records the exact coverage and the
  iOS 18 menu interaction used by the test.

The subsequent iOS 26.2 empty-budget report exposed two coverage gaps: the
fixture always included an active expense category, and the only native runtime
was iOS 18.5. Both Budget add controls were disabled when that category list was
empty, with no explanation or way forward on the screen. The repair offers
category creation from both entry points and uses an explicitly sized, labelled
button instead of a full-screen unavailable-view action inside a List row.
BUD-08 covers the missing state; CI now includes iOS 26.2 as well as iOS 18.5.
These scenarios passed on both runtimes at code revision `d87a44d`.

The same code revision passed 324 core tests on Linux and Windows in
[core CI](https://github.com/sqcode06/accountant-app/actions/runs/34794280417).
A temporary Linux package also passed all 58 app-logic tests, substituting only
observation declarations. SwiftUI/UIKit and lifecycle evidence comes from the
native run above. Later documentation-only changes preserve the tested code;
subsequent code changes require fresh native results.

REL-04 implementation now uses one schema-5 financial snapshot at the existing
ledger path. Legacy versions 1–4 and their companions are validated together;
the first save performs an atomic migration. Restore/erase serialize with older
writers and cannot leave a silently editable mixture. The original failing
regression and checkpoint/barrier tests pass. Final code revision `ad7f40e`
passed 339 core tests on each of Linux and Windows in
[core CI](https://github.com/sqcode06/accountant-app/actions/runs/34848732975),
and a Release build, 64 app tests, and six UI tests on each of iOS 18.5 and
iOS 26.2 in
[native CI](https://github.com/sqcode06/accountant-app/actions/runs/34848732888).
The new UI journey restores, relaunches, erases, and relaunches again, checking
transactions, accounts, budgets, and rules. See
[PersistenceRecovery.md](PersistenceRecovery.md) for the interruption, migration,
recovery-file retention, and downgrade contracts.

During verification, an existing iOS 18.5 Budget test timed out once while
waiting for a background process state after Home. The final run passed that
unchanged Budget check, but the timeout's cause remains unconfirmed.
[AppTesting.md](AppTesting.md) preserves the failed attempt and observed evidence.
A recurrence needs raw process-state and simulator diagnostics; it must not be
hidden by accepting an unknown or terminated state.

Budget set/Stop/clear and Clear all transactions now return success only after
the full financial snapshot saves. Failed Stop saves remain visible and offer
Retry without reapplying the action. Real-file tests cover immediate reload and
failure/retry; the native Budget journey now includes Stop/relaunch, and a new
journey injects a failed Stop save and uses Retry. Existing background/liveness
assertions remain. Native verification of these latest changes is pending.

Reminder tests now exercise permission changes, late async responses, overlapping
scheduling and cancellation, time/time-zone changes, and confirmation routes.
The Settings switch represents the user's choice even if iOS blocks delivery.
Actual notification delivery still needs a device check. These are one-shot
reminders, not recurring daily notifications while the app stays unopened.

The previously reported exit is no
longer reproducible by the user, so it is retained as an unresolved historical
report rather than a confirmed current crash. The lifecycle-test timeout above
is a separate observation.
Completing REL-04 alone does not establish release readiness.

## Why the existing tests did not catch these problems

[Core CI](../.github/workflows/ci.yml) runs `swift test` on Linux and Windows.
[Package.swift](../Package.swift) includes only `AccountantCore`; these jobs
neither build the iOS app nor execute its app and UI tests. At the reviewed
baseline, UI and launch tests only launched, measured performance, or captured
screenshots, with no workflow assertions or checked-in shared scheme/test plan.
The new iOS workflow and behavioral test address that missing setup; their
native execution is a separate verification step.

The accounting tests protect useful rules, but do not establish that the
buttons, sheets, app state, lifecycle, and repositories work together. These
are missing verification layers, not a reason to discard the core tests.

Evidence obtained during the original review (before implementation):

- The Linux core suite passed 282 XCTest tests and 3 Swift Testing tests.
- Five calendar-selection tests passed in a temporary Swift package using the
  unchanged production helper and test files. This did not build the app.
- The changed budget files passed syntax parsing. Parsing does not type-check
  SwiftUI or verify interactions.
- At that point, `BudgetWorkflowTests` had not run in the native app test target.
- AppState reproductions below used unchanged production sources, real or
  controlled repositories, and minimal Linux observation shims. They test state
  and persistence logic, not SwiftUI, UIKit, or iOS lifecycle behavior.
- No simulator or physical-device tests have run in this environment.

## Reported incidents and their status

The reports came from an existing installed build, not a rebuild of the local
patch. Its exact revision is unknown. The user has no Mac access now but can
clone the repository and use Xcode later.

| Observation | What remains to establish |
| --- | --- |
| A newly created budget immediately displayed August although it was September. | Reproduce initial selection on a clean September launch as well as a view retained across August/September. The retained-view explanation does not establish what happened on this device. |
| Tapping the summary card removed it completely; repeating after recreation was inconsistent. | Reproduce the exact tap targets and state transition natively. The user did not report seeing the month switch on tap. |
| A EUR 0.10 September expense did not change the displayed EUR 20 budget, either as draft or confirmed. | Check both selected month and live report updates through capture and confirmation. |
| Stop caused the app to exit; budget state was visible after reopening. | As of 2026-09-14 the user cannot reproduce it after the month fixes. Keep Stop/relaunch coverage; capture diagnostics if it returns. No crash log identifies a cause or proves a connection to those fixes. |

Do not equate a disappearing view, an unsaved change, and a process crash.
Record build revision, version/build number, OS/runtime, locale, timezone,
fixture ID, screenshots, console/crash logs, and `.xcresult` for native failures.

## Findings at the reviewed baseline and repair contracts

P0 findings block a reliability release. P1 findings need resolution or an
explicitly recorded disposition before release. Priorities describe impact;
they do not claim a connection to the reported Stop exit.

| ID / priority | Evidence | Required repair and regression |
| --- | --- | --- |
| REL-01 / P0 | Decoding duplicate account IDs traps in `Dictionary(uniqueKeysWithValues:)` in [Ledger.swift](../Sources/AccountantCore/Ledger.swift), bypassing normal decoding error handling. Independent reproduction exited with SIGILL and a duplicate-key fatal error. | Reject duplicates with a decoding error. A damaged ledger must enter recovery; a malformed backup must be rejected without changing live state. Audit other decoded IDs/references and specify their validity rules. |
| REL-02 / P0 | A second call to `flushPendingWrites()` returns immediately while another flush is active in [AppState.swift](../AccountantApp/AccountantApp/App/AppState.swift). A gated-save reproduction returned `eraseReturned=true completedSaves=0`, contrary to the documented awaited-completion contract. | Track persistence generations and let every caller await its requested generation, using a shared writer and waiters or an equivalent design. Return failures explicitly. Test concurrent flush, restore, erase, import, and prune during blocked or failing writes. |
| REL-03 / P0 | After a corrupt ledger is moved to quarantine, retry sees a missing original and loads an unlocked empty ledger. A new AppState does the same after relaunch. Existing budget references remain. Real-file reproduction: `locked=true` then `locked=false accounts=0`; quarantine bytes remain intact. | Persist unresolved recovery state across retry and relaunch. Moving a damaged file must not implicitly authorize a fresh empty store. Explicit restore/start-fresh must resolve the state consistently; retain recoverable originals. See [LedgerStore.swift](../Sources/AccountantCore/Persistence/LedgerStore.swift), [JSONFileStore.swift](../Sources/AccountantCore/Persistence/JSONFileStore.swift), and AppState loading/recovery. |
| REL-04 / P0 | Restore changes all in-memory data then writes ledger, budget, and rules separately. Injecting only a budget-save failure reproduced `restore=false newLedger=true oldBudget=true locked=false` on reload. | Specify and implement a recoverable multi-store commit, such as staged generations plus a commit marker. A failed/interrupted restore or erase must reload a complete old state, a complete new state, or a protected recovery state; never silently permit editing an inconsistent mixture. Test every write/commit checkpoint. |
| REL-05 / P1 | `startFreshAfterDamage()` only marks the ledger for saving. Undamaged budgets/rules can survive while the ledger is empty, contrary to the recovery screen's start-fresh description. | Make the action's scope explicit and keep all participating stores consistent. Test each damaged-store combination, failed reset, retry, and relaunch. Implement with REL-03/04. |
| REL-06 / P1 | At baseline HEAD, an empty budget report replaces the whole List, including its navigation. The month is also initialized from the date once, without refresh. | Keep navigation accessible on empty months and refresh current-month selection on relevant calendar/lifecycle changes. Preserve deliberate history browsing and an editor's effective month. The local patch addresses these properties but still needs native validation. |
| REL-07 / P0 gate | Native tests are absent from CI, UI assertions are absent, and the app hardwires normal storage at launch in [AccountantAppApp.swift](../AccountantApp/AccountantApp/AccountantAppApp.swift), with time/defaults accessed directly elsewhere. | Add a clean-checkout native gate, isolated deterministic launch fixtures, and actual workflow assertions. Missing shared schemes makes test discovery unauditable; it does not prove Xcode cannot generate a usable scheme. |
| REL-08 / P1 gate | The load-failure app test expects an error while its mock's default `load()` maps errors to `.empty`. The rule-save test asserts immediately despite debounced persistence. | Repair the fixture to express the intended `.unreadable` recovery outcome; synchronize persistence assertions with a corrected flush contract. Do not weaken expectations or skip tests to obtain green results. See [AccountantAppTests.swift](../AccountantApp/AccountantAppTests/AccountantAppTests.swift), [LedgerRepository.swift](../AccountantApp/AccountantApp/Persistence/LedgerRepository.swift), and [ClassificationRuleStorageTests.swift](../AccountantApp/AccountantAppTests/ClassificationRuleStorageTests.swift). |

These defects were reproduced against the reviewed source, not against the
unknown installed build. REL-01 is a demonstrated crash path but has no known
connection to Stop.

Two interaction hypotheses remain unconfirmed: automatic button behavior inside
a List row and overlapping picker/editor sheet transitions. Native tap and
repeated-presentation tests must establish their effects before claiming either
as the reported cause.

At the reviewed baseline, Stop changed memory and scheduled a write after a 400 ms debounce.
A real-file experiment stopped a target and immediately exited; a new process
loaded the old target. That establishes a persistence window, not a crash.
The product must distinguish an accepted change from durable completion.
For Stop and destructive actions, the repair contract is that successful
completion is acknowledged only after saving, with a visible retryable failure
otherwise. Ordinary edits may remain responsive and debounced, provided their
pending/failure state and eventual completion are tested. Native background
flush completion also needs separate validation.

## Implementation order and completion criteria

### 1. First milestone: native baseline and persistence protection

Use two bounded tracks that can be reviewed independently:

- **Native gate:** check in an `AccountantApp` shared scheme and test plan that
  include both app and UI test targets; add a macOS CI job; provide an isolated
  fixed-date launch fixture; replace one launch-only test with a meaningful
  budget workflow. Run all existing app tests and correct REL-08's fixtures and
  synchronization while preserving their intended contracts.
- **Persistence protection:** turn the REL-01/02/03 reproductions into checked-in
  failing regression tests, implement the repairs, and record passing results.
  A core decode test alone does not replace the app recovery test. A mock save
  test does not replace a real-file relaunch test.

The first native workflow starts on 2026-09-13 with isolated EUR data, creates
a EUR 20 limit, captures EUR 0.10, and confirms it. It asserts September,
EUR 0.10 spent, and EUR 19.90 remaining before and after confirmation. Tapping
the summary must preserve the target. Add Stop/relaunch assertions as soon as
the durability contract is implemented.

Exit: the app builds from a clean checkout; both native test targets execute;
the first UI workflow asserts visible outcomes; REL-01/02/03 regressions pass;
failures retain diagnostic artifacts. REL-04 remains explicitly release-blocking
until the next milestone; completing this milestone is not release approval.

### 2. Recoverable persistence and all reported budget workflows

- Implement REL-04/05 with a documented interruption model. Inject failure or
  process termination before each store write, between writes, before the commit
  marker, and after acknowledged completion. Relaunch from the resulting files
  and assert a consistent old/new state or a protected, actionable recovery
  state. This contract concerns application/process interruption; do not infer
  universal hardware power-loss guarantees from these tests.
- Use controlled repositories with barriers for blocked writes and injected
  errors. Do not synchronize by sleeping longer than the debounce interval.
- Implement and execute BUD-01 through BUD-07 below. Require failing-before and
  passing-after evidence for every reproducible fix. Keep unknown-build incidents
  unresolved if the evidence does not connect them to a repair; continue the
  other work rather than waiting indefinitely for an unavailable crash log.

### 3. Expand workflow coverage and enforce release gates

Implement the behavior matrix below. Every new defect adds a regression at the
lowest layer that can prove it, plus a UI assertion when the defect concerns
interaction. Existing correct calculations do not need every permutation
duplicated in UI automation.

For each pull request, require core tests, a native build, app integration tests,
and a short UI suite for launch, budget, capture/confirm, recovery, and relaunch.
Run the broader matrix and fault sequences on a schedule and before release.
Do not hide flaky failures with blind retries; preserve the first failure and
make synchronization deterministic.

Release requires successful native evidence for the exact candidate revision,
no unresolved P0 finding, and recorded handling of remaining issues. Repeat the
reported device flows on hardware when available. Describe any unresolved Stop
exit honestly; simulator success alone does not identify its cause.

## Deterministic test harness

- Opt-in test launches select a named fixture, isolated storage directory and
  UserDefaults suite, fixed clock, calendar, timezone, and locale. Normal launches
  continue to use normal dependencies. Test setup must never erase live data.
- Each test owns a unique namespace. Relaunch tests deliberately reuse that
  namespace without reseeding; reset only at an explicit test boundary.
- Seed stable IDs, accounts, currencies, targets, drafts, and finalized entries.
  Include empty launch, a previous-version data set, unreadable files, and
  invalid backups. Assert round-trip data and references, not just screen text.
- Expose stable accessibility identifiers for controls and observable states.
  Use explicit predicates for load/save/sheet completion and process liveness.
  Retain screenshots as evidence alongside assertions.
- Provide controlled load/save failures and notification responses through
  dependencies. Keep these controls in test/debug configurations and out of
  ordinary product flows.
- Include a diagnostics build identifier so later device reports can be tied
  to a commit. Record the actual selected toolchain/runtime in every CI run.

## Budget incident regression cases

| ID | Setup and action | Required result and layer |
| --- | --- | --- |
| BUD-01 | Fixed local date 2026-09-13; empty budget; open Budget and create an Eating out limit of EUR 20. | Initial and saved month are September; one recurring target starts then. App + UI. |
| BUD-02 | After first creation and after reopening an existing target, separately tap month text, remaining figure, blank summary space, and progress track. Repeat category picker/editor presentation. | Summary taps preserve the card and target; only explicit month controls change the period; each editor presents once and edits its intended category. UI. |
| BUD-03 | Browse to a month before any targets/spending, then return. | Empty-month navigation remains available; returning restores the original target unchanged. UI + selection unit tests. |
| BUD-04 | EUR 20 recurring target from August; capture EUR 0.10 on September 13 in that category; confirm it. | September shows EUR 0.10 spent and EUR 19.90 remaining both as draft and after confirmation. August is unchanged; October starts with a fresh EUR 20 allowance. Core + app + UI. |
| BUD-05 | Stop the only target and one of several targets; repeat for a new and an inherited target, with and without spending. | App stays running; the target stops from the selected month onward; earlier history and other categories survive. Spending history may still appear after its target stops. Navigation remains available when the report is empty. Core + app + UI. |
| BUD-06 | Relaunch after acknowledged Stop completion; inject save failure and interruption at documented checkpoints. | A completed Stop survives relaunch. Pending/failed saves are distinguishable and retryable; reloaded state satisfies the persistence contract. App real-file tests + UI relaunch. |
| BUD-07 | Cross month/year boundaries, foregrounding, timezone changes, and clock corrections; repeat while viewing history and editing. | Current selection follows the calendar; deliberate history browsing stays explicit; an open editor retains its intended month; money stays in the transaction's defined month. Unit + app + targeted native tests. |
| BUD-08 | Open Budget without active expense categories; include assets, income, and an archived expense. Use and cancel toolbar creation, then create a category and limit from the central action. Repeat with an active expense and no limit. | Both actions remain enabled and reach the correct next step; the central button shows its title with a usable horizontal layout; the new limit appears. UI on iOS 18.5 and 26.2, with screenshots. |

## Expected-behavior matrix

Gate **PR** means a required pull-request check. **Broad** means scheduled and
pre-release execution. **Device** means a recorded hardware check. P0 cases
block release; P1 is the remaining essential workflow coverage. This is the
target coverage; the implementation update above records completed evidence.
The remaining scenarios still need fixtures and execution.

| Area / priority | Fixture and expected behavior | Layers and gate |
| --- | --- | --- |
| Launch, upgrade, recovery / P0 | Empty install, existing prior-version files, each corrupt/missing store combination. Load intentionally; preserve supported old data; quarantine errors; keep recovery protected across retry/relaunch; start-fresh/restore obey their scope. | App real-file + launch UI: PR; combinations: Broad. |
| Persistence and destructive settings / P0 | Blocked writer, failed ledger/budget/rules writes, concurrent callers, interruption checkpoints. Awaited completion is durable; erase/clear labels match scope; partial operations enter recoverable state. | Core/app fault tests: PR; process interruption + UI errors/relaunch: Broad. |
| Budget / P0 | Fixed September fixture and BUD-01–07, plus multiple categories/currencies. Recurrence, history, draft spending, edits, navigation, and Stop agree. | Core/app + short create/capture/confirm/Stop UI: PR; boundary/interaction variants: Broad. |
| Overview / P1 | Known balances, finalized and draft transactions, archived accounts, two currencies. Balances/net worth use the documented scope; refresh after mutations; no unconverted cross-currency addition. | Core/app: PR; summary navigation/update UI: Broad. |
| Capture / P0 | Expense, income, transfer; decimal and locale inputs; both Save and Save-and-confirm; invalid/empty input and repeated taps. Create exactly one correctly dated transaction with correct accounts, amount, status, and validation. | Core/app + expense smoke UI: PR; all entry modes/keyboard variants: Broad. |
| Review and Activity / P1 | Mixed drafts/finalized entries and searchable memos. Review recategorization/confirmation counts once; delete/undo and filters affect their intended transaction/scope; persisted changes survive relaunch. | Core/app: PR; review/search/delete/undo UI: Broad. |
| Accounts and categories / P1 | New, duplicate/invalid, archived, and referenced accounts. Create/rename/archive/restore persist; validation is visible; budgets and transaction references remain valid. | App: PR; management UI: Broad. |
| Import and classification / P0 | Valid, dirty, duplicate, locale-specific CSV; exact fee validation; purchase/income fees; safe rejection of ambiguous legacy splits; rule create/edit/pause/reorder/try and save failure. Preview/cancel do not mutate; preview identifies the bank description, proposed category and memo, and matching reason; later case-insensitive substring matches win per field; rules and ordering survive relaunch. The Debug fixture may bypass only the OS document picker, not CSV parsing, preview, review, saving, or relaunch. | Core/app and native CSV/rule journeys: PR, passed on iOS 18.5 and 26.2. OS document picker: Device. |
| Reconciliation / P1 | Known statement, multiple accounts/currencies, draft/finalized/cleared entries, as-of boundaries. Correct scope and difference; clearing persists; unrelated data is preserved. | Core/app: PR; reconciliation UI: Broad. |
| Export and backup restore / P0 | Full three-store backup, previous supported format, duplicate IDs, unsupported/corrupt backup, failed write. Export round-trips supported data; cancel/rejection is inert; restore is consistent after failure/relaunch. | Core/app real-file: PR; file-picker/share/restore UI: Broad + Device. |
| Onboarding and settings / P1 | Fresh and already configured data. Setup is idempotent and optional where designed; currency/settings persist; revisiting setup preserves existing data. | App: PR; onboarding/settings UI: Broad. |
| Themes and app icons / P1 | Each supported theme/icon, live draft/editor, changed tab. Settings persist without resetting navigation or losing work; supported icon changes and errors are handled. | App/UI: Broad; icon/system behavior: Device. |
| Reminders / P1 | Permission granted/denied, zero/several pending drafts, changed schedule, relaunch. Requests, counts, cancellation, and rescheduling agree with settings. | App fake notification service: PR; OS delivery/permission checks: Device. |
| Accessibility and layout / P1 | Large Dynamic Type, VoiceOver, supported orientations, light/dark themes, keyboard open, representative locales. Essential actions remain reachable with distinct names and usable targets; money/date text remains interpretable. | Focused UI: Broad; VoiceOver and device layout: Device. |

Two behaviors need an explicit product contract before tests imply they exist:
full transaction editing (the current detail view offers confirm/delete), and
notification taps routing directly to Review. These are potential enhancements,
not established regressions. Existing review recategorization and reminder
scheduling now have regression coverage; OS notification delivery remains a
device check.

Each relevant workflow needs success, validation failure, save failure, repeated
action, and relaunch coverage. Add date and currency boundaries where they can
change results. A coverage percentage or finite matrix does not establish that
every possible state is correct; release decisions use demonstrated behaviors
and unresolved defects.

## Running native tests without an owned Mac, and later in Xcode

GitHub provides hosted macOS runners, so native CI does not require the user's
own Mac. The checked-in workflow runs Xcode 16.4/iOS 18.5 and Xcode 26.2/iOS 26.2;
the implementation update above records completed runs. The initial setup
checklist below is retained for reference. Keep the selected Xcode/runtime pairs
explicit when changing the gate. [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners),
[macOS image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).

Clean-checkout prerequisites for milestone 1:

1. Check in the shared `AccountantApp` scheme and `AccountantApp` test plan,
   including both native test targets and the isolated launch harness.
2. Fix the local package reference in
   [project.pbxproj](../AccountantApp/AccountantApp.xcodeproj/project.pbxproj).
   `../../accountant-app` depends on the clone directory's name; `..` refers
   portably to the package root relative to the project directory. Verify with
   a renamed checkout.
3. Select a simulator meeting the current **test targets' iOS 18.5 minimum**.
   The app minimum is 18.0; do not assume that is sufficient for these tests.
   Reconcile this gap when qualifying the oldest supported OS instead of
   silently treating 18.5 as the product's minimum. Xcode 16.4/iOS 18.5 is a
   candidate initial pair if available; record the pair actually qualified.
4. Log `xcodebuild -version`, `swift --version`, and available simulator runtimes.
   Select the simulator by its UDID. Always upload test results, failure
   screenshots, and available simulator crash logs, including on failed runs.

After these prerequisites, run from the repository root with
`ACCOUNTANT_SIMULATOR_UDID` set to the selected simulator:

```bash
ACCOUNTANT_TEST_RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/accountant-tests.XXXXXX")"
xcodebuild test \
  -project AccountantApp/AccountantApp.xcodeproj \
  -scheme AccountantApp \
  -testPlan AccountantApp \
  -destination "platform=iOS Simulator,id=$ACCOUNTANT_SIMULATOR_UDID" \
  -derivedDataPath "$ACCOUNTANT_TEST_RUN_DIR/DerivedData" \
  -resultBundlePath "$ACCOUNTANT_TEST_RUN_DIR/AccountantTests.xcresult" \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO
```

Use a fresh result-bundle path on each run. Preserve it as an artifact rather
than deleting the failure evidence. Apple describes test execution and result
analysis in its [Xcode testing documentation](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results).

Later in Xcode, after the relevant changes are committed and available in the
clone: open `Accountant.xcworkspace` (or the project above), choose the shared
scheme/test plan and qualified iPhone simulator, and use **Product > Test**.
Run the named budget cases with fixture data before trying them on a device.
Local uncommitted changes are not included in a remote clone.

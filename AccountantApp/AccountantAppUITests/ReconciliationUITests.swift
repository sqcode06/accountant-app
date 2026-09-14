import XCTest

/// Exercises `AccountReconcileView` against a fixture with known totals: a
/// cleared income, an uncleared expense sitting in the final fractional second
/// of the selected day, a draft, and a finalized entry dated exactly the next
/// midnight. See `AppUITestFixture.seedReconciliationTransactions`.
final class ReconciliationUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        runID = UUID().uuidString
        app = XCUIApplication()
        configureLaunch(reset: true)
        app.launch()

        addTeardownBlock { [weak self] in
            guard let self, let app = self.app else { return }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Final reconciliation state"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    func testKnownTotalsCutoffConfirmReverseAndRelaunch() {
        openBankAccount()

        // The account's own activity and balance count the draft and the
        // next-midnight entry that reconciliation is about to exclude.
        assertMoney(identifier: "account.detail.balance", exactly: "60.00")
        assertMoney(identifier: "account.detail.clearedBalance", exactly: "100.00")
        assertMoney(identifier: "account.detail.pendingBalance", exactly: "-40.00")
        assertActivityCellExists(containing: "Reconciliation coffee draft",
                                  message: "Draft entry missing from account activity")
        assertActivityCellExists(containing: "Reconciliation next-day fee",
                                  message: "Next-midnight entry missing from account activity")
        attachScreenshot(named: "Account detail with draft and next-midnight activity")

        openReconcile()
        setStatement("75")

        // Only the one genuinely uncleared, in-cutoff, finalized entry shows up —
        // dated the final fractional second of the day, which only
        // `ReconciliationDate.endOfDay` (not the old "+1 day, -1 whole second"
        // helper) counts as in-cutoff. The draft and the entry dated exactly the
        // next midnight are excluded, not merely hidden.
        assertMoney(identifier: "reconcile.confirmed", exactly: "100.00")
        assertMoney(identifier: "reconcile.difference", exactly: "-25.00")
        XCTAssertFalse(anyElement("reconcile.reconciledBadge").exists,
                       "Reconciled badge shown before the difference reached zero")
        let unclearedRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reconcile.uncleared.")
        )
        let unclearedRow = unclearedRows.firstMatch
        XCTAssertTrue(unclearedRow.waitForExistence(timeout: 5), "No uncleared entry appeared after entering the statement")
        XCTAssertEqual(unclearedRows.count, 1, "Expected exactly the pending groceries entry to need confirming")
        XCTAssertTrue(unclearedRow.label.contains("25.00"), "Uncleared row did not show the pending amount")
        attachScreenshot(named: "Statement entered with one entry left to confirm")

        tap(unclearedRow, description: "Confirm pending groceries entry")

        XCTAssertTrue(unclearedRow.waitForNonExistence(timeout: 5), "Confirmed entry remained in the uncleared list")
        assertMoney(identifier: "reconcile.confirmed", exactly: "75.00")
        assertMoney(identifier: "reconcile.difference", exactly: "0.00")
        XCTAssertTrue(anyElement("reconcile.reconciledBadge").waitForExistence(timeout: 5),
                      "Reconciled badge did not appear once the difference reached zero")
        XCTAssertTrue(
            app.staticTexts["Your statement balance matches the total you have ticked off."].waitForExistence(timeout: 5),
            "Matched empty state did not replace the uncleared list"
        )
        attachScreenshot(named: "Difference reached zero")

        // Persist and relaunch right here, before any reversal, so this proves
        // the *cleared* change survived — reopening after only the later,
        // reversed relaunch would land back on the original pending fixture and
        // prove nothing about this state.
        persistAndRelaunch()
        openBankAccount()
        openReconcile()
        setStatement("75")
        assertMoney(identifier: "reconcile.confirmed", exactly: "75.00")
        assertMoney(identifier: "reconcile.difference", exactly: "0.00")
        XCTAssertTrue(anyElement("reconcile.reconciledBadge").waitForExistence(timeout: 5),
                      "Reconciled badge did not survive a background flush and relaunch")
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reconcile.uncleared.")).count,
            0,
            "A cleared entry reappeared as uncleared after relaunch"
        )
        attachScreenshot(named: "Cleared state survived relaunch")

        // A statement that no longer matches, with nothing left to tick, must
        // say so rather than imply everything was checked.
        setStatement("80")
        XCTAssertTrue(anyElement("reconcile.uncheckedMismatch").waitForExistence(timeout: 5),
                      "Empty-mismatch copy did not appear for a mismatched statement with nothing left to tick")
        XCTAssertTrue(
            app.staticTexts[
                "No entries with an outstanding amount are listed for this date. "
                + "Check the statement balance and date, and look for missing or incorrect entries."
            ].waitForExistence(timeout: 5),
            "Unexpected empty-mismatch wording"
        )
        XCTAssertFalse(anyElement("reconcile.reconciledBadge").exists, "Reconciled badge shown despite a €5 mismatch")
        assertMoney(identifier: "reconcile.difference", exactly: "5.00")
        attachScreenshot(named: "Mismatch with nothing left to tick")

        setStatement("75")
        XCTAssertTrue(
            app.staticTexts["Your statement balance matches the total you have ticked off."].waitForExistence(timeout: 5),
            "Matched empty state did not return after restoring the statement amount"
        )

        backToAccountDetail()
        markGroceriesEntryPending()

        openReconcile()
        setStatement("75")
        let reopenedRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reconcile.uncleared.")
        )
        XCTAssertTrue(reopenedRows.firstMatch.waitForExistence(timeout: 5), "Reversed entry did not return to the uncleared list")
        XCTAssertEqual(reopenedRows.count, 1, "Reversed entry did not return to the uncleared list")
        assertMoney(identifier: "reconcile.difference", exactly: "-25.00")
        attachScreenshot(named: "Marked pending again before relaunch")

        persistAndRelaunch()

        openBankAccount()
        openReconcile()
        setStatement("75")
        let survivingRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "reconcile.uncleared.")
        )
        XCTAssertTrue(survivingRows.firstMatch.waitForExistence(timeout: 5),
                      "The reversed pending state did not survive a background flush and relaunch")
        XCTAssertEqual(survivingRows.count, 1, "The reversed pending state did not survive a background flush and relaunch")
        assertMoney(identifier: "reconcile.difference", exactly: "-25.00")
        attachScreenshot(named: "Pending-again state survived relaunch")
    }

    // MARK: - Navigation

    private func openBankAccount() {
        tap(app.tabBars.buttons["Settings"], description: "Settings tab")
        tap(app.buttons["settings.manageAccounts"], description: "Manage accounts")
        XCTAssertTrue(app.buttons["accounts.add"].waitForExistence(timeout: 5))

        let bankAccount = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "accounts.account.", "Fixture Bank"
        )).firstMatch
        tap(bankAccount, description: "Fixture Bank account")
        XCTAssertTrue(app.navigationBars["Fixture Bank"].waitForExistence(timeout: 5))
    }

    private func openReconcile() {
        tap(app.buttons["account.actions"], description: "Account actions")
        tap(app.buttons["account.reconcile"], description: "Reconcile")
        XCTAssertTrue(app.navigationBars["Reconcile"].waitForExistence(timeout: 5))
    }

    private func backToAccountDetail() {
        tapBackButton()
        XCTAssertTrue(app.navigationBars["Fixture Bank"].waitForExistence(timeout: 5))
    }

    private func markGroceriesEntryPending() {
        let cell = activityCell(containing: "Reconciliation groceries run")
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Missing cell for the confirmed groceries entry")
        XCTAssertTrue(cell.isHittable, "Groceries cell is offscreen")

        // This row's swipe action allows a full swipe, which can perform "Mark
        // pending" immediately by itself. A short drag reveals the action
        // instead, so the explicit tap below remains meaningful.
        let dragStart = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let dragEnd = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

        let markPending = app.buttons["Mark pending"]
        XCTAssertTrue(markPending.waitForExistence(timeout: 5), "Missing 'Mark pending' swipe action")
        XCTAssertTrue(markPending.isEnabled, "Disabled 'Mark pending' swipe action")
        XCTAssertTrue(markPending.isHittable, "Unhittable 'Mark pending' swipe action")
        markPending.tap()
    }

    private func tapBackButton() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier != %@", "account.actions")
        ).firstMatch
        tap(back, description: "Back")
    }

    // MARK: - Activity list

    /// `EntryRow` combines its children into one accessibility element, so its
    /// memo text is not a separate leaf `staticText` — the containing List cell
    /// has to be matched by its combined label instead.
    private func activityCell(containing memo: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", memo)).firstMatch
    }

    private func assertActivityCellExists(containing memo: String, message: String) {
        XCTAssertTrue(activityCell(containing: memo).waitForExistence(timeout: 5), message)
    }

    // MARK: - Actions

    private func setStatement(_ amount: String) {
        let field = app.textFields["reconcile.statementField"]
        makeHittable(field)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        // A trailing newline submits (see `onSubmit` in `AccountReconcileView`),
        // which clears focus and dismisses the keyboard, so the row scrolling
        // below isn't fighting an onscreen keyboard for space.
        field.typeText(amount + "\n")
        XCTAssertTrue(
            app.keyboards.element.waitForNonExistence(timeout: 5),
            "Keyboard did not dismiss after submitting the statement amount"
        )
    }

    // MARK: - Assertions

    /// Looks a leaf element up by identifier regardless of its concrete
    /// accessibility type (`staticText`, `image`, etc.), so a check does not
    /// depend on guessing how SwiftUI happens to expose a given view on a given
    /// OS version.
    private func anyElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Strips everything but digits, the decimal point, and a sign — mapping
    /// Foundation's Unicode minus (U+2212) to a plain hyphen — so a currency
    /// figure can be compared for its exact, signed value regardless of symbol,
    /// spacing, or which minus glyph the OS happens to format with.
    private func normalizedAmount(_ label: String) -> String {
        var result = ""
        for scalar in label.unicodeScalars {
            switch scalar {
            case "0"..."9", ".":
                result.unicodeScalars.append(scalar)
            case "-", "\u{2212}":
                result.append("-")
            default:
                continue
            }
        }
        return result
    }

    private func assertMoney(identifier: String, exactly expected: String) {
        let element = anyElement(identifier)
        makeHittable(element)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(identifier)")
        XCTAssertTrue(element.isHittable, "Unhittable \(identifier)")
        let predicate = NSPredicate { [self] evaluatedObject, _ in
            guard let element = evaluatedObject as? XCUIElement else { return false }
            return normalizedAmount(element.label) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Expected \(identifier) to read \(expected), found \(element.label)"
                + " (normalized: \(normalizedAmount(element.label)))"
        )
    }

    // MARK: - Launch and XCUI helpers

    private func configureLaunch(reset: Bool) {
        app.launchArguments = ["--accountant-ui-testing"]
        if reset { app.launchArguments.append("--accountant-ui-testing-reset") }
        app.launchEnvironment = [
            "ACCOUNTANT_UI_TEST_RUN_ID": runID,
            "ACCOUNTANT_UI_TEST_NOW": "2026-09-13T12:00:00Z",
            "ACCOUNTANT_UI_TEST_LEDGER_SEED": "reconciliation",
            "AppleLanguages": "(en)",
            "AppleLocale": "en_US",
            "TZ": "UTC"
        ]
    }

    private func persistAndRelaunch() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.waitUntilBackgrounded(), "App did not enter the background")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.terminate()
        configureLaunch(reset: false)
        app.launch()
        dismissOnboardingIfPresented()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
    }

    private func dismissOnboardingIfPresented() {
        let skip = app.buttons["Skip for now"]
        guard skip.waitForExistence(timeout: 1) else { return }

        XCTAssertTrue(skip.isHittable, "Visible setup could not be skipped")
        guard skip.isHittable else { return }
        skip.tap()
        XCTAssertTrue(skip.waitForNonExistence(timeout: 5), "Setup remained after Skip for now")
    }

    private func tap(_ element: XCUIElement, description: String) {
        makeHittable(element)
        XCTAssertTrue(element.exists, "Missing \(description)")
        XCTAssertTrue(element.isEnabled, "Disabled \(description)")
        XCTAssertTrue(element.isHittable, "Unhittable \(description)")
        guard element.exists, element.isEnabled, element.isHittable else { return }
        element.tap()
    }

    /// Scrolls down first, then — bounded — back up.
    ///
    /// The statement card sits above the row list this screen also scrolls
    /// through. A `List` can recycle it once rows have been scrolled past, so
    /// searching in one direction only can strand a caller looking for it again
    /// after having scrolled down for a row lower in the list.
    private func makeHittable(_ element: XCUIElement) {
        if element.exists && element.isHittable { return }

        let surface = activeScrollSurface()
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            surface.swipeUp()
        }
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            surface.swipeDown()
        }
    }

    private func activeScrollSurface() -> XCUIElement {
        if let collection = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) {
            return collection
        }
        return app.tables.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

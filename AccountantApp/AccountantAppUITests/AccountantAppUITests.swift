import XCTest

final class AccountantAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var runID: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        runID = UUID().uuidString
        app = XCUIApplication()
        let ledgerSeed = name.contains("testBudgetWithoutActiveExpenseCreatesCategoryAndLimit")
            ? "no-active-expense"
            : nil
        configureLaunch(
            reset: true,
            ledgerSeed: ledgerSeed,
            failFirstBudgetStop: name.contains("testBudgetStopRetriesAfterSaveFailure")
        )
        app.launch()

        addTeardownBlock { [weak self] in
            guard let self, let app = self.app else { return }
            self.attachScreenshot(named: "Final state", from: app)
            app.terminate()
        }
    }

    @MainActor
    func testSeptemberBudgetCaptureConfirmationAndRelaunch() throws {
        let budgetTab = app.tabBars.buttons["Budget"]
        XCTAssertTrue(budgetTab.waitForExistence(timeout: 10))
        budgetTab.tap()

        assertSeptemberIsVisible()

        let setLimit = app.buttons["budget.setLimit.empty"]
        XCTAssertTrue(setLimit.waitForExistence(timeout: 5))
        assertWideEnabledButton(setLimit, label: "Set a limit")
        attachScreenshot(named: "Empty September budget with active category")
        setLimit.tap()

        let eatingOut = app.buttons[
            "budget.category.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(eatingOut.waitForExistence(timeout: 5))
        eatingOut.tap()

        XCTAssertTrue(app.navigationBars["Set a limit"].waitForExistence(timeout: 5))
        tapAmountDigits([2, 0, 0, 0])
        let saveLimit = app.buttons["budget.limit.save"]
        XCTAssertTrue(saveLimit.waitForExistence(timeout: 5))
        XCTAssertTrue(saveLimit.isEnabled)
        saveLimit.tap()

        assertBudgetLine(remaining: "20.00", spent: "0.00")
        attachScreenshot(named: "September EUR 20 budget")

        // The month title is inert. Tapping figures on the card intentionally
        // opens the editor; canceling must return to the same month and card.
        app.staticTexts["budget.month.title"].tap()
        assertSeptemberIsVisible()
        assertEditorRoundTrip(from: app.staticTexts["budget.line.remaining"])
        assertEditorRoundTrip(from: app.otherElements["budget.line.progress"])

        app.buttons["capture.open"].tap()
        XCTAssertTrue(app.navigationBars["Spend"].waitForExistence(timeout: 5))
        tapAmountDigits([1, 0])

        let captureCategory = app.buttons["capture.category.Eating out"]
        XCTAssertTrue(captureCategory.isEnabled)
        captureCategory.tap()

        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5))
        assertBudgetLine(remaining: "19.90", spent: "0.10")
        attachScreenshot(named: "EUR 0.10 draft counted once")

        app.tabBars.buttons["Overview"].tap()

        let openReview = app.buttons["review.open"]
        XCTAssertTrue(openReview.waitForExistence(timeout: 5))
        openReview.tap()

        let confirm = app.buttons["review.confirmAll"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Nothing to review"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Budget"].tap()
        assertBudgetLine(remaining: "19.90", spent: "0.10")
        attachScreenshot(named: "EUR 0.10 confirmed without double counting")

        // Preserve the lifecycle regression: an ordinary debounced write must
        // survive a background/foreground transition and the first relaunch.
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.waitUntilBackgrounded(), "App did not enter the background")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Budget"].waitForExistence(timeout: 5))
        app.terminate()

        configureLaunch(reset: false)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Budget"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Budget"].tap()
        assertSeptemberIsVisible()
        assertBudgetLine(remaining: "19.90", spent: "0.10")
        attachScreenshot(named: "Confirmed budget after lifecycle relaunch")

        // Stop is an awaited durable action. The category's retained spending is
        // deliberately shown as unbudgeted, so it cannot be mistaken for an
        // active limit after the row disappears.
        let budgetLine = app.otherElements[
            "budget.line.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(budgetLine.waitForExistence(timeout: 5))
        budgetLine.swipeLeft()
        let stop = app.buttons[
            "budget.line.stop.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        let noLimits = app.staticTexts["No limits set for this month."]
        XCTAssertTrue(noLimits.waitForExistence(timeout: 5))
        let unbudgeted = app.buttons[
            "budget.unbudgeted.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(unbudgeted.waitForExistence(timeout: 5))
        waitUntilEnabled(unbudgeted, message: "Stop should finish before termination")
        XCTAssertFalse(app.otherElements["budget.stop.unsaved"].exists)
        XCTAssertFalse(app.buttons["budget.stop.retry"].exists)
        XCTAssertTrue(unbudgeted.label.contains("Eating out"))
        XCTAssertTrue(unbudgeted.label.contains("0.10"))
        attachScreenshot(named: "Stopped September limit with retained spending")

        // Terminate immediately after the observable durable completion. Do not
        // rely on debounce timing or a background-triggered write here.
        app.terminate()

        configureLaunch(reset: false)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Budget"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Budget"].tap()

        assertSeptemberIsVisible()
        XCTAssertTrue(app.staticTexts["No limits set for this month."].waitForExistence(timeout: 5))
        let persistedUnbudgeted = app.buttons[
            "budget.unbudgeted.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(persistedUnbudgeted.waitForExistence(timeout: 5))
        XCTAssertTrue(persistedUnbudgeted.label.contains("0.10"))
        attachScreenshot(named: "Stopped budget after relaunch")
    }

    @MainActor
    func testBudgetWithoutActiveExpenseCreatesCategoryAndLimit() throws {
        let budgetTab = app.tabBars.buttons["Budget"]
        XCTAssertTrue(budgetTab.waitForExistence(timeout: 10))
        budgetTab.tap()
        assertSeptemberIsVisible()

        let setLimit = app.buttons["budget.setLimit.empty"]
        XCTAssertTrue(setLimit.waitForExistence(timeout: 5))
        assertWideEnabledButton(setLimit, label: "Add a category")
        attachScreenshot(named: "Budget with no active expense categories")

        // Both entry points must offer category creation when every expense
        // category is missing or archived. Exercise the toolbar route first and
        // cancel so the central call to action can complete the workflow.
        let toolbarSetLimit = app.buttons["budget.setLimit.toolbar"]
        XCTAssertTrue(toolbarSetLimit.waitForExistence(timeout: 5))
        XCTAssertTrue(toolbarSetLimit.isEnabled)
        XCTAssertTrue(toolbarSetLimit.isHittable)
        toolbarSetLimit.tap()
        XCTAssertTrue(app.navigationBars["New category"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5))

        setLimit.tap()
        XCTAssertTrue(app.navigationBars["New category"].waitForExistence(timeout: 5))

        let categoryName = app.textFields["account.name"]
        XCTAssertTrue(categoryName.waitForExistence(timeout: 5))
        categoryName.tap()
        categoryName.typeText("Groceries")

        let saveCategory = app.buttons["account.save"]
        XCTAssertTrue(saveCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(saveCategory.isEnabled)
        saveCategory.tap()
        XCTAssertTrue(app.navigationBars["Budget"].waitForExistence(timeout: 5))

        let setCreatedCategoryLimit = app.buttons["budget.setLimit.empty"]
        XCTAssertTrue(setCreatedCategoryLimit.waitForExistence(timeout: 5))
        assertWideEnabledButton(setCreatedCategoryLimit, label: "Set a limit")
        setCreatedCategoryLimit.tap()

        let groceries = app.buttons.matching(NSPredicate(format: "label == %@", "Groceries")).firstMatch
        XCTAssertTrue(groceries.waitForExistence(timeout: 5))
        groceries.tap()

        XCTAssertTrue(app.navigationBars["Set a limit"].waitForExistence(timeout: 5))
        tapAmountDigits([2, 0, 0, 0])
        let saveLimit = app.buttons["budget.limit.save"]
        XCTAssertTrue(saveLimit.waitForExistence(timeout: 5))
        XCTAssertTrue(saveLimit.isEnabled)
        saveLimit.tap()

        assertBudgetLine(remaining: "20.00", spent: "0.00")
        attachScreenshot(named: "Budget after creating category and EUR 20 limit")
    }

    @MainActor
    func testBudgetStopRetriesAfterSaveFailure() throws {
        let budgetTab = app.tabBars.buttons["Budget"]
        XCTAssertTrue(budgetTab.waitForExistence(timeout: 10))
        budgetTab.tap()
        assertSeptemberIsVisible()

        let initialSetLimit = app.buttons["budget.setLimit.empty"]
        XCTAssertTrue(initialSetLimit.waitForExistence(timeout: 5))
        initialSetLimit.tap()
        let eatingOut = app.buttons[
            "budget.category.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(eatingOut.waitForExistence(timeout: 5))
        eatingOut.tap()
        XCTAssertTrue(app.navigationBars["Set a limit"].waitForExistence(timeout: 5))
        tapAmountDigits([2, 0, 0, 0])
        app.buttons["budget.limit.save"].tap()
        assertBudgetLine(remaining: "20.00", spent: "0.00")

        let budgetLine = app.otherElements[
            "budget.line.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(budgetLine.waitForExistence(timeout: 5))
        budgetLine.swipeLeft()
        let stop = app.buttons[
            "budget.line.stop.00000000-0000-0000-0000-000000000201"
        ]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        let saveFailure = app.alerts["Couldn't save"]
        XCTAssertTrue(saveFailure.waitForExistence(timeout: 5))
        XCTAssertTrue(saveFailure.buttons["OK"].waitForExistence(timeout: 5))
        saveFailure.buttons["OK"].tap()

        // The target disappearing is optimistic. The retry state is the visible
        // proof that Stop did not report durability after the injected failure.
        let retry = app.buttons["budget.stop.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["budget.stop.unsaved"].exists)
        attachScreenshot(named: "Budget stop pending retry after save failure")
        retry.tap()

        let setLimit = app.buttons["budget.setLimit.empty"]
        XCTAssertTrue(setLimit.waitForExistence(timeout: 5))
        waitUntilEnabled(setLimit, message: "Retry should finish before termination")
        XCTAssertFalse(app.otherElements["budget.stop.unsaved"].exists)
        XCTAssertFalse(app.buttons["budget.stop.retry"].exists)

        // The retry completed a real JSON save. Terminate immediately instead of
        // allowing a later background path to mask a durability regression.
        app.terminate()
        configureLaunch(reset: false, failFirstBudgetStop: true)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Budget"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Budget"].tap()
        assertSeptemberIsVisible()
        XCTAssertTrue(app.staticTexts["No limits set for this month."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["budget.setLimit.empty"].isEnabled)
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, message: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed,
                       message, file: file, line: line)
    }

    private func configureLaunch(
        reset: Bool,
        ledgerSeed: String? = nil,
        failFirstBudgetStop: Bool = false
    ) {
        app.launchArguments = ["--accountant-ui-testing"]
        if reset { app.launchArguments.append("--accountant-ui-testing-reset") }
        var environment: [String: String] = [
            "ACCOUNTANT_UI_TEST_RUN_ID": runID,
            "ACCOUNTANT_UI_TEST_NOW": "2026-09-13T12:00:00Z",
            "AppleLanguages": "(en)",
            "AppleLocale": "en_US",
            "TZ": "UTC"
        ]
        if let ledgerSeed {
            environment["ACCOUNTANT_UI_TEST_LEDGER_SEED"] = ledgerSeed
        }
        if failFirstBudgetStop {
            environment["ACCOUNTANT_UI_TEST_FAIL_FIRST_BUDGET_STOP"] = "1"
        }
        app.launchEnvironment = environment
    }

    private func tapAmountDigits(_ digits: [Int]) {
        for digit in digits {
            let key = app.buttons["amount.key.\(digit)"]
            XCTAssertTrue(key.waitForExistence(timeout: 3), "Missing amount digit \(digit)")
            key.tap()
        }
    }

    private func assertSeptemberIsVisible() {
        let month = app.staticTexts["budget.month.title"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        XCTAssertEqual(month.label, "September 2026")
    }

    private func assertWideEnabledButton(_ button: XCUIElement, label: String) {
        XCTAssertEqual(button.label, label)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        XCTAssertGreaterThan(
            button.frame.width,
            button.frame.height,
            "Expected \(label) to be a horizontal button, found frame \(button.frame)"
        )
    }

    private func assertBudgetLine(remaining: String, spent: String) {
        let remainingText = app.staticTexts["budget.line.remaining"]
        let spentText = app.staticTexts["budget.line.spent"]

        XCTAssertTrue(remainingText.waitForExistence(timeout: 5))
        XCTAssertTrue(spentText.waitForExistence(timeout: 5))
        XCTAssertTrue(
            remainingText.label.contains(remaining),
            "Expected remaining amount \(remaining), found \(remainingText.label)"
        )
        XCTAssertTrue(
            spentText.label.contains(spent),
            "Expected spent amount \(spent), found \(spentText.label)"
        )
    }

    private func assertEditorRoundTrip(from element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.tap()

        XCTAssertTrue(app.navigationBars["Change limit"].waitForExistence(timeout: 5))
        let scope = app.staticTexts["budget.limit.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertTrue(scope.label.contains("September 2026"))
        app.buttons["Cancel"].tap()

        assertSeptemberIsVisible()
        assertBudgetLine(remaining: "20.00", spent: "0.00")
    }

    private func attachScreenshot(named name: String, from application: XCUIApplication? = nil) {
        let attachment = XCTAttachment(screenshot: (application ?? app).screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

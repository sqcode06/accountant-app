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
        configureLaunch(reset: true, ledgerSeed: ledgerSeed)
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

        // Let the ordinary debounced write settle, then exercise a background /
        // foreground transition before a real process termination and relaunch.
        Thread.sleep(forTimeInterval: 1)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
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
        attachScreenshot(named: "Confirmed budget after relaunch")
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

    private func configureLaunch(reset: Bool, ledgerSeed: String? = nil) {
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

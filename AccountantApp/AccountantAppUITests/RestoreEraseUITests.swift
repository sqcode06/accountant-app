import XCTest

final class RestoreEraseUITests: XCTestCase {
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
            screenshot.name = "Final restore-erase state"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)

            if self.testRun?.failureCount ?? 0 > 0 {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Restore-erase failure hierarchy"
                hierarchy.lifetime = .keepAlways
                self.add(hierarchy)
            }
            app.terminate()
        }
    }

    @MainActor
    func testRestoreThenEraseRemainsEmptyAfterRelaunch() {
        openSettings()
        waitAndTap(app.buttons["Restore from a backup"], description: "Restore from a backup")
        XCTAssertTrue(app.navigationBars["Restore"].waitForExistence(timeout: 5))

        waitAndTap(app.buttons["restore.chooseFile"], description: "Fixture backup file")
        assertRestoreComparison(
            current: [
                "transactions": "0",
                "accounts": "2",
                "drafts": "0",
                "budgets": "0",
                "rules": "0"
            ],
            backup: [
                "transactions": "2",
                "accounts": "3",
                "drafts": "1",
                "budgets": "1",
                "rules": "1"
            ]
        )
        attachScreenshot(named: "Decoded restore backup comparison")

        waitAndTap(app.buttons["restore.request"], description: "Request restore")
        tapConfirmationButton(identifier: "restore.confirm", description: "Confirm restore")

        let result = app.staticTexts["restore.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Restore did not finish")
        XCTAssertEqual(result.label, "Your data has been replaced with the backup and saved.")

        assertRestoredActivity()
        attachScreenshot(named: "Restored transactions and review state")

        persistAndRelaunch()

        assertRestoredActivity()
        openDangerZoneFromRoot()
        assertDangerCounts(transactions: 2, accounts: 3, budgets: 1, rules: 1)
        attachScreenshot(named: "Restored data persists after relaunch")

        waitAndTap(
            app.buttons["danger.erase"],
            description: "Erase everything",
            scrollDirection: .backward
        )
        tapConfirmationButton(identifier: "danger.confirmErase", description: "Confirm erase")
        dismissOnboardingIfPresented()
        assertDangerCounts(transactions: 0, accounts: 0, budgets: 0, rules: 0)

        persistAndRelaunch()

        waitAndTap(app.tabBars.buttons["Activity"], description: "Activity after erased relaunch")
        XCTAssertTrue(
            app.staticTexts["Nothing recorded yet"].waitForExistence(timeout: 10),
            "Financial data returned after erase and relaunch"
        )
        XCTAssertFalse(app.staticTexts["Restored groceries"].exists)
        XCTAssertFalse(app.staticTexts["Restored salary"].exists)

        openDangerZoneFromRoot()
        assertDangerCounts(transactions: 0, accounts: 0, budgets: 0, rules: 0)
        attachScreenshot(named: "Erased data remains empty after relaunch")
    }

    // MARK: - Navigation

    private func openSettings() {
        waitAndTap(app.tabBars.buttons["Settings"], description: "Settings tab")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func openDangerZoneFromRoot() {
        openSettings()
        waitAndTap(app.buttons["Danger zone"], description: "Danger zone")
        XCTAssertTrue(app.navigationBars["Danger zone"].waitForExistence(timeout: 5))
    }

    // MARK: - Assertions and actions

    private func assertRestoredActivity() {
        waitAndTap(app.tabBars.buttons["Activity"], description: "Activity after restore")
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "1 entry to review")
            ).firstMatch.waitForExistence(timeout: 5),
            "The restored draft was not awaiting review"
        )
        XCTAssertTrue(app.staticTexts["Restored groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Restored salary"].waitForExistence(timeout: 5))
    }

    private func assertRestoreComparison(
        current: [String: String],
        backup: [String: String]
    ) {
        for key in ["transactions", "accounts", "drafts", "budgets", "rules"] {
            guard let currentValue = current[key], let backupValue = backup[key] else {
                XCTFail("Missing expected restore count for \(key)")
                return
            }
            assertStaticText(identifier: "restore.currentCount.\(key)", equals: currentValue)
            assertStaticText(identifier: "restore.backupCount.\(key)", equals: backupValue)
        }
    }

    private func assertDangerCounts(
        transactions: Int,
        accounts: Int,
        budgets: Int,
        rules: Int
    ) {
        assertStaticText(identifier: "danger.count.transactions", equals: "\(transactions)")
        assertStaticText(identifier: "danger.count.accounts", equals: "\(accounts)")
        assertStaticText(identifier: "danger.count.budgets", equals: "\(budgets)")
        assertStaticText(identifier: "danger.count.rules", equals: "\(rules)")
    }

    private func assertStaticText(identifier: String, equals expected: String) {
        let text = app.staticTexts[identifier]
        makeHittable(text)
        XCTAssertTrue(text.exists, "Missing \(identifier)")
        let valueMatches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: text
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [valueMatches], timeout: 10),
            .completed,
            "Unexpected value for \(identifier): \(text.label)"
        )
    }

    private func tapConfirmationButton(identifier: String, description: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(description)")
        XCTAssertTrue(button.isEnabled, "Disabled \(description)")
        XCTAssertTrue(button.isHittable, "Unhittable \(description)")
        guard button.exists, button.isEnabled, button.isHittable else { return }
        button.tap()
    }

    // MARK: - Launch and XCUI helpers

    private func configureLaunch(reset: Bool) {
        app.launchArguments = ["--accountant-ui-testing"]
        if reset { app.launchArguments.append("--accountant-ui-testing-reset") }
        app.launchEnvironment = [
            "ACCOUNTANT_UI_TEST_RUN_ID": runID,
            "ACCOUNTANT_UI_TEST_NOW": "2026-09-13T12:00:00Z",
            "ACCOUNTANT_UI_TEST_LEDGER_SEED": "restore-erase",
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

    private func waitAndTap(
        _ element: XCUIElement,
        description: String,
        scrollDirection: ScrollDirection = .forward
    ) {
        makeHittable(element, direction: scrollDirection)
        XCTAssertTrue(element.exists, "Missing \(description)")
        XCTAssertTrue(element.isEnabled, "Disabled \(description)")
        XCTAssertTrue(element.isHittable, "Unhittable \(description)")
        guard element.exists, element.isEnabled, element.isHittable else { return }
        element.tap()
    }

    private func makeHittable(
        _ element: XCUIElement,
        direction: ScrollDirection = .forward
    ) {
        if element.exists && element.isHittable { return }

        let surface = activeScrollSurface()
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            switch direction {
            case .forward:
                surface.swipeUp()
            case .backward:
                surface.swipeDown()
            }
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

    private enum ScrollDirection {
        case forward
        case backward
    }
}

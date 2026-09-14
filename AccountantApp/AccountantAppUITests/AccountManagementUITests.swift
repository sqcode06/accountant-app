import XCTest

final class AccountManagementUITests: XCTestCase {
    private let accountName = "UI Test Reserve"
    private let renamedAccountName = "UI Test Reserve Renamed"

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
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Final account-management state"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            app.terminate()
        }
    }

    @MainActor
    func testCreateRenameArchiveRestoreAndRelaunch() throws {
        openAccounts()

        tap(app.buttons["accounts.add"], description: "Add account")
        let nameField = app.textFields["account.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(accountName)
        tap(app.buttons["account.save"], description: "Save new account")

        let createdAccount = accountLink(named: accountName)
        XCTAssertTrue(createdAccount.waitForExistence(timeout: 5), "New asset account did not appear")
        XCTAssertTrue(createdAccount.label.contains(accountName))
        tap(createdAccount, description: "New account")
        XCTAssertTrue(app.staticTexts["Asset"].waitForExistence(timeout: 5), "New account was not an asset")

        tap(app.buttons["account.actions"], description: "Account actions")
        tap(app.buttons["account.edit"], description: "Edit account")
        XCTAssertTrue(app.navigationBars["Edit Account"].waitForExistence(timeout: 5))
        replaceText(in: nameField, with: renamedAccountName)
        tap(app.buttons["account.save"], description: "Save renamed account")

        XCTAssertTrue(app.navigationBars[renamedAccountName].waitForExistence(timeout: 5))
        tap(app.buttons["account.actions"], description: "Account actions after rename")
        tap(app.buttons["account.archive"], description: "Archive account")

        // Archive dismisses the Actions menu. Verify the resulting account state
        // in the list, where it is visible without reopening that menu.
        navigateBackToAccounts()
        let archivedAccount = accountLink(named: renamedAccountName)
        XCTAssertTrue(
            archivedAccount.waitForNonExistence(timeout: 5),
            "Archived account remained in the active-account list"
        )

        tap(app.buttons["accounts.showArchived"], description: "Show archived accounts")
        XCTAssertTrue(archivedAccount.waitForExistence(timeout: 5), "Archived account was not shown")
        XCTAssertTrue(archivedAccount.label.contains("Archived"), "Archived state was not exposed in the row")
        attachScreenshot(named: "Archived account in account list")

        let archivedCell = app.cells.containing(.button, identifier: archivedAccount.identifier).firstMatch
        XCTAssertTrue(archivedCell.waitForExistence(timeout: 5), "Missing cell for archived account")
        XCTAssertTrue(archivedCell.isHittable, "Archived account is offscreen")
        // A full swipe can perform Restore immediately. Reveal the action with
        // a short drag so the following explicit tap remains meaningful.
        let dragStart = archivedCell.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let dragEnd = archivedCell.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        tap(app.buttons["accounts.restore"], description: "Restore archived account")
        XCTAssertTrue(
            accountLink(named: renamedAccountName).waitForExistence(timeout: 5),
            "Restored account did not return to the active-account list"
        )
        XCTAssertFalse(accountLink(named: renamedAccountName).label.contains("Archived"))

        // Account edits are deliberately debounced. Moving to the background
        // invokes the app's real flush hook; the following relaunch verifies the
        // saved snapshot rather than treating the optimistic row as durable.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.waitUntilBackgrounded(), "App did not enter the background")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.terminate()
        configureLaunch(reset: false)
        app.launch()

        openAccounts()
        let relaunchedAccount = accountLink(named: renamedAccountName)
        XCTAssertTrue(relaunchedAccount.waitForExistence(timeout: 10), "Restored account did not survive relaunch")
        XCTAssertTrue(relaunchedAccount.label.contains(renamedAccountName))
        XCTAssertFalse(relaunchedAccount.label.contains("Archived"))
        attachScreenshot(named: "Restored active account after relaunch")
    }

    private func configureLaunch(reset: Bool) {
        app.launchArguments = ["--accountant-ui-testing"]
        if reset { app.launchArguments.append("--accountant-ui-testing-reset") }
        app.launchEnvironment = [
            "ACCOUNTANT_UI_TEST_RUN_ID": runID,
            "ACCOUNTANT_UI_TEST_NOW": "2026-09-13T12:00:00Z",
            "AppleLanguages": "(en)",
            "AppleLocale": "en_US",
            "TZ": "UTC"
        ]
    }

    private func openAccounts() {
        tap(app.tabBars.buttons["Settings"], description: "Settings tab")
        tap(app.buttons["settings.manageAccounts"], description: "Manage accounts")
        XCTAssertTrue(app.buttons["accounts.add"].waitForExistence(timeout: 5))
    }

    private func accountLink(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "accounts.account.", name
        )).firstMatch
    }

    private func navigateBackToAccounts() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier != %@", "account.actions")
        ).firstMatch
        tap(back, description: "Back to accounts")
        XCTAssertTrue(app.buttons["accounts.add"].waitForExistence(timeout: 5))
    }

    private func replaceText(in field: XCUIElement, with replacement: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(replacement)
    }

    private func tap(_ element: XCUIElement, description: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(description)")
        XCTAssertTrue(element.isEnabled, "Disabled \(description)")
        XCTAssertTrue(element.isHittable, "Unhittable \(description)")
        guard element.exists, element.isEnabled, element.isHittable else { return }
        element.tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

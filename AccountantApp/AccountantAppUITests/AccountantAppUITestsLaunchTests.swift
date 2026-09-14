import XCTest

final class AccountantAppUITestsLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFixtureLaunchesWithoutOnboardingOrProductionData() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--accountant-ui-testing",
            "--accountant-ui-testing-reset"
        ]
        app.launchEnvironment = [
            "ACCOUNTANT_UI_TEST_RUN_ID": "launch-\(UUID().uuidString)",
            "ACCOUNTANT_UI_TEST_NOW": "2026-09-13T12:00:00Z",
            "AppleLanguages": "(en)",
            "AppleLocale": "en_US",
            "TZ": "UTC"
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Overview"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Get started"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Isolated fixture launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

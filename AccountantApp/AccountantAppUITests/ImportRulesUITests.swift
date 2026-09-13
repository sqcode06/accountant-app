import XCTest

final class ImportRulesUITests: XCTestCase {
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
            attachment.name = "Final import-rules state"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            app.terminate()
        }
    }

    @MainActor
    func testRuleEditsPauseTryMatchAndOrderSurviveRelaunch() throws {
        openImportRules()
        addRule(matchText: "RIMI", category: "Groceries", memo: "Grocery run")
        addRule(matchText: "CITYBEE", category: "Transport", memo: "City ride")

        let rimiID = try ruleID(containing: "RIMI")
        let citybeeID = try ruleID(containing: "CITYBEE")
        assertRuleOrder(firstID: rimiID, secondID: citybeeID)

        let citybeeEdit = element(identifier: "rules.edit.\(citybeeID)")
        waitAndTap(citybeeEdit, description: "CITYBEE edit button")
        replaceText(in: element(identifier: "rules.matchText"), with: "CITYBEE RIDE")
        replaceText(in: element(identifier: "rules.memo"), with: "Booked ride")
        waitAndTap(element(identifier: "rules.save"), description: "Save edited rule")
        XCTAssertTrue(app.navigationBars["Import rules"].waitForExistence(timeout: 5))

        let rimiToggle = app.switches["rules.enabled.\(rimiID)"]
        waitAndTap(rimiToggle, description: "RIMI enabled toggle")
        XCTAssertTrue(waitForSwitch(rimiToggle, isOn: false), "RIMI rule did not pause")

        assertTryMatch(
            "A CITYBEE RIDE IN TALLINN",
            contains: ["Transport", "Booked ride"]
        )
        dismissKeyboard()
        attachScreenshot(named: "Rules try-match result")
        reorderRule(movingID: citybeeID, beforeID: rimiID)
        assertRuleOrder(firstID: citybeeID, secondID: rimiID)
        persistAndRelaunch()

        openImportRules()
        XCTAssertTrue(element(identifier: "rules.row.\(rimiID)").waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "rules.row.\(citybeeID)").waitForExistence(timeout: 5))
        assertRuleOrder(firstID: citybeeID, secondID: rimiID)

        let savedRimiToggle = app.switches["rules.enabled.\(rimiID)"]
        XCTAssertTrue(savedRimiToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSwitch(savedRimiToggle, isOn: false), "Paused state was not saved")

        let savedCitybeeEdit = element(identifier: "rules.edit.\(citybeeID)")
        XCTAssertTrue(savedCitybeeEdit.label.contains("CITYBEE RIDE"))
        XCTAssertTrue(savedCitybeeEdit.label.contains("Booked ride"))
        assertTryMatch("RIMI SUPERMARKET", contains: ["No active rules match"])
    }

    @MainActor
    func testRulesDriveRealRevolutImportReviewAndPersistedLedger() throws {
        openImportRules()
        addRule(matchText: "RIMI", category: "Groceries", memo: "Grocery run")
        addRule(matchText: "ACME PAYROLL", category: "Salary", memo: "September salary")
        waitAndTap(app.navigationBars["Import rules"].buttons["Settings"], description: "Back to Settings")

        waitAndTap(element(identifier: "settings.import"), description: "Import statement")
        waitAndTap(element(identifier: "import.format.revolut"), description: "Revolut format")
        waitAndTap(element(identifier: "import.file"), description: "Fixture statement file")
        waitAndTap(element(identifier: "import.continue"), description: "Continue after parsing")

        selectPicker(identifier: "import.statementAccount", option: "Revolut")
        selectPicker(identifier: "import.defaultCategory", option: "Uncategorised")
        selectPicker(identifier: "import.feeCategory", option: "Bank fees")
        waitAndTap(element(identifier: "import.preview"), description: "Build import preview")

        assertImportRow(
            0,
            category: "Groceries",
            memo: "Grocery run",
            ruleText: "RIMI",
            feeText: "0.40"
        )
        let firstPreviewRow = element(identifier: "import.row.0")
        let warning = firstPreviewRow.label.lowercased()
        XCTAssertTrue(
            warning.contains("duplicate") || warning.contains("reference"),
            "The Revolut missing-ID warning was not exposed: \(firstPreviewRow.label)"
        )
        attachScreenshot(named: "Revolut import preview with rule and fee")

        assertImportRow(
            1,
            category: "Salary",
            memo: "September salary",
            ruleText: "ACME PAYROLL"
        )
        assertImportRow(4, category: "Uncategorised", memo: "CORNER CAFE")

        waitAndTap(element(identifier: "import.apply"), description: "Import preview")
        let result = element(identifier: "import.result")
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("5"), "Unexpected import result: \(result.label)")
        waitAndTap(app.buttons["Done"], description: "Close import result")

        waitAndTap(app.tabBars.buttons["Overview"], description: "Overview tab")
        waitAndTap(app.buttons["review.open"], description: "Open review")

        let purchaseID = try reviewTransactionID(memo: "Grocery run", amount: "24.60")
        let purchaseCategory = element(identifier: "review.row.\(purchaseID).category")
        XCTAssertTrue(purchaseCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(purchaseCategory.label.contains("Groceries"))

        let fee = element(identifier: "review.row.\(purchaseID).fee")
        XCTAssertTrue(fee.waitForExistence(timeout: 5))
        XCTAssertTrue(fee.label.contains("0.40"), "Fee was not preserved in review: \(fee.label)")

        waitAndTap(purchaseCategory, description: "Purchase category")
        waitAndTap(app.buttons["Transport"], description: "Transport category option")
        XCTAssertTrue(waitForLabel(purchaseCategory, containing: "Transport"))
        XCTAssertTrue(fee.label.contains("0.40"), "Recategorising changed the separate fee")

        let incomeID = try reviewTransactionID(memo: "September salary", amount: "2,450")
        let incomeCategory = element(identifier: "review.row.\(incomeID).category")
        let incomeAmount = element(identifier: "review.row.\(incomeID).amount")
        XCTAssertTrue(incomeCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(incomeCategory.label.contains("Salary"))
        XCTAssertTrue(incomeAmount.waitForExistence(timeout: 5))
        XCTAssertTrue(incomeAmount.label.contains("2,450"))
        attachScreenshot(named: "Review purchase fee and income")

        waitAndTap(app.buttons["review.confirmAll"], description: "Confirm imported transactions")
        XCTAssertTrue(app.staticTexts["Nothing to review"].waitForExistence(timeout: 10))
        persistAndRelaunch()

        waitAndTap(app.tabBars.buttons["Activity"], description: "Activity tab after relaunch")
        assertVisibleText("September salary")
        assertVisibleText("CITYBEE RIDE")
        assertVisibleText("CORNER CAFE")

        let search = app.searchFields["Search memos"]
        waitAndTap(search, description: "Activity search")
        search.typeText("Grocery run")
        let groceryRows = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Grocery run")
        )
        XCTAssertTrue(groceryRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(
            groceryRows.count,
            2,
            "Both the purchase and refund should survive relaunch"
        )

        waitAndTap(app.tabBars.buttons["Overview"], description: "Overview after relaunch")
        XCTAssertTrue(app.navigationBars["Overview"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["review.open"].waitForExistence(timeout: 2),
            "A review prompt remained after every imported transaction was confirmed"
        )
    }

    // MARK: - Launch and navigation

    private func configureLaunch(reset: Bool) {
        app.launchArguments = ["--accountant-ui-testing"]
        if reset { app.launchArguments.append("--accountant-ui-testing-reset") }
        app.launchEnvironment = [
            "ACCOUNTANT_UI_TEST_RUN_ID": runID,
            "ACCOUNTANT_UI_TEST_NOW": "2026-09-13T12:00:00Z",
            "ACCOUNTANT_UI_TEST_LEDGER_SEED": "import-rules",
            "AppleLanguages": "(en)",
            "AppleLocale": "en_US",
            "TZ": "UTC"
        ]
    }

    private func persistAndRelaunch() {
        dismissKeyboard()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.terminate()
        configureLaunch(reset: false)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
    }

    private func openImportRules() {
        waitAndTap(app.tabBars.buttons["Settings"], description: "Settings tab")
        waitAndTap(element(identifier: "settings.importRules"), description: "Import rules")
        XCTAssertTrue(app.navigationBars["Import rules"].waitForExistence(timeout: 5))
    }

    // MARK: - Rules

    private func addRule(matchText: String, category: String, memo: String) {
        waitAndTap(element(identifier: "rules.add"), description: "Add rule")

        let matchField = element(identifier: "rules.matchText")
        XCTAssertTrue(matchField.waitForExistence(timeout: 5))
        XCTAssertTrue(matchField.isHittable)
        matchField.tap()
        matchField.typeText(matchText)

        selectPicker(identifier: "rules.category", option: category)

        let memoField = element(identifier: "rules.memo")
        XCTAssertTrue(memoField.waitForExistence(timeout: 5))
        XCTAssertTrue(memoField.isHittable)
        memoField.tap()
        memoField.typeText(memo)

        let save = element(identifier: "rules.save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        waitAndTap(save, description: "Save rule")
        XCTAssertTrue(app.navigationBars["Import rules"].waitForExistence(timeout: 5))
    }

    private func assertTryMatch(_ text: String, contains expected: [String]) {
        let field = element(identifier: "rules.tryText")
        makeHittable(field)
        XCTAssertTrue(field.isHittable)
        replaceText(in: field, with: text, clearingExisting: false)
        dismissKeyboard()

        let result = element(identifier: "rules.tryResult")
        makeHittable(result)
        XCTAssertTrue(result.exists)
        for value in expected {
            XCTAssertTrue(
                waitForLabel(result, containing: value),
                "Expected try-match result to contain \(value), found: \(result.label)"
            )
        }
    }

    private func ruleID(containing needle: String) throws -> String {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "rules.edit.",
            needle
        )
        let editButton = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Missing rule containing \(needle)")
        guard editButton.exists else { throw UITestFailure.missingElement("rule \(needle)") }
        return String(editButton.identifier.dropFirst("rules.edit.".count))
    }

    private func assertRuleOrder(firstID: String, secondID: String) {
        let first = element(identifier: "rules.row.\(firstID)")
        let second = element(identifier: "rules.row.\(secondID)")
        makeHittable(first)
        makeHittable(second)

        let ordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                first.exists && second.exists && first.frame.minY < second.frame.minY
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [ordered], timeout: 5),
            .completed,
            "Rule order changed"
        )
    }

    private func reorderRule(movingID: String, beforeID: String) {
        let reorderMode = element(identifier: "rules.reorder")
        waitAndTap(reorderMode, description: "Edit rule order")

        let movingRow = element(identifier: "rules.row.\(movingID)")
        let destinationRow = element(identifier: "rules.row.\(beforeID)")
        makeHittable(destinationRow)
        makeHittable(movingRow)
        XCTAssertTrue(movingRow.isHittable)
        XCTAssertTrue(destinationRow.isHittable)
        guard movingRow.isHittable, destinationRow.isHittable else { return }

        let matchingHandle = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@",
            "Reorder"
        )).allElementsBoundByIndex.first { handle in
            handle.isHittable
                && abs(handle.frame.midY - movingRow.frame.midY) < movingRow.frame.height / 2
        }

        let source = matchingHandle?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            ?? app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(
                CGVector(dx: movingRow.frame.maxX - 22, dy: movingRow.frame.midY)
            )
        let destination = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(
            CGVector(dx: movingRow.frame.maxX - 22, dy: destinationRow.frame.minY + 2)
        )
        source.press(forDuration: 0.8, thenDragTo: destination)

        assertRuleOrder(firstID: movingID, secondID: beforeID)
        waitAndTap(reorderMode, description: "Finish editing rule order")
    }

    // MARK: - Import and review

    private func assertImportRow(
        _ index: Int,
        category: String,
        memo: String,
        ruleText: String? = nil,
        feeText: String? = nil
    ) {
        let rowID = "import.row.\(index)"
        let row = element(identifier: rowID)
        makeHittable(row)
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        assertLabel(identifier: "\(rowID).category", contains: category)
        assertLabel(identifier: "\(rowID).memo", contains: memo)
        if let ruleText {
            assertLabel(identifier: "\(rowID).rule", contains: ruleText)
        }
        if let feeText {
            assertLabel(identifier: "\(rowID).fee", contains: feeText)
        }
    }

    private func reviewTransactionID(memo: String, amount: String) throws -> String {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@ AND label CONTAINS[c] %@",
            "review.row.",
            ".memo",
            memo
        )
        let memoElements = app.descendants(matching: .any).matching(predicate)

        for _ in 0..<8 {
            for memoElement in memoElements.allElementsBoundByIndex {
                let prefix = "review.row."
                let suffix = ".memo"
                guard memoElement.identifier.hasPrefix(prefix),
                      memoElement.identifier.hasSuffix(suffix)
                else { continue }

                let identifier = memoElement.identifier
                let start = identifier.index(identifier.startIndex, offsetBy: prefix.count)
                let end = identifier.index(
                    identifier.endIndex,
                    offsetBy: -suffix.count
                )
                let id = String(identifier[start..<end])
                guard UUID(uuidString: id) != nil else { continue }
                let amountElement = element(identifier: "review.row.\(id).amount")
                if amountElement.exists && amountElement.label.contains(amount) {
                    return id
                }
            }
            app.swipeUp()
        }

        XCTFail("Missing review row for \(memo), amount \(amount)")
        throw UITestFailure.missingElement("review row \(memo)")
    }

    // MARK: - XCUI helpers

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func selectPicker(identifier: String, option: String) {
        let picker = element(identifier: identifier)
        waitAndTap(picker, description: "\(identifier) picker")

        let choice = app.buttons.matching(
            NSPredicate(format: "label == %@", option)
        ).firstMatch
        waitAndTap(choice, description: "\(option) option")
    }

    private func waitAndTap(_ element: XCUIElement, description: String) {
        makeHittable(element)
        XCTAssertTrue(element.exists, "Missing \(description)")
        XCTAssertTrue(element.isEnabled, "Disabled \(description)")
        XCTAssertTrue(element.isHittable, "Unhittable \(description)")
        guard element.exists, element.isEnabled, element.isHittable else { return }
        element.tap()
    }

    private func makeHittable(_ element: XCUIElement) {
        dismissKeyboard()
        if element.exists && element.isHittable { return }

        // First establish a known top position, which also handles returning to a
        // toolbar or early row after a prior assertion scrolled to the bottom.
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }

        // Then scan down through lazily-created List rows until the target can
        // actually receive the tap.
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func dismissKeyboard() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }

        let returnKey = keyboard.buttons.matching(NSPredicate(
            format: "label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
            "Return",
            "Done",
            "Go"
        )).firstMatch
        if returnKey.exists && returnKey.isHittable {
            returnKey.tap()
        }
    }

    private func replaceText(
        in field: XCUIElement,
        with text: String,
        clearingExisting: Bool = true
    ) {
        makeHittable(field)
        XCTAssertTrue(field.exists)
        XCTAssertTrue(field.isHittable)
        guard field.exists, field.isHittable else { return }

        field.tap()
        let current = (field.value as? String) ?? ""
        if clearingExisting && !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    private func assertLabel(identifier: String, contains text: String) {
        let target = element(identifier: identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing \(identifier)")
        XCTAssertTrue(
            waitForLabel(target, containing: text),
            "Expected \(identifier) to contain \(text), found: \(target.label)"
        )
    }

    private func assertVisibleText(_ text: String) {
        let target = app.staticTexts[text]
        makeHittable(target)
        XCTAssertTrue(target.exists, "Missing text: \(text)")
        XCTAssertTrue(target.isHittable, "Text was not visible: \(text)")
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", text),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func waitForSwitch(_ element: XCUIElement, isOn: Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", isOn ? "1" : "0"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum UITestFailure: Error {
        case missingElement(String)
    }
}

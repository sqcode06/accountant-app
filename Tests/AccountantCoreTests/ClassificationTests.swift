import XCTest
@testable import AccountantCore

final class ClassificationTests: XCTestCase {
    func testMatchingDescriptionRuleReturnsSuggestion() throws {
        let fixture = makeFixture()
        let rule = DescriptionContainsRule(
            "rimi",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Rimi"
        )

        let suggestion = rule.classify(
            line: fixture.line(description: "RIMI EESTI FOOD"),
            current: fixture.draft
        )

        XCTAssertEqual(
            suggestion,
            ClassificationSuggestion(
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        )
    }

    func testNonMatchingDescriptionRuleReturnsNil() throws {
        let fixture = makeFixture()
        let rule = DescriptionContainsRule(
            "rimi",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Rimi"
        )

        let suggestion = rule.classify(
            line: fixture.line(description: "BOLT FOOD"),
            current: fixture.draft
        )

        XCTAssertNil(suggestion)
    }

    func testDescriptionMatchingIsCaseInsensitive() throws {
        let fixture = makeFixture()
        let rule = DescriptionContainsRule(
            "BoLt",
            counterpartyAccountID: fixture.transport.id,
            cleanedMemo: "Bolt"
        )

        let suggestion = rule.classify(
            line: fixture.line(description: "bolt ride 1234"),
            current: fixture.draft
        )

        XCTAssertEqual(
            suggestion,
            ClassificationSuggestion(
                counterpartyAccountID: fixture.transport.id,
                cleanedMemo: "Bolt"
            )
        )
    }

    func testEmptyNeedleNeverMatches() throws {
        let fixture = makeFixture()
        let rule = DescriptionContainsRule(
            "   ",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Should not apply"
        )

        let suggestion = rule.classify(
            line: fixture.line(description: "anything at all"),
            current: fixture.draft
        )

        XCTAssertNil(suggestion)
    }

    func testDescriptionRuleWithNoSuggestedFieldsReturnsNil() throws {
        let fixture = makeFixture()
        let rule = DescriptionContainsRule("rimi")

        let suggestion = rule.classify(
            line: fixture.line(description: "RIMI"),
            current: fixture.draft
        )

        XCTAssertNil(suggestion)
    }

    func testEmptyClassifierReturnsNilSuggestion() throws {
        let fixture = makeFixture()
        let classifier = TransactionClassifier()

        let suggestion = classifier.classify(
            line: fixture.line(description: "RIMI"),
            current: fixture.draft
        )

        XCTAssertNil(suggestion)
    }

    func testMultipleRulesCombineDifferentFields() throws {
        let fixture = makeFixture()
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("bolt", cleanedMemo: "Bolt"),
            DescriptionContainsRule("bolt", counterpartyAccountID: fixture.transport.id)
        ])

        let suggestion = classifier.classify(
            line: fixture.line(description: "BOLT RIDE"),
            current: fixture.draft
        )

        XCTAssertEqual(
            suggestion,
            ClassificationSuggestion(
                counterpartyAccountID: fixture.transport.id,
                cleanedMemo: "Bolt"
            )
        )
    }

    func testLaterRuleOverridesEarlierSuggestionForSameField() throws {
        let fixture = makeFixture()
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule("bolt", counterpartyAccountID: fixture.transport.id, cleanedMemo: "Bolt"),
            DescriptionContainsRule("bolt food", counterpartyAccountID: fixture.food.id, cleanedMemo: "Bolt Food")
        ])

        let suggestion = classifier.classify(
            line: fixture.line(description: "BOLT FOOD TALLINN"),
            current: fixture.draft
        )

        XCTAssertEqual(
            suggestion,
            ClassificationSuggestion(
                counterpartyAccountID: fixture.food.id,
                cleanedMemo: "Bolt Food"
            )
        )
    }

    func testAddRuleAppendsRulesInOrder() throws {
        let fixture = makeFixture()
        var classifier = TransactionClassifier()
        classifier.addRule(DescriptionContainsRule("bolt", counterpartyAccountID: fixture.transport.id))
        classifier.addRule(DescriptionContainsRule("bolt food", counterpartyAccountID: fixture.food.id))

        let suggestion = classifier.classify(
            line: fixture.line(description: "BOLT FOOD"),
            current: fixture.draft
        )

        XCTAssertEqual(suggestion?.counterpartyAccountID, fixture.food.id)
    }

    func testClassificationDoesNotMutateInputTransaction() throws {
        let fixture = makeFixture()
        let original = fixture.draft
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        ])

        _ = classifier.classify(
            line: fixture.line(description: "RIMI"),
            current: fixture.draft
        )

        XCTAssertEqual(fixture.draft, original)
    }

    func testApplyingSuggestionUpdatesCounterpartyPostingOnly() throws {
        let fixture = makeFixture()
        let suggestion = ClassificationSuggestion(
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Rimi"
        )
        let now = Date(timeIntervalSince1970: 99_999)

        let updated = try suggestion.applying(
            to: fixture.draft,
            statementAccountID: fixture.bank.id,
            now: now
        )

        XCTAssertEqual(updated.id, fixture.draft.id)
        XCTAssertEqual(updated.origin, fixture.draft.origin)
        XCTAssertEqual(updated.state, .draft)
        XCTAssertEqual(updated.memo, "Rimi")
        XCTAssertEqual(updated.updatedAt, now)
        XCTAssertEqual(updated.postings.count, 2)

        XCTAssertEqual(
            updated.postings[0],
            Posting(accountID: fixture.bank.id, money: Money(Decimal(-12), currency: fixture.eur))
        )
        XCTAssertEqual(
            updated.postings[1],
            Posting(accountID: fixture.groceries.id, money: Money(Decimal(12), currency: fixture.eur))
        )

        XCTAssertEqual(
            fixture.draft.postings[1],
            Posting(accountID: fixture.uncategorized.id, money: Money(Decimal(12), currency: fixture.eur))
        )
    }

    func testApplyingMemoOnlySuggestionDoesNotRequireCounterpartyLookup() throws {
        let fixture = makeFixture()
        let suggestion = ClassificationSuggestion(cleanedMemo: "Cleaned")

        let updated = try suggestion.applying(
            to: fixture.draft,
            statementAccountID: AccountID(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
        )

        XCTAssertEqual(updated.memo, "Cleaned")
        XCTAssertEqual(updated.postings, fixture.draft.postings)
    }

    func testApplyingEmptySuggestionReturnsOriginalTransactionWithoutTouchingTimestamp() throws {
        let fixture = makeFixture()
        let suggestion = ClassificationSuggestion()
        let now = Date(timeIntervalSince1970: 123_456)

        let updated = try suggestion.applying(
            to: fixture.draft,
            statementAccountID: fixture.bank.id,
            now: now
        )

        XCTAssertEqual(updated, fixture.draft)
        XCTAssertNotEqual(updated.updatedAt, now)
    }

    func testApplyingSuggestionThroughClassifierReturnsClassifiedDraft() throws {
        let fixture = makeFixture()
        let classifier = TransactionClassifier(rules: [
            DescriptionContainsRule(
                "rimi",
                counterpartyAccountID: fixture.groceries.id,
                cleanedMemo: "Rimi"
            )
        ])

        let updated = try classifier.classifiedDraft(
            line: fixture.line(description: "RIMI EESTI"),
            current: fixture.draft,
            statementAccountID: fixture.bank.id
        )

        XCTAssertEqual(updated.memo, "Rimi")
        XCTAssertEqual(updated.postings[1].accountID, fixture.groceries.id)
    }

    func testApplyingNilSuggestionReturnsOriginalTransaction() throws {
        let fixture = makeFixture()
        let suggestion: ClassificationSuggestion? = nil

        let updated = try suggestion.applying(
            to: fixture.draft,
            statementAccountID: fixture.bank.id
        )

        XCTAssertEqual(updated, fixture.draft)
    }

    func testApplyingSuggestionToFinalizedTransactionThrows() throws {
        let fixture = makeFixture()
        let finalized = Transaction.finalized(
            date: fixture.draft.date,
            memo: fixture.draft.memo,
            postings: fixture.draft.postings
        )
        let suggestion = ClassificationSuggestion(
            counterpartyAccountID: fixture.groceries.id
        )

        XCTAssertThrowsError(
            try suggestion.applying(
                to: finalized,
                statementAccountID: fixture.bank.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ClassificationError,
                ClassificationError.cannotApplyToFinalized(finalized.id)
            )
        }
    }

    func testApplyingCounterpartySuggestionWithoutStatementPostingThrows() throws {
        let fixture = makeFixture()
        let suggestion = ClassificationSuggestion(
            counterpartyAccountID: fixture.groceries.id
        )
        let missingStatementAccountID = AccountID(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)

        XCTAssertThrowsError(
            try suggestion.applying(
                to: fixture.draft,
                statementAccountID: missingStatementAccountID
            )
        ) { error in
            XCTAssertEqual(
                error as? ClassificationError,
                ClassificationError.statementPostingNotFound(missingStatementAccountID)
            )
        }
    }

    func testApplyingCounterpartySuggestionWithoutCounterpartyPostingThrows() throws {
        let fixture = makeFixture()
        let statementOnly = Transaction.draft(
            date: Date(timeIntervalSince1970: 100),
            memo: "Internal correction",
            postings: [
                Posting(accountID: fixture.bank.id, money: Money(Decimal(-12), currency: fixture.eur)),
                Posting(accountID: fixture.bank.id, money: Money(Decimal(12), currency: fixture.eur))
            ]
        )
        let suggestion = ClassificationSuggestion(counterpartyAccountID: fixture.groceries.id)

        XCTAssertThrowsError(
            try suggestion.applying(
                to: statementOnly,
                statementAccountID: fixture.bank.id
            )
        ) { error in
            XCTAssertEqual(error as? ClassificationError, ClassificationError.counterpartyPostingNotFound)
        }
    }

    func testApplyingCounterpartySuggestionToSplitTransactionThrowsAmbiguousCounterparty() throws {
        let fixture = makeFixture()
        let split = Transaction.draft(
            date: Date(timeIntervalSince1970: 100),
            memo: "Split",
            postings: [
                Posting(accountID: fixture.bank.id, money: Money(Decimal(-12), currency: fixture.eur)),
                Posting(accountID: fixture.food.id, money: Money(Decimal(5), currency: fixture.eur)),
                Posting(accountID: fixture.transport.id, money: Money(Decimal(7), currency: fixture.eur))
            ]
        )
        let suggestion = ClassificationSuggestion(
            counterpartyAccountID: fixture.groceries.id
        )

        XCTAssertThrowsError(
            try suggestion.applying(
                to: split,
                statementAccountID: fixture.bank.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ClassificationError,
                ClassificationError.ambiguousCounterpartyPostings
            )
        }
    }

    private func makeFixture() -> ClassificationFixture {
        ClassificationFixture()
    }
}

private struct ClassificationFixture {
    let eur: Currency
    let bank: Account
    let uncategorized: Account
    let groceries: Account
    let food: Account
    let transport: Account
    let draft: Transaction

    init() {
        let eur = Currency("EUR")
        let bank = Account(name: "Swedbank", kind: .asset)
        let uncategorized = Account(name: "Uncategorized", kind: .clearing)
        let groceries = Account(name: "Groceries", kind: .expense)
        let food = Account(name: "Food Delivery", kind: .expense)
        let transport = Account(name: "Transport", kind: .expense)

        self.eur = eur
        self.bank = bank
        self.uncategorized = uncategorized
        self.groceries = groceries
        self.food = food
        self.transport = transport
        self.draft = Transaction.draft(
            date: Date(timeIntervalSince1970: 100),
            memo: "Original",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-12), currency: eur)),
                Posting(accountID: uncategorized.id, money: Money(Decimal(12), currency: eur))
            ]
        )
    }

    func line(description: String) -> BankLine {
        BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-12),
            currency: eur,
            description: description,
            externalID: "X1"
        )
    }
}

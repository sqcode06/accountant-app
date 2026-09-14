import Testing
import Foundation
import AccountantCore

/// The stored form of a classification rule.
///
/// Moved here with the type itself: this is domain behaviour — normalising the
/// text people type, and turning a stored configuration into a live rule — and it
/// runs on Linux now rather than only in Xcode.
struct ClassificationRuleConfigurationTests {

    @Test func configurationBuildsDescriptionContainsRule() throws {
        let fixture = ClassificationFixture()
        let configuration = ClassificationRuleConfiguration(
            needle: "  rimi  ",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "  Rimi  "
        )

        let classifier = ClassificationRuleConfiguration.makeClassifier(from: [configuration])
        let line = fixture.line(description: "RIMI EESTI")
        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, _) = preview.outcomes.first else {
            Issue.record("Expected classified line to stay proposed")
            return
        }

        #expect(draft.memo == "Rimi")
        #expect(draft.postings[1].accountID == fixture.groceries.id)
    }

    @Test func disabledOrEmptyConfigurationsAreIgnored() throws {
        let fixture = ClassificationFixture()
        let disabled = ClassificationRuleConfiguration(
            needle: "rimi",
            counterpartyAccountID: fixture.groceries.id,
            cleanedMemo: "Rimi",
            isEnabled: false
        )
        let noEffect = ClassificationRuleConfiguration(needle: "rimi")

        let classifier = ClassificationRuleConfiguration.makeClassifier(from: [disabled, noEffect])
        let line = fixture.line(description: "RIMI EESTI")
        let preview = fixture.pipeline.previewImport(
            lines: [line],
            into: fixture.ledger,
            classifier: classifier,
            now: fixture.now
        )

        guard case .proposed(_, let draft, _) = preview.outcomes.first else {
            Issue.record("Expected neutral line to stay proposed")
            return
        }

        #expect(draft.memo == line.description)
        #expect(draft.postings[1].accountID == fixture.uncategorized.id)
    }

    @Test func classificationRuleConfigurationDecodingNormalizesPersistedText() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "   ",
          "needle": "  RIMI  ",
          "cleanedMemo": "  Groceries  ",
          "isEnabled": true
        }
        """

        let data = try #require(json.data(using: .utf8))
        let rule = try JSONDecoder().decode(ClassificationRuleConfiguration.self, from: data)

        #expect(rule.id == id)
        #expect(rule.name == "Groceries")
        #expect(rule.needle == "RIMI")
        #expect(rule.cleanedMemo == "Groceries")
        #expect(rule.isEnabled)
    }

    @Test func evaluationReportsOrderedMatchesAndIndependentFieldWinners() throws {
        let fixture = ClassificationFixture()
        let broadID = UUID()
        let memoID = UUID()
        let specificID = UUID()
        let broad = ClassificationRuleConfiguration(
            id: broadID,
            name: "Any Bolt",
            needle: "bolt",
            counterpartyAccountID: fixture.groceries.id
        )
        let memo = ClassificationRuleConfiguration(
            id: memoID,
            name: "Clean Bolt Food memo",
            needle: "bolt food",
            cleanedMemo: "Bolt Food"
        )
        let specific = ClassificationRuleConfiguration(
            id: specificID,
            name: "Bolt Food category",
            needle: "bolt food",
            counterpartyAccountID: fixture.food.id
        )

        let evaluation = [broad, memo, specific].evaluate(
            line: fixture.line(description: "BOLT FOOD TALLINN"),
            current: fixture.draft
        )

        #expect(evaluation.matches.map(\.id) == [broadID, memoID, specificID])
        #expect(evaluation.matches.map(\.name) == ["Any Bolt", "Clean Bolt Food memo", "Bolt Food category"])
        #expect(evaluation.suggestion == ClassificationSuggestion(
            counterpartyAccountID: fixture.food.id,
            cleanedMemo: "Bolt Food"
        ))
        #expect(evaluation.counterpartyWinnerRuleID == specificID)
        #expect(evaluation.memoWinnerRuleID == memoID)
    }

    @Test func evaluationOmitsDisabledNoEffectAndNonmatchingConfigurations() throws {
        let fixture = ClassificationFixture()
        let matchingID = UUID()
        let configurations = [
            ClassificationRuleConfiguration(
                name: "Disabled",
                needle: "bolt",
                cleanedMemo: "Disabled",
                isEnabled: false
            ),
            ClassificationRuleConfiguration(name: "No effect", needle: "bolt"),
            ClassificationRuleConfiguration(name: "Different text", needle: "rimi", cleanedMemo: "Rimi"),
            ClassificationRuleConfiguration(
                id: matchingID,
                name: "Match",
                needle: "bolt",
                cleanedMemo: "Bolt"
            )
        ]

        let evaluation = configurations.evaluate(
            line: fixture.line(description: "BOLT RIDE"),
            current: fixture.draft
        )

        #expect(evaluation.matches.map(\.id) == [matchingID])
        #expect(evaluation.suggestion == ClassificationSuggestion(cleanedMemo: "Bolt"))
        #expect(evaluation.counterpartyWinnerRuleID == nil)
        #expect(evaluation.memoWinnerRuleID == matchingID)
    }

    @Test func descriptionOnlyEvaluationMatchesLineEvaluation() throws {
        let fixture = ClassificationFixture()
        let configurations = [
            ClassificationRuleConfiguration(
                needle: "bolt",
                counterpartyAccountID: fixture.food.id,
                cleanedMemo: "Bolt"
            )
        ]

        let lineEvaluation = configurations.evaluate(
            line: fixture.line(description: "BOLT RIDE"),
            current: fixture.draft
        )
        let descriptionEvaluation = configurations.evaluate(description: "BOLT RIDE")

        #expect(descriptionEvaluation == lineEvaluation)
    }
}

private struct ClassificationFixture {
    let eur = Currency("EUR")
    let now = Date(timeIntervalSince1970: 123_456)
    let bank = Account(name: "LHV", kind: .asset)
    let uncategorized = Account(name: "Uncategorized", kind: .clearing)
    let groceries = Account(name: "Groceries", kind: .expense)
    let food = Account(name: "Food Delivery", kind: .expense)

    var draft: Transaction {
        Transaction.draft(
            memo: "Original",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-12), currency: eur)),
                Posting(accountID: uncategorized.id, money: Money(Decimal(12), currency: eur))
            ]
        )
    }

    var ledger: Ledger {
        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(uncategorized)
        ledger.addAccount(groceries)
        ledger.addAccount(food)
        return ledger
    }

    var pipeline: ImportPipeline {
        ImportPipeline(
            source: "LHV",
            statementAccountID: bank.id,
            defaultCounterpartyAccountID: uncategorized.id
        )
    }

    func line(description: String) -> BankLine {
        BankLine(
            date: Date(timeIntervalSince1970: 100),
            amount: Decimal(-12),
            currency: eur,
            description: description,
            externalID: "CARD-1"
        )
    }
}

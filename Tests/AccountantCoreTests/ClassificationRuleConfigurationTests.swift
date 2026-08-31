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
}

private struct ClassificationFixture {
    let eur = Currency("EUR")
    let now = Date(timeIntervalSince1970: 123_456)
    let bank = Account(name: "LHV", kind: .asset)
    let uncategorized = Account(name: "Uncategorized", kind: .clearing)
    let groceries = Account(name: "Groceries", kind: .expense)
    let food = Account(name: "Food Delivery", kind: .expense)

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

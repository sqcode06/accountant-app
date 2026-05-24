import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

struct ReconciliationSnapshotTests {

    @Test func snapshotReportsMatchedBalance() async throws {
        let fixture = ReconciliationFixture()
        var ledger = fixture.ledger
        let income = try fixture.draftIncome(amount: 100)
        try ledger.addTransaction(income)
        try ledger.finalizeTransaction(id: income.id)

        let snapshot = try ReconciliationSnapshot.make(
            from: ledger,
            accountID: fixture.bank.id,
            statementBalance: 100,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.account.id == fixture.bank.id)
        #expect(snapshot.report.ledgerBalance.amount == 100)
        #expect(snapshot.report.statementBalance.amount == 100)
        #expect(snapshot.report.difference.amount == .zero)
        #expect(snapshot.report.status == .matched)
        #expect(snapshot.isMatched)
        #expect(snapshot.statusTitle == "Matched")
    }

    @Test func snapshotReportsMismatchAndDifference() async throws {
        let fixture = ReconciliationFixture()
        var ledger = fixture.ledger
        let income = try fixture.draftIncome(amount: 100)
        try ledger.addTransaction(income)
        try ledger.finalizeTransaction(id: income.id)

        let snapshot = try ReconciliationSnapshot.make(
            from: ledger,
            accountID: fixture.bank.id,
            statementBalance: 90,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.report.ledgerBalance.amount == 100)
        #expect(snapshot.report.statementBalance.amount == 90)
        #expect(snapshot.report.difference.amount == -10)
        #expect(snapshot.report.status == .mismatched)
        #expect(!snapshot.isMatched)
        #expect(snapshot.statusTitle == "Mismatched")
    }

    @Test func snapshotIgnoresDraftTransactionsByDefault() async throws {
        let fixture = ReconciliationFixture()
        var ledger = fixture.ledger
        try ledger.addTransaction(fixture.draftIncome(amount: 100))

        let snapshot = try ReconciliationSnapshot.make(
            from: ledger,
            accountID: fixture.bank.id,
            statementBalance: 0,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.report.ledgerBalance.amount == .zero)
        #expect(snapshot.report.statementBalance.amount == .zero)
        #expect(snapshot.report.status == .matched)
        #expect(!snapshot.report.includeDrafts)
    }

    @Test func snapshotThrowsForMissingAccount() async throws {
        let fixture = ReconciliationFixture()
        #expect(throws: ReconciliationError.self) {
            _ = try ReconciliationSnapshot.make(
                from: fixture.ledger,
                accountID: AccountID(),
                statementBalance: 0,
                currency: fixture.currency,
                asOf: fixture.asOf
            )
        }
    }
}

private struct ReconciliationFixture {
    let currency = Currency("EUR")
    let date = Date(timeIntervalSinceReferenceDate: 750_000_000)
    let asOf = Date(timeIntervalSinceReferenceDate: 750_000_100)

    let bank = Account(name: "Bank", kind: .asset)
    let salary = Account(name: "Salary", kind: .income)

    var ledger: Ledger {
        makeLedger(with: [bank, salary])
    }

    func money(_ amount: Decimal) -> Money {
        Money(amount, currency: currency)
    }

    func draftIncome(amount: Decimal) throws -> AccountantCore.Transaction {
        try Transaction.draftIncome(
            receivedIn: bank.id,
            source: salary.id,
            amount: money(amount),
            date: date,
            memo: "Salary"
        )
    }
}

private func makeLedger(with accounts: [Account]) -> Ledger {
    var ledger = Ledger()

    for account in accounts {
        ledger.addAccount(account)
    }

    return ledger
}

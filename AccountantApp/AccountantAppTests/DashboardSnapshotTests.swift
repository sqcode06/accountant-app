import Testing
import Foundation
import AccountantCore
@testable import AccountantApp

struct DashboardSnapshotTests {

    @Test func snapshotExcludesArchivedAccountsButCountsThem() async throws {
        let fixture = DashboardFixture()
        var ledger = fixture.ledger
        try ledger.archiveAccount(id: fixture.oldCash.id)

        let snapshot = DashboardSnapshot.make(
            from: ledger,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.archivedAccountCount == 1)
        #expect(snapshot.accountSummaries.contains { $0.account.id == fixture.oldCash.id } == false)
        #expect(snapshot.accountSummaries.contains { $0.account.id == fixture.bank.id })
        #expect(snapshot.heroSubtitle == "6 active accounts · 1 archived")
        #expect(snapshot.accountCountCaption(for: .asset) == "1 account")
    }

    @Test func snapshotIgnoresDraftTransactionsAndIncludesFinalizedTransactions() async throws {
        let fixture = DashboardFixture()
        var ledger = fixture.ledger

        let draftExpense = try Transaction.draftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: fixture.money(42),
            date: fixture.transactionDate,
            memo: "Draft groceries"
        )
        try ledger.addTransaction(draftExpense)

        var snapshot = DashboardSnapshot.make(
            from: ledger,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.kindAmount(.asset) == .zero)
        #expect(snapshot.kindAmount(.expense) == .zero)

        let income = try Transaction.draftIncome(
            receivedIn: fixture.bank.id,
            source: fixture.salary.id,
            amount: fixture.money(1000),
            date: fixture.transactionDate,
            memo: "Salary"
        )
        try ledger.addTransaction(income)
        try ledger.finalizeTransaction(id: income.id)

        snapshot = DashboardSnapshot.make(
            from: ledger,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.kindAmount(.asset) == 1000)
        #expect(snapshot.kindAmount(.income) == -1000)
        #expect(snapshot.userFacingAmount(for: .income) == 1000)
    }

    @Test func snapshotCalculatesNetPositionFromAssetsAndLiabilities() async throws {
        let fixture = DashboardFixture()
        var ledger = fixture.ledger

        let salary = try Transaction.draftIncome(
            receivedIn: fixture.bank.id,
            source: fixture.salary.id,
            amount: fixture.money(1000),
            date: fixture.transactionDate,
            memo: "Salary"
        )
        try ledger.addTransaction(salary)
        try ledger.finalizeTransaction(id: salary.id)

        let creditCardExpense = try Transaction.draftExpense(
            paidFrom: fixture.creditCard.id,
            category: fixture.groceries.id,
            amount: fixture.money(120),
            date: fixture.transactionDate,
            memo: "Card groceries"
        )
        try ledger.addTransaction(creditCardExpense)
        try ledger.finalizeTransaction(id: creditCardExpense.id)

        let snapshot = DashboardSnapshot.make(
            from: ledger,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.kindAmount(.asset) == 1000)
        #expect(snapshot.kindAmount(.liability) == -120)
        #expect(snapshot.assetLiabilityAmount == 880)
    }

    @Test func snapshotUsesCatalogOrderingForKindSummaries() async throws {
        let fixture = DashboardFixture()

        let snapshot = DashboardSnapshot.make(
            from: fixture.ledger,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.kindSummaries.map(\.kind) == AccountKindCatalog.all)
    }

    @Test func snapshotBuildsUserFacingCaptions() async throws {
        let fixture = DashboardFixture()
        var ledger = fixture.ledger
        try ledger.archiveAccount(id: fixture.oldCash.id)

        let snapshot = DashboardSnapshot.make(
            from: ledger,
            currency: fixture.currency,
            asOf: fixture.asOf
        )

        #expect(snapshot.activeAccountCount == 6)
        #expect(snapshot.heroSubtitle == "6 active accounts · 1 archived")
        #expect(snapshot.accountCountCaption(for: .asset) == "1 account")
        #expect(snapshot.accountCountCaption(for: .equity) == "1 account")
    }
}

private struct DashboardFixture {
    let currency = Currency("EUR")
    let transactionDate = Date(timeIntervalSinceReferenceDate: 750_000_000)
    let asOf = Date(timeIntervalSinceReferenceDate: 750_000_100)

    let bank = Account(name: "Bank", kind: .asset)
    let creditCard = Account(name: "Credit card", kind: .liability)
    let salary = Account(name: "Salary", kind: .income)
    let groceries = Account(name: "Groceries", kind: .expense)
    let equity = Account(name: "Opening equity", kind: .equity)
    let clearing = Account(name: "Import clearing", kind: .clearing)
    let oldCash = Account(name: "Old cash", kind: .asset)

    var ledger: Ledger {
        makeLedger(with: [
            salary,
            groceries,
            bank,
            equity,
            clearing,
            creditCard,
            oldCash
        ])
    }

    func money(_ amount: Decimal) -> Money {
        Money(amount, currency: currency)
    }
}

private func makeLedger(with accounts: [Account]) -> Ledger {
    var ledger = Ledger()

    for account in accounts {
        ledger.addAccount(account)
    }

    return ledger
}

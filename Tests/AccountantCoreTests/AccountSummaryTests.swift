import XCTest
@testable import AccountantCore

final class AccountSummaryTests: XCTestCase {
    func testAccountBalanceSummariesReturnActiveAccountsWithBalancesInDeterministicOrder() throws {
        let fixture = try makeFixture()
        let summaries = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(summaries.map { $0.account.name }, ["Bank", "Cash", "Groceries", "Salary"])
        XCTAssertEqual(summaries.map { $0.account.kind }, [.asset, .asset, .expense, .income])

        XCTAssertEqual(summary(named: "Bank", in: summaries)?.balance, Money(Decimal(845), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Cash", in: summaries)?.balance, Money(Decimal(100), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Groceries", in: summaries)?.balance, Money(Decimal(40), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Salary", in: summaries)?.balance, Money(Decimal(-1000), currency: fixture.eur))
    }

    func testAccountBalanceSummariesExcludeDraftsByDefaultButCanIncludeThem() throws {
        var fixture = try makeFixture()

        let draft = try Transaction.draftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: Money(Decimal(10), currency: fixture.eur),
            date: Date(timeIntervalSince1970: 150),
            memo: "Draft snack"
        )
        try fixture.ledger.addTransaction(draft)

        let finalizedOnly = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        let withDrafts = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200),
            includeDrafts: true
        )

        XCTAssertEqual(summary(named: "Bank", in: finalizedOnly)?.balance, Money(Decimal(845), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Groceries", in: finalizedOnly)?.balance, Money(Decimal(40), currency: fixture.eur))

        XCTAssertEqual(summary(named: "Bank", in: withDrafts)?.balance, Money(Decimal(835), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Groceries", in: withDrafts)?.balance, Money(Decimal(50), currency: fixture.eur))
    }

    func testAccountBalanceSummariesRespectAsOfDate() throws {
        var fixture = try makeFixture()

        let laterExpense = try Transaction.draftExpense(
            paidFrom: fixture.bank.id,
            category: fixture.groceries.id,
            amount: Money(Decimal(25), currency: fixture.eur),
            date: Date(timeIntervalSince1970: 300),
            memo: "Later groceries"
        )
        try fixture.ledger.addTransaction(laterExpense)
        try fixture.ledger.finalizeTransaction(id: laterExpense.id, now: Date(timeIntervalSince1970: 301))

        let beforeLaterTransaction = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        let afterLaterTransaction = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(summary(named: "Bank", in: beforeLaterTransaction)?.balance, Money(Decimal(845), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Groceries", in: beforeLaterTransaction)?.balance, Money(Decimal(40), currency: fixture.eur))

        XCTAssertEqual(summary(named: "Bank", in: afterLaterTransaction)?.balance, Money(Decimal(820), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Groceries", in: afterLaterTransaction)?.balance, Money(Decimal(65), currency: fixture.eur))
    }

    func testAccountBalanceSummariesExcludeArchivedAccountsByDefaultButCanIncludeThem() throws {
        let fixture = try makeFixture()

        let activeOnly = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        let includingArchived = fixture.ledger.accountBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200),
            includeArchived: true
        )

        XCTAssertNil(summary(named: "Old Dining", in: activeOnly))
        XCTAssertEqual(summary(named: "Old Dining", in: includingArchived)?.account.status, .archived)
        XCTAssertEqual(summary(named: "Old Dining", in: includingArchived)?.balance, Money(Decimal(15), currency: fixture.eur))

        // Archived account rows are hidden by default, but their historical postings still affect active accounts.
        XCTAssertEqual(summary(named: "Bank", in: activeOnly)?.balance, Money(Decimal(845), currency: fixture.eur))
    }

    func testAccountBalanceSummariesFilterByKind() throws {
        let fixture = try makeFixture()

        let assets = fixture.ledger.accountBalanceSummaries(
            kind: .asset,
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        let expenses = fixture.ledger.accountBalanceSummaries(
            kind: .expense,
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(assets.map { $0.account.name }, ["Bank", "Cash"])
        XCTAssertEqual(summary(named: "Bank", in: assets)?.balance, Money(Decimal(845), currency: fixture.eur))
        XCTAssertEqual(summary(named: "Cash", in: assets)?.balance, Money(Decimal(100), currency: fixture.eur))

        XCTAssertEqual(expenses.map { $0.account.name }, ["Groceries"])
        XCTAssertEqual(summary(named: "Groceries", in: expenses)?.balance, Money(Decimal(40), currency: fixture.eur))
    }

    func testAccountBalanceSummariesUseRequestedCurrencyOnly() throws {
        let fixture = try makeFixture()

        let usdSummaries = fixture.ledger.accountBalanceSummaries(
            currency: fixture.usd,
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(summary(named: "Bank", in: usdSummaries)?.balance, Money(Decimal(50), currency: fixture.usd))
        XCTAssertEqual(summary(named: "Salary", in: usdSummaries)?.balance, Money(Decimal(-50), currency: fixture.usd))
        XCTAssertEqual(summary(named: "Cash", in: usdSummaries)?.balance, Money(Decimal(0), currency: fixture.usd))
        XCTAssertEqual(summary(named: "Groceries", in: usdSummaries)?.balance, Money(Decimal(0), currency: fixture.usd))
    }

    func testAccountKindBalanceSummariesAggregateBalancesAndCounts() throws {
        let fixture = try makeFixture()

        let summaries = fixture.ledger.accountKindBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(summaries.map { $0.kind }, [.asset, .expense, .income])

        XCTAssertEqual(kindSummary(.asset, in: summaries)?.balance, Money(Decimal(945), currency: fixture.eur))
        XCTAssertEqual(kindSummary(.asset, in: summaries)?.accountCount, 2)

        XCTAssertEqual(kindSummary(.expense, in: summaries)?.balance, Money(Decimal(40), currency: fixture.eur))
        XCTAssertEqual(kindSummary(.expense, in: summaries)?.accountCount, 1)

        XCTAssertEqual(kindSummary(.income, in: summaries)?.balance, Money(Decimal(-1000), currency: fixture.eur))
        XCTAssertEqual(kindSummary(.income, in: summaries)?.accountCount, 1)
    }

    func testAccountKindBalanceSummariesCanIncludeArchivedAccounts() throws {
        let fixture = try makeFixture()

        let summaries = fixture.ledger.accountKindBalanceSummaries(
            currency: fixture.eur,
            asOf: Date(timeIntervalSince1970: 200),
            includeArchived: true
        )

        XCTAssertEqual(kindSummary(.expense, in: summaries)?.balance, Money(Decimal(55), currency: fixture.eur))
        XCTAssertEqual(kindSummary(.expense, in: summaries)?.accountCount, 2)
    }

    private func makeFixture() throws -> AccountSummaryFixture {
        try AccountSummaryFixture()
    }

    private func summary(named name: String, in summaries: [AccountBalanceSummary]) -> AccountBalanceSummary? {
        summaries.first { $0.account.name == name }
    }

    private func kindSummary(_ kind: AccountKind, in summaries: [AccountKindBalanceSummary]) -> AccountKindBalanceSummary? {
        summaries.first { $0.kind == kind }
    }
}

private struct AccountSummaryFixture {
    let eur: Currency
    let usd: Currency
    var ledger: Ledger
    let bank: Account
    let cash: Account
    let groceries: Account
    let oldDining: Account
    let salary: Account

    init() throws {
        eur = Currency("EUR")
        usd = Currency("USD")

        bank = Account(name: "Bank", kind: .asset)
        cash = Account(name: "Cash", kind: .asset)
        groceries = Account(name: "Groceries", kind: .expense)
        oldDining = Account(name: "Old Dining", kind: .expense)
        salary = Account(name: "Salary", kind: .income)

        var ledger = Ledger()
        ledger.addAccount(bank)
        ledger.addAccount(cash)
        ledger.addAccount(groceries)
        ledger.addAccount(oldDining)
        ledger.addAccount(salary)

        let eurIncome = try Transaction.draftIncome(
            receivedIn: bank.id,
            source: salary.id,
            amount: Money(Decimal(1000), currency: eur),
            date: Date(timeIntervalSince1970: 100),
            memo: "EUR salary"
        )

        let eurExpense = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: groceries.id,
            amount: Money(Decimal(40), currency: eur),
            date: Date(timeIntervalSince1970: 110),
            memo: "Groceries"
        )

        let transfer = try Transaction.draftTransfer(
            from: bank.id,
            to: cash.id,
            amount: Money(Decimal(100), currency: eur),
            date: Date(timeIntervalSince1970: 120),
            memo: "ATM withdrawal"
        )

        let archivedExpense = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: oldDining.id,
            amount: Money(Decimal(15), currency: eur),
            date: Date(timeIntervalSince1970: 130),
            memo: "Old dining"
        )

        let usdIncome = try Transaction.draftIncome(
            receivedIn: bank.id,
            source: salary.id,
            amount: Money(Decimal(50), currency: usd),
            date: Date(timeIntervalSince1970: 140),
            memo: "USD salary"
        )

        for tx in [eurIncome, eurExpense, transfer, archivedExpense, usdIncome] {
            try ledger.addTransaction(tx)
            try ledger.finalizeTransaction(id: tx.id, now: Date(timeIntervalSince1970: 150))
        }

        try ledger.archiveAccount(id: oldDining.id)

        self.ledger = ledger
    }
}
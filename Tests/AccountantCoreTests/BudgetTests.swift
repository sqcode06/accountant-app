import XCTest
@testable import AccountantCore

final class BudgetTests: XCTestCase {

    private let eur = Currency("EUR")

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let august = BudgetPeriod(year: 2026, month: 8)

    private struct Fixture {
        var ledger: Ledger
        let bank: Account
        let groceries: Account
        let eatingOut: Account
        let salary: Account
    }

    private func makeFixture() -> Fixture {
        var ledger = Ledger()

        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        let eatingOut = Account(name: "Eating out", kind: .expense)
        let salary = Account(name: "Salary", kind: .income)

        for account in [bank, groceries, eatingOut, salary] {
            ledger.addAccount(account)
        }

        return Fixture(
            ledger: ledger,
            bank: bank,
            groceries: groceries,
            eatingOut: eatingOut,
            salary: salary
        )
    }

    private func date(_ day: Int, month: Int = 8, year: Int = 2026) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @discardableResult
    private func spend(
        _ amount: Decimal,
        on category: Account,
        from bank: Account,
        day: Int,
        month: Int = 8,
        in ledger: inout Ledger,
        finalize: Bool = true
    ) throws -> TransactionID {
        let tx = try Transaction.draftExpense(
            paidFrom: bank.id,
            category: category.id,
            amount: Money(amount, currency: eur),
            date: date(day, month: month)
        )

        try ledger.addTransaction(tx)
        if finalize { try ledger.finalizeTransaction(id: tx.id) }

        return tx.id
    }

    // MARK: - Setting targets

    func testSettingATargetMakesItApplyFromThatMonthOnward() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        XCTAssertEqual(budget.target(for: fixture.groceries.id, in: august)?.amount.amount, Decimal(300))
        XCTAssertEqual(budget.target(for: fixture.groceries.id, in: august.next)?.amount.amount, Decimal(300))
        XCTAssertNil(budget.target(for: fixture.groceries.id, in: august.previous))
    }

    func testRejectsNonPositiveTarget() throws {
        let fixture = makeFixture()
        var budget = Budget()

        XCTAssertThrowsError(
            try budget.setTarget(
                amount: Money(Decimal(0), currency: eur),
                for: fixture.groceries.id,
                from: august,
                in: fixture.ledger
            )
        ) { error in
            XCTAssertEqual(error as? BudgetError, .nonPositiveAmount(Money(Decimal(0), currency: eur)))
        }
    }

    func testRejectsBudgetingANonExpenseAccount() throws {
        let fixture = makeFixture()
        var budget = Budget()

        // A bank account holds a balance; it does not have a monthly allowance.
        XCTAssertThrowsError(
            try budget.setTarget(
                amount: Money(Decimal(300), currency: eur),
                for: fixture.bank.id,
                from: august,
                in: fixture.ledger
            )
        ) { error in
            XCTAssertEqual(error as? BudgetError, .accountNotBudgetable(fixture.bank.id))
        }

        XCTAssertThrowsError(
            try budget.setTarget(
                amount: Money(Decimal(300), currency: eur),
                for: fixture.salary.id,
                from: august,
                in: fixture.ledger
            )
        )
    }

    func testRejectsUnknownAccount() throws {
        let fixture = makeFixture()
        var budget = Budget()

        XCTAssertThrowsError(
            try budget.setTarget(
                amount: Money(Decimal(300), currency: eur),
                for: AccountID(),
                from: august,
                in: fixture.ledger
            )
        )
    }

    // MARK: - Changing targets over time

    func testRaisingATargetLeavesEarlierMonthsReportingTheOldLimit() throws {
        let fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )
        try budget.setTarget(
            amount: Money(Decimal(400), currency: eur),
            for: fixture.groceries.id,
            from: august.next,
            in: fixture.ledger
        )

        // History stays honest: August still knows it planned 300.
        XCTAssertEqual(budget.target(for: fixture.groceries.id, in: august)?.amount.amount, Decimal(300))
        XCTAssertEqual(budget.target(for: fixture.groceries.id, in: august.next)?.amount.amount, Decimal(400))
        XCTAssertEqual(budget.target(for: fixture.groceries.id, in: august.next.next)?.amount.amount, Decimal(400))
    }

    func testExactlyOneTargetAppliesPerMonth() throws {
        let fixture = makeFixture()
        var budget = Budget()

        for amount in [Decimal(100), Decimal(200), Decimal(300)] {
            try budget.setTarget(
                amount: Money(amount, currency: eur),
                for: fixture.groceries.id,
                from: august,
                in: fixture.ledger
            )
        }

        // Repeatedly setting the same month must not stack overlapping targets.
        XCTAssertEqual(budget.targets(in: august).count, 1)
        XCTAssertEqual(budget.target(for: fixture.groceries.id, in: august)?.amount.amount, Decimal(300))
    }

    func testRemovingATargetStopsItWithoutErasingHistory() throws {
        let fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )
        budget.removeTarget(for: fixture.groceries.id, from: august.next)

        XCTAssertNotNil(budget.target(for: fixture.groceries.id, in: august))
        XCTAssertNil(budget.target(for: fixture.groceries.id, in: august.next))
    }

    func testForgettingAnAccountErasesItEntirely() throws {
        let fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )
        budget.forget(accountID: fixture.groceries.id)

        XCTAssertTrue(budget.targets.isEmpty)
        XCTAssertNil(budget.target(for: fixture.groceries.id, in: august))
    }

    // MARK: - Reporting

    func testReportComparesSpendingAgainstTheTarget() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        try spend(Decimal(118), on: fixture.groceries, from: fixture.bank, day: 5, in: &fixture.ledger)

        let report = fixture.ledger.budgetReport(
            budget: budget,
            period: august,
            currency: eur,
            calendar: utc
        )

        let line = try XCTUnwrap(report.lines.first)
        XCTAssertEqual(line.spent.amount, Decimal(118))
        XCTAssertEqual(line.target.amount, Decimal(300))
        XCTAssertEqual(line.remaining.amount, Decimal(182))
        XCTAssertFalse(line.isOverspent)
        XCTAssertNil(line.overspend)
        XCTAssertEqual(line.progress, 118.0 / 300.0, accuracy: 0.0001)
    }

    func testOverspendIsReportedWithTheAmountPastTheLimit() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(100), currency: eur),
            for: fixture.eatingOut.id,
            from: august,
            in: fixture.ledger
        )

        try spend(Decimal(112), on: fixture.eatingOut, from: fixture.bank, day: 9, in: &fixture.ledger)

        let report = fixture.ledger.budgetReport(
            budget: budget,
            period: august,
            currency: eur,
            calendar: utc
        )

        let line = try XCTUnwrap(report.lines.first)
        XCTAssertTrue(line.isOverspent)
        XCTAssertEqual(line.overspend?.amount, Decimal(12))
        XCTAssertEqual(line.remaining.amount, Decimal(-12))
        XCTAssertGreaterThan(line.progress, 1.0)

        XCTAssertFalse(report.isWithinBudget)
        XCTAssertEqual(report.overspentLines.count, 1)
    }

    func testSpendingOutsideThePeriodIsExcluded() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        try spend(Decimal(50), on: fixture.groceries, from: fixture.bank, day: 31, month: 7, in: &fixture.ledger)
        try spend(Decimal(118), on: fixture.groceries, from: fixture.bank, day: 5, month: 8, in: &fixture.ledger)
        try spend(Decimal(70), on: fixture.groceries, from: fixture.bank, day: 1, month: 9, in: &fixture.ledger)

        let report = fixture.ledger.budgetReport(
            budget: budget,
            period: august,
            currency: eur,
            calendar: utc
        )

        XCTAssertEqual(report.lines.first?.spent.amount, Decimal(118))
    }

    func testDraftsCountTowardSpendingByDefault() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        try spend(
            Decimal(40),
            on: fixture.groceries,
            from: fixture.bank,
            day: 5,
            in: &fixture.ledger,
            finalize: false
        )

        // An unfinalized purchase is still money that left. A budget that ignores
        // it flatters you.
        let included = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, calendar: utc
        )
        XCTAssertEqual(included.lines.first?.spent.amount, Decimal(40))

        let excluded = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, includeDrafts: false, calendar: utc
        )
        XCTAssertEqual(excluded.lines.first?.spent.amount, Decimal.zero)
    }

    func testRefundReducesSpendingAndNeverDrivesProgressNegative() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        try spend(Decimal(50), on: fixture.groceries, from: fixture.bank, day: 5, in: &fixture.ledger)

        // A refund: money back into the bank, out of the category.
        let refund = try Transaction.draftIncome(
            receivedIn: fixture.bank.id,
            source: fixture.groceries.id,
            amount: Money(Decimal(80), currency: eur),
            date: date(6)
        )
        try fixture.ledger.addTransaction(refund)
        try fixture.ledger.finalizeTransaction(id: refund.id)

        let report = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, calendar: utc
        )

        let line = try XCTUnwrap(report.lines.first)
        XCTAssertEqual(line.spent.amount, Decimal(-30))
        XCTAssertEqual(line.progress, 0, "A net refund must not render a negative bar")
    }

    // MARK: - Unbudgeted spending

    func testSpendingInAnUnbudgetedCategoryIsSurfacedSeparately() throws {
        var fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        try spend(Decimal(118), on: fixture.groceries, from: fixture.bank, day: 5, in: &fixture.ledger)
        try spend(Decimal(112), on: fixture.eatingOut, from: fixture.bank, day: 9, in: &fixture.ledger)

        let report = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, calendar: utc
        )

        XCTAssertEqual(report.lines.count, 1)
        XCTAssertEqual(report.unbudgeted.count, 1)
        XCTAssertEqual(report.unbudgeted.first?.account.name, "Eating out")
        XCTAssertEqual(report.unbudgetedSpent.amount, Decimal(112))

        // Totals keep the two kinds of spending distinguishable.
        XCTAssertEqual(report.totalSpent.amount, Decimal(118))
        XCTAssertEqual(report.totalSpentIncludingUnbudgeted.amount, Decimal(230))
        XCTAssertEqual(report.totalRemaining.amount, Decimal(182))
    }

    func testCategoriesWithNoSpendAndNoTargetAreNotListed() throws {
        var fixture = makeFixture()
        let budget = Budget()

        try spend(Decimal(10), on: fixture.groceries, from: fixture.bank, day: 5, in: &fixture.ledger)

        let report = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, calendar: utc
        )

        XCTAssertEqual(report.unbudgeted.map(\.account.name), ["Groceries"])
    }

    func testOrderingIsDeterministicByName() throws {
        var fixture = makeFixture()
        var budget = Budget()

        for category in [fixture.eatingOut, fixture.groceries] {
            try budget.setTarget(
                amount: Money(Decimal(100), currency: eur),
                for: category.id,
                from: august,
                in: fixture.ledger
            )
        }

        let report = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, calendar: utc
        )

        XCTAssertEqual(report.lines.map(\.account.name), ["Eating out", "Groceries"])
    }

    // MARK: - Currency

    func testSpendingInAnotherCurrencyDoesNotCountTowardThisBudget() throws {
        var fixture = makeFixture()
        var budget = Budget()
        let usd = Currency("USD")

        let usdBank = Account(name: "USD Bank", kind: .asset, currency: usd)
        fixture.ledger.addAccount(usdBank)

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        let dollarSpend = try Transaction.draftExpense(
            paidFrom: usdBank.id,
            category: fixture.groceries.id,
            amount: Money(Decimal(75), currency: usd),
            date: date(5)
        )
        try fixture.ledger.addTransaction(dollarSpend)
        try fixture.ledger.finalizeTransaction(id: dollarSpend.id)

        let report = fixture.ledger.budgetReport(
            budget: budget, period: august, currency: eur, calendar: utc
        )

        // No implicit conversion anywhere in this app.
        XCTAssertEqual(report.lines.first?.spent.amount, Decimal.zero)
    }

    // MARK: - Persistence

    func testBudgetRoundTripsThroughCoding() throws {
        let fixture = makeFixture()
        var budget = Budget()

        try budget.setTarget(
            amount: Money(Decimal(300), currency: eur),
            for: fixture.groceries.id,
            from: august,
            in: fixture.ledger
        )

        let data = try JSONEncoder().encode(budget)
        let decoded = try JSONDecoder().decode(Budget.self, from: data)

        XCTAssertEqual(decoded, budget)
        XCTAssertEqual(decoded.target(for: fixture.groceries.id, in: august)?.amount.amount, Decimal(300))
    }
}

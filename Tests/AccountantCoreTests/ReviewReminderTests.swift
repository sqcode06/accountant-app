import XCTest
@testable import AccountantCore

/// When to nudge someone about their review queue, and what to say.
///
/// The failure that matters most here is firing when there is nothing to review.
/// That is the notification people turn off, and once it is off the capture loop
/// quietly stops working.
final class ReviewReminderTests: XCTestCase {

    private let eur = Currency("EUR")

    /// Fixed zone so day boundaries do not depend on where the test runs.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Tallinn")!
        return calendar
    }()

    /// 2024-03-05 20:00 Tallinn — an ordinary evening reminder time.
    private let now = Date(timeIntervalSince1970: 1_709_661_600)

    private func makeLedger() -> (ledger: Ledger, bank: Account, groceries: Account) {
        var ledger = Ledger()
        let bank = Account(name: "Swedbank", kind: .asset, currency: eur)
        let groceries = Account(name: "Groceries", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(groceries)
        return (ledger, bank, groceries)
    }

    @discardableResult
    private func addDraft(
        to ledger: inout Ledger,
        bank: Account,
        groceries: Account,
        capturedAt: Date,
        finalize: Bool = false
    ) throws -> Transaction {
        let tx = Transaction(
            date: capturedAt,
            memo: "Rimi",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(10), currency: eur))
            ],
            state: .draft,
            createdAt: capturedAt
        )

        try ledger.addTransaction(tx)

        if finalize {
            try ledger.finalizeTransaction(id: tx.id)
        }

        return tx
    }

    private func daysBefore(_ count: Int) -> Date {
        calendar.date(byAdding: .day, value: -count, to: now)!
    }

    // MARK: - When not to fire

    func testEmptyLedgerDoesNotRemind() {
        XCTAssertEqual(
            ReviewReminder.decide(for: Ledger(), now: now, calendar: calendar),
            .nothingToReview
        )
    }

    /// The one that keeps the notification from becoming noise.
    func testLedgerWithOnlyConfirmedEntriesDoesNotRemind() throws {
        var (ledger, bank, groceries) = makeLedger()
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now, finalize: true)

        XCTAssertEqual(
            ReviewReminder.decide(for: ledger, now: now, calendar: calendar),
            .nothingToReview
        )
    }

    func testConfirmingTheLastDraftStopsTheReminder() throws {
        var (ledger, bank, groceries) = makeLedger()
        let draft = try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now)

        guard case .remind = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder while a draft is waiting")
        }

        try ledger.finalizeTransaction(id: draft.id)

        XCTAssertEqual(
            ReviewReminder.decide(for: ledger, now: now, calendar: calendar),
            .nothingToReview
        )
    }

    // MARK: - Counting

    func testCountsOnlyDrafts() throws {
        var (ledger, bank, groceries) = makeLedger()
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now)
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now)
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now, finalize: true)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        XCTAssertEqual(reminder.draftCount, 2)
        XCTAssertEqual(reminder.title, "2 entries to review")
    }

    func testSingleDraftReadsAsSingular() throws {
        var (ledger, bank, groceries) = makeLedger()
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        XCTAssertEqual(reminder.title, "1 entry to review")
    }

    // MARK: - Age

    func testEntriesCapturedTodayReadAsToday() throws {
        var (ledger, bank, groceries) = makeLedger()

        // Earlier the same day, not 24 hours ago.
        let thisMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: thisMorning)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        XCTAssertEqual(reminder.oldestDraftAgeInDays, 0)
        XCTAssertEqual(reminder.body, "Check what you captured today and confirm it.")
    }

    func testAgeComesFromTheOldestDraft() throws {
        var (ledger, bank, groceries) = makeLedger()
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: daysBefore(3))
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: now)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        XCTAssertEqual(reminder.draftCount, 2)
        XCTAssertEqual(reminder.oldestDraftAgeInDays, 3)
        XCTAssertEqual(reminder.body, "The oldest has been waiting 3 days.")
    }

    func testWordingChangesWithAge() throws {
        let cases: [(days: Int, expected: String)] = [
            (1, "Some of these have been waiting since yesterday."),
            (2, "The oldest has been waiting 2 days."),
            (6, "The oldest has been waiting 6 days."),
            (7, "A few have been waiting over a week."),
            (40, "A few have been waiting over a week.")
        ]

        for testCase in cases {
            var (ledger, bank, groceries) = makeLedger()
            try addDraft(
                to: &ledger,
                bank: bank,
                groceries: groceries,
                capturedAt: daysBefore(testCase.days)
            )

            guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
                return XCTFail("Expected a reminder at \(testCase.days) days")
            }

            XCTAssertEqual(reminder.oldestDraftAgeInDays, testCase.days)
            XCTAssertEqual(reminder.body, testCase.expected, "at \(testCase.days) days")
        }
    }

    /// Age is measured from when it was captured, not the date written on it.
    ///
    /// Backdating a transaction to last month is ordinary — entering a receipt you
    /// found in a coat pocket. That entry has been waiting minutes, not weeks, and
    /// saying otherwise would make the reminder read as nagging about something the
    /// user just did.
    func testBackdatedEntriesAreNotTreatedAsOld() throws {
        var (ledger, bank, groceries) = makeLedger()

        let capturedNow = now
        let writtenFor = daysBefore(30)

        let tx = Transaction(
            date: writtenFor,
            memo: "Receipt from a coat pocket",
            postings: [
                Posting(accountID: bank.id, money: Money(Decimal(-10), currency: eur)),
                Posting(accountID: groceries.id, money: Money(Decimal(10), currency: eur))
            ],
            state: .draft,
            createdAt: capturedNow
        )
        try ledger.addTransaction(tx)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        XCTAssertEqual(reminder.oldestDraftAgeInDays, 0)
    }

    /// A capture timestamped slightly in the future must not read as ancient.
    func testFutureCaptureDoesNotProduceANegativeAge() throws {
        var (ledger, bank, groceries) = makeLedger()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: tomorrow)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        XCTAssertEqual(reminder.oldestDraftAgeInDays, 0)
        XCTAssertEqual(reminder.body, "Check what you captured today and confirm it.")
    }

    /// Day arithmetic has to respect the calendar, not assume 86,400-second days.
    func testAgeIsCorrectAcrossADaylightSavingChange() throws {
        var (ledger, bank, groceries) = makeLedger()

        // Tallinn springs forward on 2024-03-31. 2024-04-01 20:00 local.
        let afterChange = Date(timeIntervalSince1970: 1_711_990_800)
        let twoDaysBefore = calendar.date(byAdding: .day, value: -2, to: afterChange)!

        try addDraft(to: &ledger, bank: bank, groceries: groceries, capturedAt: twoDaysBefore)

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: afterChange, calendar: calendar) else {
            return XCTFail("Expected a reminder")
        }

        // A 23-hour day sits in this range; dividing elapsed seconds by 86,400
        // would report 1.
        XCTAssertEqual(reminder.oldestDraftAgeInDays, 2)
    }
}

import Foundation
import Testing
import AccountantCore
@testable import AccountantApp

@Suite(.serialized)
@MainActor
struct ReviewReminderControllerTests {
    private let now = Date(timeIntervalSince1970: 1_757_847_600) // 2025-09-14 12:00 UTC

    @Test func replacesTheOneShotWithTheLatestDraftCountAndCancelsWhenEmpty() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        var ledgerFixture = makeLedger()
        let first = try addDraft(to: &ledgerFixture, capturedAt: now)

        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(fixture.service.pendingRequest?.title == "1 entry to review")

        let second = try addDraft(to: &ledgerFixture, capturedAt: now)
        controller.refresh(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(fixture.service.pendingRequest?.title == "2 entries to review")

        try ledgerFixture.ledger.finalizeTransaction(id: first.id)
        try ledgerFixture.ledger.finalizeTransaction(id: second.id)
        controller.refresh(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()

        #expect(fixture.service.pendingRequest == nil)
        #expect(fixture.service.maximumPendingCount == 1)
    }

    @Test func sameCountQueueReplacementRefreshesTheOldestDraftWording() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let controller = makeController(defaults: fixture.defaults, service: fixture.service)

        var recent = makeLedger()
        try addDraft(to: &recent, capturedAt: now)
        await controller.refreshAuthorization(for: recent.ledger)
        await controller.waitForPendingUpdates()
        #expect(fixture.service.pendingRequest?.body == "Check what you captured today and confirm it.")

        var older = makeLedger()
        let threeDaysAgo = try #require(
            calendar(timeZone: "Europe/Tallinn").date(byAdding: .day, value: -3, to: now)
        )
        try addDraft(to: &older, capturedAt: threeDaysAgo)
        controller.refresh(for: older.ledger)
        await controller.waitForPendingUpdates()

        #expect(fixture.service.pendingRequest?.title == "1 entry to review")
        #expect(fixture.service.pendingRequest?.body == "The oldest has been waiting 3 days.")
    }

    @Test func disableWinsWhenAnOlderAddIsStillInFlight() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        await controller.refreshAuthorization(for: Ledger())
        await controller.waitForPendingUpdates()

        fixture.service.blockNextReplacement = true
        controller.refresh(for: ledgerFixture.ledger)
        try await fixture.service.waitUntilReplacementIsBlocked()

        controller.disable()
        fixture.service.releaseBlockedReplacement()
        await controller.waitForPendingUpdates()

        #expect(fixture.service.pendingRequest == nil)
        #expect(!controller.isEnabled)
        #expect(fixture.defaults.bool(forKey: "reviewReminderEnabled") == false)
    }

    @Test func disableWinsWhenAnOlderPermissionCheckIsStillInFlight() async throws {
        let fixture = makeFixture(isEnabled: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.blockNextAuthorizationCheck = true

        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        let enabling = Task { @MainActor in await controller.enable() }
        try await fixture.service.waitUntilAuthorizationCheckIsBlocked()

        controller.disable()
        fixture.service.releaseBlockedAuthorizationCheck()
        await enabling.value
        await controller.waitForPendingUpdates()

        #expect(!controller.isEnabled)
        #expect(fixture.defaults.bool(forKey: "reviewReminderEnabled") == false)
        #expect(fixture.service.pendingRequest == nil)
    }

    @Test func authorizationCompletionUsesTheNewestQueue() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.blockNextAuthorizationCheck = true

        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        let firstLedger = ledgerFixture.ledger
        let checking = Task {
            await controller.refreshAuthorization(for: firstLedger)
        }
        try await fixture.service.waitUntilAuthorizationCheckIsBlocked()

        try addDraft(to: &ledgerFixture, capturedAt: now)
        controller.refresh(for: ledgerFixture.ledger)
        fixture.service.releaseBlockedAuthorizationCheck()
        await checking.value
        await controller.waitForPendingUpdates()

        #expect(fixture.service.pendingRequest?.title == "2 entries to review")
    }

    @Test func lateForegroundPermissionReadCannotOverwriteANewerRead() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.status = .denied
        fixture.service.blockNextAuthorizationCheck = true

        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        let olderRead = Task {
            await controller.refreshAuthorization(for: Ledger())
        }
        try await fixture.service.waitUntilAuthorizationCheckIsBlocked()

        fixture.service.status = .authorized
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        fixture.service.releaseBlockedAuthorizationCheck()
        await olderRead.value
        await controller.waitForPendingUpdates()

        #expect(controller.authorizationStatus == .authorized)
        #expect(controller.isEnabled)
        #expect(fixture.service.pendingRequest?.title == "1 entry to review")
    }

    @Test func foregroundRefreshFollowsSystemPermissionButPreservesUserChoice() async throws {
        let wanted = makeFixture(isEnabled: true)
        defer { wanted.defaults.removePersistentDomain(forName: wanted.suiteName) }

        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let controller = makeController(defaults: wanted.defaults, service: wanted.service)

        wanted.service.status = .denied
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(!controller.isEnabled)
        #expect(controller.statusMessage?.contains("iOS Settings") == true)
        #expect(wanted.service.pendingRequest == nil)

        wanted.service.status = .authorized
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(controller.isEnabled)
        #expect(wanted.service.pendingRequest != nil)

        controller.disable()
        await controller.waitForPendingUpdates()
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(!controller.isEnabled)
        #expect(wanted.service.pendingRequest == nil)
    }

    @Test func deniedIntentCanBeTurnedOffAndStaysOffAfterAuthorizationAndReload() async throws {
        let fixture = makeFixture(isEnabled: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.status = .denied

        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        await controller.enable()
        await controller.waitForPendingUpdates()
        #expect(controller.wantsReminders)
        #expect(!controller.isEnabled)
        #expect(fixture.defaults.bool(forKey: "reviewReminderEnabled"))

        controller.disable()
        await controller.waitForPendingUpdates()
        #expect(!controller.wantsReminders)
        #expect(!fixture.defaults.bool(forKey: "reviewReminderEnabled"))

        fixture.service.status = .authorized
        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let reloaded = makeController(defaults: fixture.defaults, service: fixture.service)
        await reloaded.refreshAuthorization(for: ledgerFixture.ledger)
        await reloaded.waitForPendingUpdates()

        #expect(!reloaded.wantsReminders)
        #expect(!reloaded.isEnabled)
        #expect(fixture.service.pendingRequest == nil)
    }

    @Test func permissionRequestFailureIsTransientAndExplained() async {
        let fixture = makeFixture(isEnabled: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.status = .notDetermined
        fixture.service.requestError = TestFailure()

        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        await controller.enable()
        await controller.waitForPendingUpdates()

        #expect(!controller.isEnabled)
        #expect(!controller.isDeniedBySystem)
        #expect(controller.statusMessage?.contains("could not request") == true)

        await controller.refreshAuthorization(for: Ledger())
        await controller.waitForPendingUpdates()
        #expect(controller.statusMessage?.contains("could not request") == true)

        fixture.service.requestError = nil
        fixture.service.status = .authorized
        await controller.refreshAuthorization(for: Ledger())
        await controller.waitForPendingUpdates()
        #expect(controller.isEnabled)
        #expect(controller.statusMessage == nil)
    }

    @Test func schedulingFailureIsVisibleAndTheNextRefreshRetries() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        await controller.refreshAuthorization(for: Ledger())
        await controller.waitForPendingUpdates()

        fixture.service.replacementError = TestFailure()
        controller.refresh(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(controller.statusMessage?.contains("could not schedule") == true)
        #expect(fixture.service.pendingRequest == nil)

        fixture.service.replacementError = nil
        controller.refresh(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        #expect(controller.statusMessage == nil)
        #expect(fixture.service.pendingRequest != nil)
    }

    @Test func timeAndTimeZoneChangesReplaceTheOneShotUsingInjectedClockAndCalendar() async throws {
        let fixture = makeFixture(isEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        var currentCalendar = calendar(timeZone: "Europe/Tallinn")
        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)

        let controller = ReviewReminderController(
            defaults: fixture.defaults,
            notificationService: fixture.service,
            now: { now },
            calendar: { currentCalendar }
        )
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        var request = try #require(fixture.service.pendingRequest)
        var components = request.calendar.dateComponents([.hour, .minute], from: request.fireDate)
        #expect(components.hour == 19)
        #expect(components.minute == 30)
        #expect(request.calendar.timeZone.identifier == "Europe/Tallinn")

        let newTime = try #require(
            currentCalendar.date(bySettingHour: 8, minute: 15, second: 0, of: now)
        )
        controller.setTime(newTime)
        controller.refresh(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        request = try #require(fixture.service.pendingRequest)
        components = request.calendar.dateComponents([.hour, .minute], from: request.fireDate)
        #expect(components.hour == 8)
        #expect(components.minute == 15)

        currentCalendar = calendar(timeZone: "Asia/Tokyo")
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        await controller.waitForPendingUpdates()
        request = try #require(fixture.service.pendingRequest)
        components = request.calendar.dateComponents([.hour, .minute], from: request.fireDate)
        #expect(components.hour == 8)
        #expect(components.minute == 15)
        #expect(request.calendar.timeZone.identifier == "Asia/Tokyo")
        #expect(request.triggerDateComponents.calendar?.identifier == .gregorian)
        #expect(request.triggerDateComponents.timeZone?.identifier == "Asia/Tokyo")
    }

    @Test func simultaneousFirstReviewOffersOnlyOnce() async {
        let fixture = makeFixture(isEnabled: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.status = .notDetermined

        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        async let first: Void = controller.offerAfterFirstReview(for: Ledger())
        async let second: Void = controller.offerAfterFirstReview(for: Ledger())
        _ = await (first, second)
        await controller.waitForPendingUpdates()

        #expect(fixture.service.authorizationRequestCount == 1)
        #expect(!controller.shouldOfferReminders)
    }

    @Test func repeatedEnableWhilePermissionRequestIsOpenDoesNotAskTwice() async throws {
        let fixture = makeFixture(isEnabled: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.status = .notDetermined
        fixture.service.blockNextPermissionRequest = true

        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        let firstEnable = Task { await controller.enable() }
        try await fixture.service.waitUntilPermissionRequestIsBlocked()

        await controller.enable()
        fixture.service.releaseBlockedPermissionRequest()
        await firstEnable.value

        #expect(fixture.service.authorizationRequestCount == 1)
        #expect(controller.isEnabled)
    }

    @Test func foregroundRefreshDoesNotCancelAnExplicitOfferAndOfferUsesNewestQueue() async throws {
        let fixture = makeFixture(isEnabled: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.service.status = .notDetermined
        fixture.service.blockNextPermissionRequest = true

        var ledgerFixture = makeLedger()
        try addDraft(to: &ledgerFixture, capturedAt: now)
        let controller = makeController(defaults: fixture.defaults, service: fixture.service)
        let firstLedger = ledgerFixture.ledger
        let offering = Task {
            await controller.offerAfterFirstReview(for: firstLedger)
        }
        try await fixture.service.waitUntilPermissionRequestIsBlocked()

        try addDraft(to: &ledgerFixture, capturedAt: now)
        await controller.refreshAuthorization(for: ledgerFixture.ledger)
        fixture.service.releaseBlockedPermissionRequest()
        await offering.value
        await controller.waitForPendingUpdates()

        #expect(fixture.service.authorizationRequestCount == 1)
        #expect(fixture.service.authorizationCheckCount == 1)
        #expect(controller.isEnabled)
        #expect(fixture.service.pendingRequest?.title == "2 entries to review")
    }

    private func makeController(
        defaults: UserDefaults,
        service: TestReviewNotificationService
    ) -> ReviewReminderController {
        ReviewReminderController(
            defaults: defaults,
            notificationService: service,
            now: { now },
            calendar: { calendar(timeZone: "Europe/Tallinn") }
        )
    }

    private func makeFixture(
        isEnabled: Bool
    ) -> (
        suiteName: String,
        defaults: UserDefaults,
        service: TestReviewNotificationService
    ) {
        let suiteName = "ReviewReminderControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(isEnabled, forKey: "reviewReminderEnabled")
        return (suiteName, defaults, TestReviewNotificationService())
    }

    private func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func makeLedger() -> (ledger: Ledger, bank: Account, category: Account) {
        var ledger = Ledger()
        let currency = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset, currency: currency)
        let category = Account(name: "Food", kind: .expense)
        ledger.addAccount(bank)
        ledger.addAccount(category)
        return (ledger, bank, category)
    }

    @discardableResult
    private func addDraft(
        to fixture: inout (ledger: Ledger, bank: Account, category: Account),
        capturedAt: Date
    ) throws -> AccountantCore.Transaction {
        let currency = Currency("EUR")
        let transaction = AccountantCore.Transaction(
            date: capturedAt,
            memo: "Groceries",
            postings: [
                Posting(accountID: fixture.bank.id, money: Money(-10, currency: currency)),
                Posting(accountID: fixture.category.id, money: Money(10, currency: currency))
            ],
            state: .draft,
            createdAt: capturedAt
        )
        try fixture.ledger.addTransaction(transaction)
        return transaction
    }
}

@MainActor
private final class TestReviewNotificationService: ReviewNotificationService {
    var status: ReviewReminderAuthorizationStatus = .authorized
    var requestError: Error?
    var replacementError: Error?
    var blockNextReplacement = false
    var blockNextAuthorizationCheck = false
    var blockNextPermissionRequest = false

    private(set) var pendingRequest: ReviewNotificationRequest?
    private(set) var authorizationRequestCount = 0
    private(set) var authorizationCheckCount = 0
    private(set) var maximumPendingCount = 0
    private let replacementBlock = TestBlockSignal()
    private let authorizationCheckBlock = TestBlockSignal()
    private let permissionRequestBlock = TestBlockSignal()

    func authorizationStatus() async -> ReviewReminderAuthorizationStatus {
        authorizationCheckCount += 1
        let result = status
        if blockNextAuthorizationCheck {
            blockNextAuthorizationCheck = false
            await authorizationCheckBlock.block()
        }
        return result
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        if let requestError { throw requestError }
        if blockNextPermissionRequest {
            blockNextPermissionRequest = false
            await permissionRequestBlock.block()
        }
        status = .authorized
        return true
    }

    func replacePendingRequest(with request: ReviewNotificationRequest?) async throws {
        if blockNextReplacement {
            blockNextReplacement = false
            await replacementBlock.block()
        }

        if let replacementError { throw replacementError }
        pendingRequest = request
        maximumPendingCount = max(maximumPendingCount, pendingRequest == nil ? 0 : 1)
    }

    func releaseBlockedReplacement() {
        replacementBlock.release()
    }

    func releaseBlockedAuthorizationCheck() {
        authorizationCheckBlock.release()
    }

    func releaseBlockedPermissionRequest() {
        permissionRequestBlock.release()
    }

    func waitUntilReplacementIsBlocked() async throws {
        try await replacementBlock.waitUntilBlocked()
    }

    func waitUntilAuthorizationCheckIsBlocked() async throws {
        try await authorizationCheckBlock.waitUntilBlocked()
    }

    func waitUntilPermissionRequestIsBlocked() async throws {
        try await permissionRequestBlock.waitUntilBlocked()
    }
}

@MainActor
private final class TestBlockSignal {
    private var isBlocked = false
    private var startWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func block() async {
        isBlocked = true
        let waiters = Array(startWaiters.values)
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: ()) }

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        isBlocked = false
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilBlocked() async throws {
        guard !isBlocked else { return }
        let id = UUID()

        try await withCheckedThrowingContinuation { continuation in
            startWaiters[id] = continuation
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                self.timeOutStartWaiter(id: id)
            }
        }
    }

    private func timeOutStartWaiter(id: UUID) {
        startWaiters.removeValue(forKey: id)?.resume(throwing: TestWaitTimeout())
    }
}

private struct TestFailure: Error {}
private struct TestWaitTimeout: Error {}

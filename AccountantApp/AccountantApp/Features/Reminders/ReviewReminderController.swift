import Foundation
import AccountantCore
#if canImport(Combine)
import Combine
#endif

enum ReviewReminderAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
}

struct ReviewNotificationRequest: Equatable {
    let title: String
    let body: String
    let fireDate: Date
    let calendar: Calendar

    var triggerDateComponents: DateComponents {
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        // The numeric year/month/day must be interpreted by the same calendar
        // that produced them, including its current time zone.
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}

@MainActor
protocol ReviewNotificationService {
    func authorizationStatus() async -> ReviewReminderAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func replacePendingRequest(with request: ReviewNotificationRequest?) async throws
}

/// Schedules one evening nudge for the current review queue.
///
/// The pending request is replaced whenever its count or time can have changed.
/// Replacements are deliberately serialized: if an add is still in flight when
/// the user disables reminders, its completion is followed by the newer cancel
/// instead of allowing the stale add to win the race.
@MainActor
final class ReviewReminderController: ObservableObject {

    private enum Key {
        static let isEnabled = "reviewReminderEnabled"
        static let hour = "reviewReminderHour"
        static let minute = "reviewReminderMinute"
        static let didAsk = "reviewReminderDidAskPermission"
    }

    private static let defaultHour = 19
    private static let defaultMinute = 30

    @Published private(set) var isEnabled = false
    @Published private(set) var hour: Int
    @Published private(set) var minute: Int
    /// The Settings switch preserves the user's choice even when iOS blocks
    /// delivery. Foreground permission checks never change this choice.
    @Published private(set) var wantsReminders: Bool
    @Published private(set) var authorizationStatus: ReviewReminderAuthorizationStatus = .notDetermined
    @Published private(set) var didAuthorizationCheckFail = false
    @Published private(set) var didSchedulingFail = false

    var isDeniedBySystem: Bool { authorizationStatus == .denied }

    var statusMessage: String? {
        if isDeniedBySystem {
            return "Notifications are blocked for Accountant in iOS Settings. Turn them on there, or switch this reminder off."
        }
        if didAuthorizationCheckFail {
            return "Accountant could not request notification permission. Switch this reminder off and on to try again."
        }
        if didSchedulingFail {
            return "Accountant could not schedule the reminder. It will try again when the app becomes active or the review queue changes."
        }
        return nil
    }

    private let defaults: UserDefaults
    private let notificationService: any ReviewNotificationService
    private let now: () -> Date
    private let calendar: () -> Calendar

    private var intentRevision = 0
    private var authorizationReadRevision = 0
    private var activeEnableRevision: Int?
    private var latestLedger = Ledger()

    private var desiredRequest: ReviewNotificationRequest?
    private var replacementRevision = 0
    private var replacementTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        notificationService: any ReviewNotificationService,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.defaults = defaults
        self.notificationService = notificationService
        self.now = now
        self.calendar = calendar
        self.wantsReminders = defaults.bool(forKey: Key.isEnabled)
        self.hour = defaults.object(forKey: Key.hour) as? Int ?? Self.defaultHour
        self.minute = defaults.object(forKey: Key.minute) as? Int ?? Self.defaultMinute
    }

    var reminderTime: Date {
        calendar().date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: now()
        ) ?? now()
    }

    var shouldOfferReminders: Bool {
        !defaults.bool(forKey: Key.didAsk)
    }

    /// Spends the one automatic permission offer only after a successful review.
    /// Marking it asked before suspension also prevents two confirmation routes
    /// from presenting duplicate prompts.
    func offerAfterFirstReview(for ledger: Ledger) async {
        latestLedger = ledger

        guard shouldOfferReminders else {
            refreshLatestLedger()
            return
        }

        defaults.set(true, forKey: Key.didAsk)
        await enable()
        refreshLatestLedger()
    }

    /// Records user intent, then reconciles it with the current system setting.
    func enable() async {
        guard activeEnableRevision == nil else { return }

        intentRevision += 1
        let revision = intentRevision
        activeEnableRevision = revision
        authorizationReadRevision += 1
        defer {
            if activeEnableRevision == revision {
                activeEnableRevision = nil
            }
        }
        defaults.set(true, forKey: Key.didAsk)
        wantsReminders = true
        defaults.set(true, forKey: Key.isEnabled)
        didAuthorizationCheckFail = false

        let currentStatus = await notificationService.authorizationStatus()
        guard revision == intentRevision,
              activeEnableRevision == revision,
              wantsReminders else { return }
        authorizationStatus = currentStatus

        switch currentStatus {
        case .authorized:
            isEnabled = true
        case .denied:
            isEnabled = false
            replacePendingRequest(with: nil)
        case .notDetermined:
            do {
                let granted = try await notificationService.requestAuthorization()
                guard revision == intentRevision,
                      activeEnableRevision == revision,
                      wantsReminders else { return }
                authorizationStatus = granted ? .authorized : .denied
                isEnabled = granted
                if !granted { replacePendingRequest(with: nil) }
            } catch {
                guard revision == intentRevision,
                      activeEnableRevision == revision,
                      wantsReminders else { return }
                isEnabled = false
                didAuthorizationCheckFail = true
                replacePendingRequest(with: nil)
            }
        }
    }

    func disable() {
        intentRevision += 1
        authorizationReadRevision += 1
        activeEnableRevision = nil
        wantsReminders = false
        isEnabled = false
        didAuthorizationCheckFail = false
        defaults.set(false, forKey: Key.isEnabled)
        replacePendingRequest(with: nil)
    }

    func setTime(_ date: Date) {
        let components = calendar().dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? Self.defaultHour
        minute = components.minute ?? Self.defaultMinute
        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
    }

    /// Re-reads permission after launch or foregrounding. This never asks for
    /// permission and never changes the user's persisted on/off choice.
    func refreshAuthorization(for ledger: Ledger) async {
        latestLedger = ledger

        // A scene becoming active is routine and must not cancel the explicit
        // request that caused the system permission sheet to appear.
        guard activeEnableRevision == nil else { return }

        authorizationReadRevision += 1
        let revision = authorizationReadRevision
        let refreshedStatus = await notificationService.authorizationStatus()
        guard revision == authorizationReadRevision,
              activeEnableRevision == nil else { return }
        authorizationStatus = refreshedStatus

        switch authorizationStatus {
        case .authorized:
            didAuthorizationCheckFail = false
            isEnabled = wantsReminders
        case .denied:
            didAuthorizationCheckFail = false
            isEnabled = false
        case .notDetermined:
            isEnabled = false
        }

        refreshLatestLedger()
    }

    /// Rebuilds the sole pending reminder from the latest ledger, time, calendar,
    /// and time zone. Safe to call after any relevant state or lifecycle change.
    func refresh(for ledger: Ledger, now suppliedNow: Date? = nil) {
        latestLedger = ledger
        refreshLatestLedger(now: suppliedNow)
    }

    private func refreshLatestLedger(now suppliedNow: Date? = nil) {
        guard isEnabled else {
            replacePendingRequest(with: nil)
            return
        }

        let currentDate = suppliedNow ?? now()
        let currentCalendar = calendar()

        guard case let .remind(reminder) = ReviewReminder.decide(
            for: latestLedger,
            now: currentDate,
            calendar: currentCalendar
        ), let fireDate = nextFireDate(after: currentDate, calendar: currentCalendar) else {
            replacePendingRequest(with: nil)
            return
        }

        replacePendingRequest(
            with: ReviewNotificationRequest(
                title: reminder.title,
                body: reminder.body,
                fireDate: fireDate,
                calendar: currentCalendar
            )
        )
    }

    /// Test synchronization point for the serialized replacement loop.
    func waitForPendingUpdates() async {
        while let task = replacementTask {
            await task.value
        }
    }

    private func nextFireDate(after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private func replacePendingRequest(with request: ReviewNotificationRequest?) {
        desiredRequest = request
        replacementRevision += 1

        guard replacementTask == nil else { return }

        replacementTask = Task { [weak self] in
            await self?.runReplacementLoop()
        }
    }

    private func runReplacementLoop() async {
        while true {
            let revision = replacementRevision
            let request = desiredRequest

            do {
                try await notificationService.replacePendingRequest(with: request)
                if revision == replacementRevision {
                    didSchedulingFail = false
                }
            } catch {
                if revision == replacementRevision {
                    didSchedulingFail = true
                }
            }

            guard revision != replacementRevision else {
                replacementTask = nil
                return
            }
        }
    }
}

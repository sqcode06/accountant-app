import Foundation
import UserNotifications
import AccountantCore

/// Schedules the evening nudge to review what was captured.
///
/// The decision of whether to nudge and what to say lives in
/// `AccountantCore.ReviewReminder`, where it is testable. This is the part that
/// has to talk to iOS: permission, scheduling, cancelling.
///
/// **Scheduled one occurrence at a time, not as a repeating trigger.** A repeating
/// notification fixes its text when it is scheduled, so it would still be
/// announcing "3 entries to review" weeks after those three were confirmed. Every
/// ledger change reschedules the next one instead, which keeps the count honest
/// and means an empty queue cancels rather than fires.
@MainActor
final class ReviewReminderController: ObservableObject {

    private enum Key {
        static let isEnabled = "reviewReminderEnabled"
        static let hour = "reviewReminderHour"
        static let minute = "reviewReminderMinute"
        static let didAsk = "reviewReminderDidAskPermission"
    }

    private static let requestIdentifier = "review-reminder"

    /// Early evening: late enough that the day's spending has happened, early
    /// enough that a five-minute task does not feel like one more thing before bed.
    private static let defaultHour = 19
    private static let defaultMinute = 30

    @Published private(set) var isEnabled: Bool
    @Published private(set) var hour: Int
    @Published private(set) var minute: Int

    /// Set when iOS has refused us. The toggle stays visible but explains itself
    /// rather than silently doing nothing.
    @Published private(set) var isDeniedBySystem = false

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    init(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.center = center

        self.isEnabled = defaults.bool(forKey: Key.isEnabled)
        // `integer(forKey:)` returns 0 for an unset key, which is a legitimate
        // hour, so the presence of the key is what distinguishes "midnight" from
        // "never chosen".
        self.hour = defaults.object(forKey: Key.hour) as? Int ?? Self.defaultHour
        self.minute = defaults.object(forKey: Key.minute) as? Int ?? Self.defaultMinute
    }

    /// The chosen time as a `Date` today, for a `DatePicker` to bind to.
    var reminderTime: Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    // MARK: - Permission

    /// Whether now is a sensible moment to ask.
    ///
    /// iOS lets an app ask exactly once, so the ask has to be spent well. Asking on
    /// first launch — before anything is recorded, when the app has demonstrated
    /// nothing — is how that one chance gets wasted on a "no".
    var shouldOfferReminders: Bool {
        !defaults.bool(forKey: Key.didAsk)
    }

    /// Called once the user has confirmed their first review, when the loop has
    /// just proved itself and the offer means something.
    func offerAfterFirstReview() async {
        guard shouldOfferReminders else { return }

        defaults.set(true, forKey: Key.didAsk)

        await enable()
    }

    /// Turns reminders on, asking for permission if it has not been granted.
    func enable() async {
        defaults.set(true, forKey: Key.didAsk)

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])

            isDeniedBySystem = !granted
            isEnabled = granted
            defaults.set(granted, forKey: Key.isEnabled)
        } catch {
            // A failed request is a refusal for our purposes; there is nothing
            // useful to tell the user beyond the toggle not sticking.
            isDeniedBySystem = true
            isEnabled = false
            defaults.set(false, forKey: Key.isEnabled)
        }
    }

    func disable() {
        isEnabled = false
        defaults.set(false, forKey: Key.isEnabled)
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }

    func setTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)

        hour = components.hour ?? Self.defaultHour
        minute = components.minute ?? Self.defaultMinute

        defaults.set(hour, forKey: Key.hour)
        defaults.set(minute, forKey: Key.minute)
    }

    // MARK: - Scheduling

    /// Rebuilds the pending reminder from current ledger state.
    ///
    /// Safe and cheap to call after any change; it always cancels before deciding,
    /// so there is never more than one pending and never a stale one.
    func refresh(for ledger: Ledger, now: Date = Date()) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])

        guard isEnabled else { return }

        guard case let .remind(reminder) = ReviewReminder.decide(for: ledger, now: now) else {
            return
        }

        guard let fireDate = nextFireDate(after: now) else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: fireDate
            ),
            repeats: false
        )

        center.add(
            UNNotificationRequest(
                identifier: Self.requestIdentifier,
                content: content,
                trigger: trigger
            )
        )
    }

    /// The next time the reminder should fire.
    ///
    /// If today's slot has passed, this is tomorrow — reviewing at 21:00 should not
    /// summon a notification for 19:30 the same evening.
    private func nextFireDate(after now: Date) -> Date? {
        let calendar = Calendar.current

        guard let today = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: now
        ) else {
            return nil
        }

        if today > now {
            return today
        }

        return calendar.date(byAdding: .day, value: 1, to: today)
    }
}

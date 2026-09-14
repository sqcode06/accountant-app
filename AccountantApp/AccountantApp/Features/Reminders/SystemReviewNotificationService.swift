import Foundation
import UserNotifications

extension ReviewReminderController {
    convenience init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.init(
            defaults: defaults,
            notificationService: SystemReviewNotificationService(),
            now: now,
            calendar: calendar
        )
    }
}

/// The only type in the reminder feature that knows about UserNotifications.
/// Keeping that boundary small lets the controller's permission and replacement
/// behavior run against a deterministic service in tests.
final class SystemReviewNotificationService: ReviewNotificationService {
    private static let requestIdentifier = "review-reminder"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> ReviewReminderAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func replacePendingRequest(with request: ReviewNotificationRequest?) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])

        guard let request else { return }

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: request.triggerDateComponents,
            repeats: false
        )

        try await center.add(
            UNNotificationRequest(
                identifier: Self.requestIdentifier,
                content: content,
                trigger: trigger
            )
        )
    }
}

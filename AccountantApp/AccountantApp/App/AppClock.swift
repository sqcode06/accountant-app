import SwiftUI

/// The wall clock used for user-visible dates.
///
/// Keeping it in the environment lets simulator workflows exercise a known
/// calendar month without changing the device clock. Production always uses the
/// live clock; the fixed implementation is only selected by the debug UI-test
/// launch configuration.
struct AppClock: Sendable {
    private let read: @Sendable () -> Date

    init(read: @escaping @Sendable () -> Date) {
        self.read = read
    }

    func now() -> Date { read() }

    static let live = AppClock { Date() }

    static func fixed(_ date: Date) -> AppClock {
        AppClock { date }
    }
}

private struct AppClockKey: EnvironmentKey {
    static let defaultValue = AppClock.live
}

extension EnvironmentValues {
    var appClock: AppClock {
        get { self[AppClockKey.self] }
        set { self[AppClockKey.self] = newValue }
    }
}

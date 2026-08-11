import SwiftUI

/// Whether the setup guide still has anything to say.
enum OnboardingStatus: String {
    /// Not been through it, or dismissed while asking to be reminded. Shows on
    /// the next launch.
    case pending

    /// Went through it and finished.
    case completed

    /// Dismissed with the reminder switched off.
    ///
    /// Kept as its own case rather than folded into `completed` because "set up
    /// their accounts" and "waved us away for good" are different facts, and only
    /// one of them means the app is ready to use.
    case dismissed
}

@MainActor
final class OnboardingController: ObservableObject {

    private static let storageKey = "onboardingStatus"

    @Published private(set) var status: OnboardingStatus

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.string(forKey: Self.storageKey)
        self.status = stored.flatMap(OnboardingStatus.init(rawValue:)) ?? .pending
    }

    var shouldPresent: Bool {
        status == .pending
    }

    func complete() {
        set(.completed)
    }

    /// Closed with the reminder switched off — do not offer it again.
    func dismissPermanently() {
        set(.dismissed)
    }

    /// Puts the guide back, from the danger zone.
    func reset() {
        set(.pending)
    }

    private func set(_ newStatus: OnboardingStatus) {
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: Self.storageKey)
    }
}

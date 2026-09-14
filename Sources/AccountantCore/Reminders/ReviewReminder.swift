import Foundation

/// Decides whether an evening review is worth interrupting someone for.
///
/// Quick capture is deliberately careless — you tap an amount and a category at
/// the till and move on — and that only works because the review catches what the
/// carelessness got wrong. Until now nothing prompted the review except opening
/// the app, which is exactly what someone avoiding their budget does not do.
///
/// Kept as a pure function of ledger state so it tests on Linux like the rest of
/// the core. Nothing here imports `UserNotifications`; the app layer asks this
/// what to say and then says it.
public enum ReviewReminder {

    /// What the app should do at the reminder hour.
    public enum Decision: Equatable, Sendable {
        /// Nothing to review. The app should cancel any pending reminder rather
        /// than fire one — being reminded to review nothing is worse than not
        /// being reminded at all, and it is how a notification becomes noise the
        /// user turns off.
        case nothingToReview

        /// Worth a nudge.
        case remind(Reminder)
    }

    public struct Reminder: Equatable, Sendable {
        public let draftCount: Int

        /// Age in days of the oldest unreviewed entry, 0 for anything captured
        /// today.
        public let oldestDraftAgeInDays: Int

        public init(draftCount: Int, oldestDraftAgeInDays: Int) {
            self.draftCount = draftCount
            self.oldestDraftAgeInDays = oldestDraftAgeInDays
        }

        public var title: String {
            draftCount == 1 ? "1 entry to review" : "\(draftCount) entries to review"
        }

        /// Says what is waiting, never how the user is doing.
        ///
        /// A reminder is read in a second and out of context, which makes it the
        /// worst possible place for judgement. "You are over budget" pushes people
        /// away from an app they need to open; naming the task gets it done.
        public var body: String {
            switch oldestDraftAgeInDays {
            case 0:
                "Check what you captured today and confirm it."
            case 1:
                "Some of these have been waiting since yesterday."
            case 2...6:
                "The oldest has been waiting \(oldestDraftAgeInDays) days."
            default:
                "A few have been waiting over a week."
            }
        }
    }

    /// Whether to fire, and what to say.
    ///
    /// `now` and `calendar` are injected so this is testable without waiting for
    /// an evening, and so day arithmetic respects the user's own calendar rather
    /// than assuming 86,400-second days — which is wrong twice a year in most of
    /// Europe.
    public static func decide(
        for ledger: Ledger,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Decision {
        let drafts = ledger.draftTransactions()

        guard !drafts.isEmpty else { return .nothingToReview }

        // `draftTransactions()` is oldest first, but it sorts on the *effective*
        // date, which the user can backdate. Capture time is what "waiting" means
        // here, so take the minimum rather than trusting position.
        let oldestCapture = drafts.map(\.createdAt).min() ?? now

        let startOfCapture = calendar.startOfDay(for: oldestCapture)
        let startOfToday = calendar.startOfDay(for: now)

        let days = calendar.dateComponents(
            [.day],
            from: startOfCapture,
            to: startOfToday
        ).day ?? 0

        return .remind(
            Reminder(
                draftCount: drafts.count,
                // A clock skew or a backdated capture must not produce a negative
                // age, which would fall through to the "over a week" wording.
                oldestDraftAgeInDays: max(0, days)
            )
        )
    }
}

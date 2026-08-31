import SwiftUI
import AccountantCore

/// A short-lived bar offering back the draft that was just deleted.
///
/// Deliberately not an alert. The review flow works because a swipe is instant,
/// and a confirmation dialog on each one would undo the only thing that makes
/// going through a day of captures bearable. This puts the safety net *after* the
/// action instead of in front of it.
struct UndoBar: View {
    let message: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            Text(message)
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)

            Spacer(minLength: Metrics.Space.s)

            Button("Undo", action: undo)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .accessibilityLabel("Dismiss")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.Space.l)
        .padding(.vertical, Metrics.Space.m)
        .background(
            Theme.surfaceRaised,
            in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

extension View {
    /// Shows the undo bar whenever a draft has just been deleted.
    ///
    /// Applied to whichever screen the user lands on after the delete — the review
    /// list for a swipe, the activity list for a delete made from the detail screen
    /// that then pops back.
    func draftDeletionUndoBar() -> some View {
        modifier(DraftDeletionUndoBar())
    }
}

private struct DraftDeletionUndoBar: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let pending = appState.recentlyDeletedDraft {
                    UndoBar(
                        message: message(for: pending.transaction),
                        undo: { Task { await appState.undoDraftDeletion() } },
                        dismiss: { appState.dismissUndo() }
                    )
                    .padding(.horizontal, Metrics.Space.l)
                    .padding(.bottom, Metrics.Space.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: appState.recentlyDeletedDraft)
    }

    /// Names the entry so it is clear *which* one went, when several were deleted
    /// in a row.
    private func message(for transaction: AccountantCore.Transaction) -> String {
        if let memo = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines),
           !memo.isEmpty {
            return "Deleted “\(memo)”"
        }

        if let money = largestPosting(in: transaction) {
            return "Deleted \(MoneyDisplay.string(money))"
        }

        return "Entry deleted"
    }

    private func largestPosting(in transaction: AccountantCore.Transaction) -> Money? {
        transaction.postings
            .max { abs($0.money.amount) < abs($1.money.amount) }
            .map { Money(abs($0.money.amount), currency: $0.money.currency) }
    }
}

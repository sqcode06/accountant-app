import SwiftUI
import AccountantCore

/// Shown when a store was found damaged and writing is paused.
///
/// A bar rather than an alert, deliberately. The previous behaviour was a
/// dismissible alert, and a dismissible alert is one tap from gone — after which
/// the app looked empty, behaved normally, and overwrote the real file on the next
/// edit. This cannot be dismissed; it goes away when the situation is resolved.
///
/// It also names the quarantine file. "Something went wrong" is useless when the
/// actionable fact is that the data still exists, under a specific name.
struct DataRecoveryBanner: View {
    @EnvironmentObject private var appState: AppState

    @State private var isConfirmingStartFresh = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            HStack(alignment: .top, spacing: Metrics.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.deficit)

                VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                    Text("Saving is paused")
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.ink)

                    Text("Your saved data could not be read, so the app has not touched it. Nothing will be written until you choose what to do.")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !quarantined.isEmpty {
                        Text("Kept safe as \(quarantined.joined(separator: ", "))")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: Metrics.Space.s) {
                Button {
                    Task {
                        isWorking = true
                        await appState.retryLoadAfterDamage()
                        isWorking = false
                    }
                } label: {
                    Text("Try again")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Metrics.Space.l)
                        .padding(.vertical, Metrics.Space.s)
                        .background(Theme.surfaceSunken, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    isConfirmingStartFresh = true
                } label: {
                    Text("Start fresh")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.inkInverse)
                        .padding(.horizontal, Metrics.Space.l)
                        .padding(.vertical, Metrics.Space.s)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .disabled(isWorking)
            .opacity(isWorking ? 0.5 : 1)
        }
        .card()
        .padding(.horizontal, Metrics.Space.l)
        .padding(.bottom, Metrics.Space.s)
        .confirmationDialog(
            "Start fresh?",
            isPresented: $isConfirmingStartFresh,
            titleVisibility: .visible
        ) {
            Button("Start fresh", role: .destructive) {
                Task {
                    isWorking = true
                    await appState.startFreshAfterDamage()
                    isWorking = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will start with no data. Your unreadable file stays on this device and is not deleted, so it can still be recovered.")
        }
    }

    private var quarantined: [String] {
        appState.dataProtection.quarantined.map(\.quarantinedURL.lastPathComponent)
    }
}

import SwiftUI

/// The way back into the setup guide, at the top of Settings.
///
/// Sits here rather than in the danger zone because running it destroys nothing —
/// it only offers to create an account and some categories. Putting it beside
/// "erase everything" would make a harmless thing look frightening.
///
/// The copy changes with what has actually happened, so it reads as a status
/// rather than a permanent advertisement for a thing you already did.
struct SetupGuideWidget: View {
    @EnvironmentObject private var onboarding: OnboardingController

    let onOpen: () -> Void

    var body: some View {
        Section {
            Button(action: onOpen) {
                HStack(spacing: Metrics.Space.m) {
                    Image(systemName: icon)
                        .font(.system(.title3, weight: .medium))
                        .foregroundStyle(Theme.inkInverse)
                        .frame(width: 42, height: 42)
                        .background(Theme.accent, in: RoundedRectangle(
                            cornerRadius: Metrics.Radius.inset,
                            style: .continuous
                        ))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.uiRowTitle)
                            .foregroundStyle(Theme.ink)

                        Text(subtitle)
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Metrics.Space.s)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.vertical, Metrics.Space.xs)
            }
            .buttonStyle(.plain)
        }
    }

    private var icon: String {
        onboarding.status == .completed ? "arrow.clockwise" : "sparkles"
    }

    private var title: String {
        switch onboarding.status {
        case .pending, .dismissed:
            "Finish setting up"
        case .completed:
            "Run the setup guide again"
        }
    }

    private var subtitle: String {
        switch onboarding.status {
        case .pending:
            "Add an account and the categories you spend on."
        case .dismissed:
            "You skipped this. It takes about a minute."
        case .completed:
            "Adds another account and more categories. Nothing is removed."
        }
    }
}

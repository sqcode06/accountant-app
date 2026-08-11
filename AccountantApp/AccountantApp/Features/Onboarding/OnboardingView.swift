import SwiftUI
import AccountantCore

/// First-run setup.
///
/// Exists because the app is unusable empty: with no accounts and no categories,
/// every screen is an empty state and the capture button has nowhere to put
/// anything. Four steps, and the two that matter create real data rather than
/// explaining what you could go and create yourself.
///
/// Skippable from every step. Someone who wants to poke around first should be
/// able to, and skipping is recorded as an answer — the guide does not come back.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var onboarding: OnboardingController

    /// Closes the guide without deciding anything about whether it returns.
    let onClose: () -> Void

    @State private var step = Step.welcome
    @State private var accountName = "Bank"
    @State private var currency = Currency("EUR")
    @State private var selectedCategories: Set<String> = ["Groceries", "Eating out", "Transport"]
    @State private var isFinishing = false

    /// Ticked by default: closing the guide should be a "not now", not a decision
    /// you made by accident on your first thirty seconds in the app. Untick it and
    /// the guide stops offering itself.
    @State private var remindNextTime = true

    private enum Step: Int, CaseIterable {
        case welcome, account, categories, done
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.xl) {
                    switch step {
                    case .welcome: welcomeStep
                    case .account: accountStep
                    case .categories: categoriesStep
                    case .done: doneStep
                    }
                }
                .padding(Metrics.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .background(Theme.canvas)
        .interactiveDismissDisabled()
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            HStack(spacing: Metrics.Space.xs) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.surfaceSunken)
                        .frame(width: item == step ? 20 : 6, height: 6)
                        .animation(.snappy(duration: 0.2), value: step)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Metrics.Space.l)
        .padding(.top, Metrics.Space.l)
    }

    private var footer: some View {
        VStack(spacing: Metrics.Space.m) {
            Button(action: advance) {
                Text(primaryTitle)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.inkInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Theme.accent,
                        in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance || isFinishing)
            .opacity(canAdvance && !isFinishing ? 1 : 0.4)

            if step != .done {
                VStack(spacing: Metrics.Space.s) {
                    Button("Skip for now", action: skip)
                        .font(.uiLabel)
                        .foregroundStyle(Theme.inkMuted)

                    // The choice sits next to the action it governs, so it is read
                    // at the moment it applies rather than buried in Settings.
                    Button {
                        remindNextTime.toggle()
                    } label: {
                        HStack(spacing: Metrics.Space.s) {
                            Image(systemName: remindNextTime ? "checkmark.square.fill" : "square")
                                .foregroundStyle(remindNextTime ? Theme.accent : Theme.inkFaint)

                            Text("Show this again next time")
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .font(.uiCaption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(remindNextTime ? [.isSelected] : [])
                }
            }
        }
        .padding(Metrics.Space.l)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            title("Accountant")

            Text("A budgeting app that keeps honest books underneath.")
                .font(.title3)
                .foregroundStyle(Theme.inkMuted)

            VStack(alignment: .leading, spacing: Metrics.Space.m) {
                point(
                    icon: "bolt",
                    title: "Record in two taps",
                    detail: "Type the amount, tap a category. Fix the details later."
                )
                point(
                    icon: "tray.full",
                    title: "Review when it suits you",
                    detail: "Everything you capture waits in one place until you confirm it."
                )
                point(
                    icon: "chart.bar",
                    title: "Set limits that hold",
                    detail: "Monthly limits per category, with what is left front and centre."
                )
            }
            .padding(.top, Metrics.Space.s)
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            title("Where is your money?")

            Text("Start with the account you spend from most. This is the balance the app will track.")
                .font(.uiBody)
                .foregroundStyle(Theme.inkMuted)

            VStack(alignment: .leading, spacing: Metrics.Space.m) {
                VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                    Text("Name")
                        .fieldLabel()

                    TextField("Bank", text: $accountName)
                        .textInputAutocapitalization(.words)
                        .font(.uiBody)
                        .foregroundStyle(Theme.ink)
                        .padding(Metrics.Space.m)
                        .background(
                            Theme.surfaceSunken,
                            in: RoundedRectangle(cornerRadius: Metrics.Radius.inset, style: .continuous)
                        )
                }

                VStack(alignment: .leading, spacing: Metrics.Space.xs) {
                    Text("Currency")
                        .fieldLabel()

                    Picker("Currency", selection: $currency) {
                        ForEach(CurrencyCatalog.options(including: currency), id: \.code) { option in
                            Text(CurrencyCatalog.displayName(for: option)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }
            }
            .card()
        }
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            title("What do you spend on?")

            Text("Pick a few to start. These become the categories you tap when recording, and the ones you can set limits on.")
                .font(.uiBody)
                .foregroundStyle(Theme.inkMuted)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: Metrics.Space.s)],
                spacing: Metrics.Space.s
            ) {
                ForEach(Self.suggestedCategories, id: \.self) { name in
                    let isSelected = selectedCategories.contains(name)

                    Button {
                        if isSelected {
                            selectedCategories.remove(name)
                        } else {
                            selectedCategories.insert(name)
                        }
                    } label: {
                        Text(name)
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.inkInverse : Theme.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Metrics.Space.m)
                            .background(
                                isSelected ? Theme.accent : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: Metrics.Radius.control, style: .continuous)
                                    .strokeBorder(Theme.hairline, lineWidth: isSelected ? 0 : 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeOut(duration: 0.15), value: selectedCategories)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.l) {
            title("You're set up")

            Text("Here is the loop the app is built around.")
                .font(.uiBody)
                .foregroundStyle(Theme.inkMuted)

            VStack(alignment: .leading, spacing: Metrics.Space.m) {
                point(
                    icon: "plus.circle",
                    title: "Capture as you go",
                    detail: "The button in the corner records spending without stopping to be precise."
                )
                point(
                    icon: "checkmark.circle",
                    title: "Confirm later",
                    detail: "Entries wait under Review until you check them. Nothing is final until you say so."
                )
                point(
                    icon: "chart.bar",
                    title: "Set your first limit",
                    detail: "The Budget tab is empty until you set one. Start with the category that gets away from you."
                )
            }
        }
    }

    // MARK: - Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(.largeTitle, weight: .bold))
            .foregroundStyle(Theme.ink)
    }

    private func point(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Metrics.Space.m) {
            Image(systemName: icon)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)

                Text(detail)
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Flow

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .account: "Continue"
        case .categories: "Continue"
        case .done: isFinishing ? "Setting up…" : "Start using Accountant"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome, .done:
            true
        case .account:
            !accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .categories:
            !selectedCategories.isEmpty
        }
    }

    private func advance() {
        switch step {
        case .welcome:
            step = .account
        case .account:
            step = .categories
        case .categories:
            step = .done
        case .done:
            finish()
        }
    }

    /// Leaving without finishing. The checkbox decides whether the guide offers
    /// itself again; either way nothing has been created yet.
    private func skip() {
        if !remindNextTime {
            onboarding.dismissPermanently()
        }

        onClose()
    }

    /// Creates everything at the end rather than as you go, so backing up a step
    /// or skipping partway through does not leave half a chart of accounts behind.
    private func finish() {
        isFinishing = true

        Task {
            await appState.createAccount(
                name: accountName.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .asset,
                currency: currency
            )

            for name in selectedCategories.sorted() {
                await appState.createAccount(name: name, kind: .expense)
            }

            isFinishing = false
            onboarding.complete()
            onClose()
        }
    }

    private static let suggestedCategories = [
        "Groceries",
        "Eating out",
        "Transport",
        "Rent",
        "Utilities",
        "Subscriptions",
        "Health",
        "Fun"
    ]
}

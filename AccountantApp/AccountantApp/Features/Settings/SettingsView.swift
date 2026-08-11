import SwiftUI
import AccountantCore

/// Everything that is configuration rather than daily use.
///
/// Import lives here and behind the Overview menu rather than in a tab: it happens
/// when a statement arrives, not continuously. Classification rules moved out of
/// the import screen, where they were buried inside a 1,000-line file and only
/// discoverable if you were already importing.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var onboarding: OnboardingController

    @State private var isPresentingImport = false
    @State private var isPresentingOnboarding = false

    var body: some View {
        List {
            SetupGuideWidget { isPresentingOnboarding = true }

            // High on purpose: changing theme rebuilds the tab content, which
            // scrolls this list back to the top. Anything lower would put the
            // control you just used off screen.
            ThemeSection()

            Section("Accounts") {
                NavigationLink {
                    AccountListView()
                        .environmentObject(appState)
                } label: {
                    Label("Manage accounts", systemImage: "folder")
                }
            }

            Section {
                Button {
                    isPresentingImport = true
                } label: {
                    Label("Import a statement", systemImage: "square.and.arrow.down")
                }

                NavigationLink {
                    ClassificationRulesView()
                        .environmentObject(appState)
                } label: {
                    Label("Import rules", systemImage: "wand.and.stars")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Rules match text in a statement line and set the category automatically.")
            }

            Section {
                LabeledContent("Display currency", value: appState.displayCurrency.code)
            } footer: {
                Text("Used where an account does not state its own currency. Amounts are never converted between currencies.")
            }

            Section {
                LabeledContent("Transactions", value: "\(appState.ledger.transactions.count)")
                LabeledContent("Accounts", value: "\(appState.ledger.accounts.count)")
                LabeledContent("Awaiting review", value: "\(appState.draftTransactions.count)")
            } header: {
                Text("Ledger")
            }

            Section {
                NavigationLink {
                    DangerZoneView()
                        .environmentObject(appState)
                        .environmentObject(onboarding)
                } label: {
                    Label("Danger zone", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.deficit)
                }
            } footer: {
                Text("Deleting transactions, clearing budgets, and starting over.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $isPresentingOnboarding) {
            OnboardingView { isPresentingOnboarding = false }
                .environmentObject(appState)
                .environmentObject(onboarding)
        }
        .sheet(isPresented: $isPresentingImport) {
            NavigationStack {
                ImportPreviewScreen()
                    .navigationTitle("Import")
                    .environmentObject(appState)
            }
        }
    }
}

/// Classification rules, lifted out of the import screen.
private struct ClassificationRulesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            if appState.classificationRules.isEmpty {
                Section {
                    Text("No rules yet. Rules are added while importing a statement.")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                }
            } else {
                Section {
                    ForEach(appState.classificationRules) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Contains “\(rule.needle)”")
                                .font(.uiRowTitle)
                                .foregroundStyle(Theme.ink)

                            Text(summary(for: rule))
                                .font(.uiCaption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.vertical, Metrics.Space.xs)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await appState.deleteClassificationRule(id: rule.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Import rules")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(for rule: ClassificationRuleConfiguration) -> String {
        var parts: [String] = []

        if let accountID = rule.counterpartyAccountID,
           let name = appState.ledger.accounts[accountID]?.name {
            parts.append("categorise as \(name)")
        }

        if let memo = rule.cleanedMemo {
            parts.append("rename to “\(memo)”")
        }

        return parts.isEmpty ? "No effect" : parts.joined(separator: ", ")
    }
}

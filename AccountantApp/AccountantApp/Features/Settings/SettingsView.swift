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
    @EnvironmentObject private var reminders: ReviewReminderController

    @State private var isPresentingImport = false
    @State private var isPresentingOnboarding = false

    var body: some View {
        List {
            SetupGuideWidget { isPresentingOnboarding = true }

            // High on purpose: changing theme rebuilds the tab content, which
            // scrolls this list back to the top. Anything lower would put the
            // control you just used off screen.
            ThemeSection()

            AppIconSection()

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
                .accessibilityIdentifier("settings.import")

                NavigationLink {
                    ClassificationRulesView()
                        .environmentObject(appState)
                } label: {
                    Label("Import rules", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("settings.importRules")
            } header: {
                Text("Import")
            } footer: {
                Text("Rules match text in a statement line and set the category automatically.")
            }

            Section {
                Toggle("Daily review reminder", isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { wantsReminders in
                        if wantsReminders {
                            Task {
                                await reminders.enable()
                                reminders.refresh(for: appState.ledger)
                            }
                        } else {
                            reminders.disable()
                        }
                    }
                ))
                .tint(Theme.accent)

                if reminders.isEnabled {
                    DatePicker(
                        "Remind me at",
                        selection: Binding(
                            get: { reminders.reminderTime },
                            set: { newTime in
                                reminders.setTime(newTime)
                                reminders.refresh(for: appState.ledger)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .tint(Theme.accent)
                }
            } header: {
                Text("Reminders")
            } footer: {
                if reminders.isDeniedBySystem {
                    Text("Notifications are turned off for Accountant in iOS Settings. Turn them on there to use reminders.")
                } else {
                    Text("A nudge at the end of the day, only when something is actually waiting to be reviewed.")
                }
            }

            Section {
                LabeledContent("Display currency", value: appState.displayCurrency.code)
            } footer: {
                Text("Used where an account does not state its own currency. Amounts are never converted between currencies.")
            }

            Section {
                LabeledContent("Transactions", value: "\(appState.ledger.transactions.count)")
                LabeledContent("Accounts", value: "\(appState.ledger.accounts.count)")
                LabeledContent("Awaiting review", value: "\(appState.draftCount)")
            } header: {
                Text("Ledger")
            }

            Section {
                NavigationLink {
                    DataExportView()
                        .environmentObject(appState)
                } label: {
                    Label("Export your data", systemImage: "square.and.arrow.up")
                }

                NavigationLink {
                    RestoreBackupView()
                        .environmentObject(appState)
                } label: {
                    Label("Restore from a backup", systemImage: "arrow.uturn.backward")
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Spreadsheet files to read anywhere, and a full backup to keep somewhere safe — and put back if you ever need to.")
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

            Section {
                BrandSignature()
                    .padding(.vertical, Metrics.Space.xs)
            } footer: {
                Text(Brand.promise)
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
            ImportFlow()
                .environmentObject(appState)
        }
    }
}

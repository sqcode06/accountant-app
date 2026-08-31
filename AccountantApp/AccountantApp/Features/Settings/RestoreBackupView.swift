import SwiftUI
import UniformTypeIdentifiers
import AccountantCore

/// Puts a backup back.
///
/// The whole screen exists to answer one question before anything is overwritten:
/// is this the right file? So it reads the backup, says what is in it and what it
/// is about to replace, and only then offers the button. Restoring straight from
/// the file picker would be faster and would make picking last year's backup by
/// mistake a silent, total loss.
struct RestoreBackupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isPickingFile = false
    @State private var candidate: Candidate?
    @State private var failure: String?
    @State private var isRestoring = false
    @State private var isConfirming = false
    @State private var didRestore = false

    var body: some View {
        List {
            if didRestore {
                Section {
                    Label("Restored", systemImage: "checkmark.circle.fill")
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.cleared)

                    Text("Your data has been replaced with the backup and saved.")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                }
            } else if let candidate {
                comparison(candidate)

                Section {
                    Button(role: .destructive) {
                        isConfirming = true
                    } label: {
                        if isRestoring {
                            HStack(spacing: Metrics.Space.s) {
                                ProgressView()
                                Text("Restoring…")
                            }
                        } else {
                            Text("Replace everything with this backup")
                        }
                    }
                    .disabled(isRestoring)

                    Button("Choose a different file") {
                        self.candidate = nil
                        isPickingFile = true
                    }
                    .disabled(isRestoring)
                }
            } else {
                Section {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("Choose a backup file", systemImage: "folder")
                    }
                } footer: {
                    Text("Pick a backup exported from this app. Nothing is replaced until you have seen what is in it and confirmed.")
                }
            }

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.deficit)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .confirmationDialog(
            "Replace everything?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Replace everything", role: .destructive) {
                Task { await restore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current transactions, budget limits and import rules will be replaced by the backup. This cannot be undone.")
        }
    }

    // MARK: - Comparison

    /// Side by side on purpose. "12 transactions" means nothing alone; "12,
    /// replacing 400" is a number you react to.
    private func comparison(_ candidate: Candidate) -> some View {
        Section {
            row("Transactions", now: appState.ledger.transactions.count, backup: candidate.summary.transactionCount)
            row("Accounts", now: appState.ledger.accounts.count, backup: candidate.summary.accountCount)
            row("Awaiting review", now: appState.draftCount, backup: candidate.summary.draftCount)
            row("Budget limits", now: appState.budget.targets.count, backup: candidate.summary.budgetTargetCount)
            row("Import rules", now: appState.classificationRules.count, backup: candidate.summary.classificationRuleCount)
        } header: {
            Text(candidate.filename)
        } footer: {
            Text("Backup made \(candidate.summary.createdAt.formatted(date: .abbreviated, time: .shortened)).")
        }
    }

    private func row(_ title: String, now: Int, backup: Int) -> some View {
        HStack {
            Text(title)
                .font(.uiRowTitle)
                .foregroundStyle(Theme.ink)

            Spacer()

            Text("\(now)")
                .font(.figureTrailing)
                .foregroundStyle(Theme.inkFaint)
                .strikethrough(now != backup)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.inkFaint)

            Text("\(backup)")
                .font(.figureRow)
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Loading

    private func handle(_ result: Result<[URL], Error>) {
        failure = nil

        switch result {
        case let .failure(error):
            failure = error.localizedDescription

        case let .success(urls):
            guard let url = urls.first else { return }

            do {
                candidate = try Candidate(url: url)
            } catch {
                candidate = nil
                failure = error.localizedDescription
            }
        }
    }

    private func restore() async {
        guard let candidate else { return }

        isRestoring = true
        defer { isRestoring = false }

        if await appState.restore(from: candidate.backup) {
            didRestore = true
            self.candidate = nil
        } else {
            failure = appState.lastError?.message ?? "The backup could not be restored."
        }
    }

    /// A backup that has been read and understood, but not applied.
    private struct Candidate {
        let filename: String
        let backup: LedgerBackup
        let summary: LedgerBackupSummary

        init(url: URL) throws {
            // Files from the document picker live outside the sandbox and need
            // their security scope opened first, and closed after.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)

            self.filename = url.lastPathComponent
            self.backup = try LedgerBackupCoder.decode(data)
            self.summary = LedgerBackupSummary(backup: self.backup)
        }
    }
}

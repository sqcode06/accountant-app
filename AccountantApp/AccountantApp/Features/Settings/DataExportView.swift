import SwiftUI
import AccountantCore

/// Gets your data off the phone.
///
/// Until this existed, everything you had recorded lived in one file inside the
/// app's sandbox: delete the app and it was gone, with no way to look at it
/// anywhere else. For a money app that is the wrong default, whatever else the app
/// does well.
///
/// Three files rather than one, because they answer different questions. The CSVs
/// are for reading — a spreadsheet, an accountant, your own arithmetic. The JSON
/// is the backup: ledger, budget limits and import rules together, which is what
/// it takes to put the app back the way it was. A backup holding only the ledger
/// would restore your transactions and none of your plan.
struct DataExportView: View {
    @EnvironmentObject private var appState: AppState

    @State private var bundle: ExportBundle?
    @State private var failure: String?

    var body: some View {
        List {
            if let bundle {
                Section {
                    exportRow(
                        title: "Transactions",
                        detail: "\(bundle.postingCount) rows · CSV",
                        systemImage: "tablecells",
                        url: bundle.transactions
                    )

                    exportRow(
                        title: "Accounts",
                        detail: "\(bundle.accountCount) accounts · CSV",
                        systemImage: "folder",
                        url: bundle.accounts
                    )
                } header: {
                    Text("Spreadsheet")
                } footer: {
                    Text("One row per entry side, so both halves of every transaction are there. Amounts use a dot and no thousands separator, so nothing has to be cleaned up before it opens.")
                }

                Section {
                    exportRow(
                        title: "Full backup",
                        detail: bundle.backupDetail,
                        systemImage: "arrow.down.doc",
                        url: bundle.backup
                    )
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Your transactions, budget limits and import rules in one file, in the format this app reads. Keep a copy somewhere that is not this phone.")
                }
            } else if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.deficit)

                    Button("Try again") {
                        self.failure = nil
                        Task { await prepare() }
                    }
                }
            } else {
                Section {
                    HStack(spacing: Metrics.Space.m) {
                        ProgressView()
                        Text("Preparing your files…")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Rebuilt each time the screen opens: an export is a snapshot, and a
            // stale one is worse than a slow one.
            await prepare()
        }
    }

    private func exportRow(
        title: String,
        detail: String,
        systemImage: String,
        url: URL
    ) -> some View {
        ShareLink(item: url) {
            HStack(spacing: Metrics.Space.m) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.ink)

                    Text(detail)
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer()

                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.vertical, Metrics.Space.xs)
        }
    }

    private func prepare() async {
        bundle = nil

        let ledger = appState.ledger
        let budget = appState.budget
        let rules = appState.classificationRules
        let timeZone = TimeZone.current
        let stamp = ExportBundle.stamp(for: Date())

        do {
            // Off the main actor: a long history means a lot of string building,
            // and this screen should not stutter on open.
            bundle = try await Task.detached(priority: .userInitiated) {
                try ExportBundle.write(
                    ledger: ledger,
                    budget: budget,
                    classificationRules: rules,
                    timeZone: timeZone,
                    stamp: stamp
                )
            }.value
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// The three files, written to a fresh temporary directory.
///
/// A directory per export rather than fixed filenames, so two exports in a row
/// cannot half-overwrite each other while the share sheet still holds the first.
struct ExportBundle: Sendable {
    let transactions: URL
    let accounts: URL
    let backup: URL
    let postingCount: Int
    let accountCount: Int
    let backupDetail: String

    /// UTF-8 with a byte-order mark.
    ///
    /// Excel reads a BOM-less UTF-8 CSV as the system codepage, which turns every
    /// õ, ä and ü in an account name into mojibake — and this app is built for
    /// Estonian bank statements, so that is most of them. Numbers and every sane
    /// parser ignore the mark, and our own importer strips it explicitly, so the
    /// file still round-trips back into the app.
    private static func utf8WithBOM(_ text: String) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    static func stamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func write(
        ledger: Ledger,
        budget: Budget,
        classificationRules: [ClassificationRuleConfiguration],
        timeZone: TimeZone,
        stamp: String
    ) throws -> ExportBundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let transactionsURL = directory
            .appendingPathComponent("Accountant transactions \(stamp).csv")
        let accountsURL = directory
            .appendingPathComponent("Accountant accounts \(stamp).csv")
        let backupURL = directory
            .appendingPathComponent("Accountant backup \(stamp).json")

        let transactionsCSV = LedgerExport.transactionsCSV(from: ledger, timeZone: timeZone)
        let accountsCSV = LedgerExport.accountsCSV(from: ledger)

        try utf8WithBOM(transactionsCSV).write(to: transactionsURL, options: [.atomic])
        try utf8WithBOM(accountsCSV).write(to: accountsURL, options: [.atomic])

        // All three stores in one document. The core owns the format so that a
        // backup and the files it restores cannot drift apart.
        let backupData = try LedgerBackupCoder.encode(
            LedgerBackup(
                ledger: ledger,
                budget: budget,
                classificationRules: classificationRules
            )
        )
        try backupData.write(to: backupURL, options: [.atomic])

        return ExportBundle(
            transactions: transactionsURL,
            accounts: accountsURL,
            backup: backupURL,
            postingCount: ledger.transactions.reduce(0) { $0 + $1.postings.count },
            accountCount: ledger.accounts.count,
            backupDetail: "\(ledger.transactions.count) transactions · \(budget.targets.count) limits · \(classificationRules.count) rules"
        )
    }
}

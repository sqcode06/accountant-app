import SwiftUI
import UniformTypeIdentifiers
import AccountantCore

/// Import a bank statement from a file.
///
/// Replaces a 1,079-line screen whose only way in was pasting CSV into a
/// `TextEditor` on a phone. Three steps: which bank, where it goes, and what will
/// happen — with nothing written until the last one.
///
/// The bank is a preset rather than a column-mapping exercise. Reading a Swedbank
/// export means knowing the delimiter is a semicolon, dates are `dd.MM.yyyy`,
/// amounts carry a decimal comma, direction lives in a `D`/`K` column, and row
/// type 82 is a turnover total that must not be imported. Nobody should have to
/// reconstruct that through a mapping UI.
struct ImportFlow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .source
    @State private var format: StatementFormat = .swedbank

    @State private var fileName: String?
    @State private var parsed: BankLineParseResult?
    @State private var readFailure: String?

    @State private var statementAccountID: AccountID?
    @State private var categoryAccountID: AccountID?
    @State private var feeAccountID: AccountID?

    @State private var preview: ImportPreview?
    @State private var applyReport: ImportApplyReport?

    @State private var isPickingFile = false
    @State private var isWorking = false

    private enum Step: Int, CaseIterable {
        case source, destination, review
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .source: sourceStep
                case .destination: destinationStep
                case .review: reviewStep
                }
            }
            .background(Theme.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(applyReport == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
            .appErrorAlert()
            .fileImporter(
                isPresented: $isPickingFile,
                // Deliberately permissive. Swedbank ships a CSV named ".csv.xls",
                // so filtering on comma-separated text alone would hide the most
                // common file this app will ever be handed. The contents are
                // validated after, which is the honest check anyway.
                allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data],
                allowsMultipleSelection: false,
                onCompletion: handleFileSelection
            )
        }
    }

    private var title: String {
        switch step {
        case .source: "Import"
        case .destination: "Where does it go?"
        case .review: applyReport == nil ? "Review" : "Imported"
        }
    }

    // MARK: - Step 1 — which bank, which file

    private var sourceStep: some View {
        List {
            Section {
                ForEach(StatementFormat.all) { option in
                    Button {
                        format = option
                        clearFile()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(.uiRowTitle)
                                    .foregroundStyle(Theme.ink)

                                if let note = option.note {
                                    Text(note)
                                        .font(.uiCaption)
                                        .foregroundStyle(Theme.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: Metrics.Space.s)

                            if option.id == format.id {
                                Image(systemName: "checkmark")
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, Metrics.Space.xs)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Which bank?")
            } footer: {
                Text("Each preset knows that bank's delimiter, date format and how it marks money going out.")
            }

            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label(fileName == nil ? "Choose a file" : "Choose a different file",
                          systemImage: "doc.badge.plus")
                }

                if let fileName {
                    LabeledContent("File", value: fileName)
                        .font(.uiCaption)
                }

                if let parsed {
                    LabeledContent("Rows read", value: "\(parsed.lines.count)")
                        .font(.uiCaption)

                    if parsed.hasRowErrors {
                        LabeledContent("Rows with problems", value: "\(parsed.rowErrors.count)")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.pending)
                    }
                }

                if let readFailure {
                    Text(readFailure)
                        .font(.uiCaption)
                        .foregroundStyle(Theme.deficit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Statement file")
            }

            if parsed?.lines.isEmpty == false {
                Section {
                    Button {
                        prepareDestinations()
                        step = .destination
                    } label: {
                        Text("Continue")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.inkInverse)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.accent, in: RoundedRectangle(
                                cornerRadius: Metrics.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Step 2 — accounts

    private var destinationStep: some View {
        List {
            Section {
                accountPicker(
                    title: "Statement account",
                    accounts: balanceAccounts,
                    selection: $statementAccountID
                )
            } footer: {
                Text("The account this statement belongs to. Its balance is what these lines move.")
            }

            Section {
                accountPicker(
                    title: "Uncategorised",
                    accounts: categoryAccounts,
                    selection: $categoryAccountID
                )
            } footer: {
                Text("Where lines land when no rule matches. You can recategorise them during review.")
            }

            if format.columns.fee != nil {
                Section {
                    accountPicker(
                        title: "Fees",
                        accounts: categoryAccounts,
                        selection: $feeAccountID
                    )
                } footer: {
                    Text("\(format.name) lists fees separately. Without somewhere to put them, lines carrying a fee will not import.")
                }
            }

            Section {
                Button {
                    buildPreview()
                } label: {
                    Text(isWorking ? "Reading…" : "Preview import")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.inkInverse)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.accent, in: RoundedRectangle(
                            cornerRadius: Metrics.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canPreview || isWorking)
                .opacity(canPreview && !isWorking ? 1 : 0.4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func accountPicker(
        title: String,
        accounts: [Account],
        selection: Binding<AccountID?>
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Choose").tag(AccountID?.none)

            ForEach(accounts, id: \.id) { account in
                Text(account.name).tag(Optional(account.id))
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - Step 3 — review

    private var reviewStep: some View {
        List {
            if let report = applyReport {
                Section {
                    VStack(alignment: .leading, spacing: Metrics.Space.s) {
                        Label("Imported", systemImage: "checkmark.circle.fill")
                            .font(.uiTitle)
                            .foregroundStyle(Theme.cleared)

                        Text("\(report.insertedTransactions) added to review. Confirm them from Activity when you are ready.")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .heroCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else if let preview {
                Section {
                    ImportSummary(preview: preview, rowErrors: parsed?.rowErrors ?? [])
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                outcomeSection("Ready", preview.readyOutcomes, tint: Theme.cleared)
                outcomeSection("With warnings", preview.warningOutcomes, tint: Theme.pending)
                outcomeSection("Already imported", preview.duplicateOutcomes, tint: Theme.inkMuted)
                outcomeSection("Not imported", preview.failedOutcomes, tint: Theme.deficit)

                if let rowErrors = parsed?.rowErrors, !rowErrors.isEmpty {
                    Section {
                        ForEach(rowErrors, id: \.row) { error in
                            Text(ImportMessages.rowError(error, accounts: appState.ledger.accounts))
                                .font(.uiCaption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    } header: {
                        Text("Rows that could not be read")
                    } footer: {
                        Text("These lines are skipped. Everything else still imports.")
                    }
                }

                Section {
                    Button {
                        apply()
                    } label: {
                        Text(isWorking ? "Importing…" : "Import \(preview.importableCount)")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.inkInverse)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Theme.accent, in: RoundedRectangle(
                                cornerRadius: Metrics.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(preview.importableCount == 0 || isWorking)
                    .opacity(preview.importableCount == 0 || isWorking ? 0.4 : 1)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Imported lines arrive as drafts. Nothing is confirmed until you review it.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func outcomeSection(
        _ title: String,
        _ outcomes: [ImportLineOutcome],
        tint: Color
    ) -> some View {
        if !outcomes.isEmpty {
            Section {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                    ImportOutcomeRow(
                        outcome: outcome,
                        accounts: appState.ledger.accounts
                    )
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(outcomes.count)").foregroundStyle(tint)
                }
            }
        }
    }

    // MARK: - Actions

    private func clearFile() {
        fileName = nil
        parsed = nil
        readFailure = nil
        preview = nil
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        clearFile()

        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result {
                readFailure = error.localizedDescription
            }
            return
        }

        fileName = url.lastPathComponent

        do {
            let text = try StatementFile.readText(at: url)
            parsed = try format.makeParser(source: format.name).parseLines(text)

            if parsed?.lines.isEmpty == true {
                readFailure = parsed?.hasRowErrors == true
                    ? "No rows could be read. This may be the wrong bank format."
                    : "No transactions found in this file."
            }
        } catch let error as BankLineParseError {
            // Structural failures usually mean the wrong preset, so say that
            // rather than only naming the missing column.
            readFailure = ImportMessages.parseError(error)
        } catch {
            readFailure = error.localizedDescription
        }
    }

    /// Guesses the accounts so the common case is one tap.
    private func prepareDestinations() {
        if statementAccountID == nil {
            statementAccountID = balanceAccounts.first {
                $0.name.localizedCaseInsensitiveContains(format.name)
            }?.id ?? balanceAccounts.first?.id
        }

        if categoryAccountID == nil {
            categoryAccountID = categoryAccounts.first {
                $0.name.localizedCaseInsensitiveContains("uncategor")
            }?.id ?? categoryAccounts.first?.id
        }

        if feeAccountID == nil {
            feeAccountID = categoryAccounts.first {
                $0.name.localizedCaseInsensitiveContains("fee")
            }?.id
        }
    }

    private var canPreview: Bool {
        statementAccountID != nil && categoryAccountID != nil
    }

    private func buildPreview() {
        guard
            let lines = parsed?.lines,
            let statementAccountID,
            let categoryAccountID
        else { return }

        isWorking = true

        let pipeline = makePipeline(statementAccountID, categoryAccountID)
        preview = pipeline.previewImport(
            lines: lines,
            into: appState.ledger,
            classifier: appState.transactionClassifier()
        )

        isWorking = false
        step = .review
    }

    private func apply() {
        guard
            let preview,
            let statementAccountID,
            let categoryAccountID
        else { return }

        isWorking = true

        Task {
            applyReport = await appState.applyImportPreview(
                preview,
                using: makePipeline(statementAccountID, categoryAccountID)
            )
            isWorking = false
        }
    }

    private func makePipeline(
        _ statement: AccountID,
        _ category: AccountID
    ) -> ImportPipeline {
        ImportPipeline(
            source: format.name,
            statementAccountID: statement,
            defaultCounterpartyAccountID: category,
            feeAccountID: feeAccountID
        )
    }

    // MARK: - Derived

    private var balanceAccounts: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && ($0.kind == .asset || $0.kind == .liability) }
            .sortedForDisplay()
    }

    private var categoryAccounts: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && ($0.kind == .expense || $0.kind == .income) }
            .sortedForDisplay()
    }
}

// MARK: - Summary

private struct ImportSummary: View {
    let preview: ImportPreview
    let rowErrors: [BankLineRowError]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.m) {
            Text("\(preview.importableCount) to import")
                .font(.uiTitle)
                .foregroundStyle(Theme.ink)

            HStack(spacing: Metrics.Space.xl) {
                metric("Ready", preview.readyOutcomes.count, Theme.cleared)
                metric("Warnings", preview.warningOutcomes.count, Theme.pending)
                metric("Duplicates", preview.duplicateOutcomes.count, Theme.inkMuted)
                metric("Failed", preview.failedOutcomes.count + rowErrors.count, Theme.deficit)
            }
        }
        .heroCard()
        .padding(.vertical, Metrics.Space.s)
    }

    private func metric(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.figurePrimary)
                .foregroundStyle(value == 0 ? Theme.inkFaint : tint)

            Text(label)
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
        }
    }
}

// MARK: - Row

private struct ImportOutcomeRow: View {
    let outcome: ImportLineOutcome
    let accounts: [AccountID: Account]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            HStack {
                Text(outcome.line.description)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Spacer(minLength: Metrics.Space.s)

                MoneyText(
                    money: Money(outcome.line.amount, currency: outcome.line.currency),
                    role: outcome.line.amount > .zero ? .inflow : .outflow,
                    showsPositiveSign: true
                )
            }

            HStack(spacing: Metrics.Space.xs) {
                Text(DateDisplay.transactionDate(outcome.line.date))

                if outcome.line.hasFee, let fee = outcome.line.fee {
                    Text("· fee \(MoneyDisplay.string(Money(fee, currency: outcome.line.currency)))")
                }
            }
            .font(.uiCaption)
            .foregroundStyle(Theme.inkMuted)

            if let detail {
                Text(detail)
                    .font(.uiCaption)
                    .foregroundStyle(detailTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.Space.xs)
    }

    private var detail: String? {
        switch outcome {
        case let .proposed(_, _, warnings):
            warnings.isEmpty ? nil : warnings.map(ImportMessages.warning).joined(separator: " ")
        case .skippedDuplicate:
            "Already imported."
        case let .failed(_, error):
            ImportMessages.importError(error, accounts: accounts)
        }
    }

    private var detailTint: Color {
        switch outcome {
        case .proposed: Theme.pending
        case .skippedDuplicate: Theme.inkMuted
        case .failed: Theme.deficit
        }
    }
}

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
    // Keep explanations tied to the rules that produced this preview.
    @State private var previewRules: [ClassificationRuleConfiguration] = []
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
                if step != .source && applyReport == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Back") {
                            step = step == .review ? .destination : .source
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier("import.back")
                    }
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
                    .accessibilityIdentifier("import.format.\(option.id)")
                }
            } header: {
                Text("Which bank?")
            } footer: {
                Text("Each preset knows that bank's delimiter, date format and how it marks money going out.")
            }

            Section {
                Button {
                    chooseFile()
                } label: {
                    Label(fileName == nil ? "Choose a file" : "Choose a different file",
                          systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("import.file")

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
                    .accessibilityIdentifier("import.continue")
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
                .accessibilityIdentifier("import.statementAccount")
            } footer: {
                Text("The account this statement belongs to. Its balance is what these lines move.")
            }

            Section {
                accountPicker(
                    title: "Uncategorised",
                    accounts: categoryAccounts,
                    selection: $categoryAccountID
                )
                .accessibilityIdentifier("import.defaultCategory")
            } footer: {
                Text("The starting category for each line. A matching category rule can replace it. You can change categories in Review after importing.")
            }

            if format.columns.fee != nil {
                Section {
                    accountPicker(
                        title: "Fees",
                        accounts: categoryAccounts,
                        selection: $feeAccountID
                    )
                    .accessibilityIdentifier("import.feeCategory")
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
                .accessibilityIdentifier("import.preview")
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
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("import.result")
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

                outcomeSection("Ready", in: preview, tint: Theme.cleared) {
                    if case let .proposed(_, _, warnings) = $0 { return warnings.isEmpty }
                    return false
                }
                outcomeSection("With warnings", in: preview, tint: Theme.pending) {
                    if case let .proposed(_, _, warnings) = $0 { return !warnings.isEmpty }
                    return false
                }
                outcomeSection("Already imported", in: preview, tint: Theme.inkMuted) {
                    if case .skippedDuplicate = $0 { return true }
                    return false
                }
                outcomeSection("Not imported", in: preview, tint: Theme.deficit) {
                    if case .failed = $0 { return true }
                    return false
                }

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
                    .accessibilityIdentifier("import.apply")
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
        in preview: ImportPreview,
        tint: Color,
        matching: (ImportLineOutcome) -> Bool
    ) -> some View {
        let indices = preview.outcomes.indices.filter { matching(preview.outcomes[$0]) }
        if !indices.isEmpty {
            Section {
                ForEach(indices, id: \.self) { index in
                    ImportOutcomeRow(
                        index: index,
                        outcome: preview.outcomes[index],
                        evaluation: previewRules.evaluate(description: preview.outcomes[index].line.description),
                        accounts: appState.ledger.accounts
                    )
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(indices.count)").foregroundStyle(tint)
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
        previewRules = []
    }

    private func chooseFile() {
        #if DEBUG
        if let url = AppUITestFixture.importStatementURL() {
            handleFileSelection(.success([url]))
            return
        }
        #endif
        isPickingFile = true
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
        previewRules = appState.applicableClassificationRules
        preview = pipeline.previewImport(
            lines: lines,
            into: appState.ledger,
            classifier: ClassificationRuleConfiguration.makeClassifier(from: previewRules)
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
    let index: Int
    let outcome: ImportLineOutcome
    let evaluation: ClassificationRuleEvaluation
    let accounts: [AccountID: Account]

    private var identifier: String { "import.row.\(index)" }

    private var draftDetails: DraftReviewDetails? {
        guard case let .proposed(_, draft, _) = outcome else { return nil }
        return DraftReviewDetails(transaction: draft, accounts: accounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.xs) {
            HStack {
                Text(outcome.line.description)
                    .font(.uiRowTitle)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Metrics.Space.s)

                MoneyText(
                    money: Money(outcome.line.amount, currency: outcome.line.currency),
                    role: outcome.line.amount > .zero ? .inflow : .outflow,
                    showsPositiveSign: true
                )
            }

            Text(DateDisplay.transactionDate(outcome.line.date))
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)

            if let draftDetails {
                Text("Category: \(draftDetails.categoryName)")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("\(identifier).category")

                Text("Transaction description: \(draftDetails.title)")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("\(identifier).memo")

                Text(ruleExplanation)
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).rule")

                if !draftDetails.feePostings.isEmpty {
                    Text(draftDetails.feePostings.map { posting in
                        "Fee: \(MoneyDisplay.string(posting.money)) · \(accounts[posting.accountID]?.name ?? "Unknown category")"
                    }.joined(separator: "; "))
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityIdentifier("\(identifier).fee")
                }
            }

            if let detail {
                Text(detail)
                    .font(.uiCaption)
                    .foregroundStyle(detailTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.Space.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel([outcome.line.description, detail].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier(identifier)
    }

    private var ruleExplanation: String {
        guard !evaluation.matches.isEmpty else {
            return "No active rule matched. Using the starting category and bank description."
        }
        let matched = evaluation.matches.map { "“\($0.needle)”" }.joined(separator: ", ")
        let category = winnerName(evaluation.counterpartyWinnerRuleID)
            .map { "Category from rule \($0)." } ?? "Starting category kept."
        let memo = winnerName(evaluation.memoWinnerRuleID)
            .map { "Description from rule \($0)." } ?? "Bank description kept."
        return "Matched \(matched). \(category) \(memo)"
    }

    private func winnerName(_ id: UUID?) -> String? {
        guard let id, let match = evaluation.matches.first(where: { $0.id == id }) else { return nil }
        return "“\(match.needle)”"
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

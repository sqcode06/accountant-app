import SwiftUI
import AccountantCore

struct ImportPreviewScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var source = "CSV Import"
    @State private var csvText = Self.sampleCSV
    @State private var selectedStatementAccountID: AccountID?
    @State private var selectedCounterpartyAccountID: AccountID?
    @State private var preview: ImportPreview?
    @State private var previewPipeline: ImportPipeline?
    @State private var parseErrorMessage: String?
    @State private var applyReport: ImportApplyReport?
    @State private var isApplying = false
    @State private var isBuildingPreview = false
    @State private var previewConfiguration: ImportPreviewConfiguration?
    @State private var newRuleNeedle = ""
    @State private var newRuleMemo = ""
    @State private var newRuleCounterpartyAccountID: AccountID?

    var body: some View {
        ScrollView {
            content
                .padding()
        }
        .background {
            importBackground
        }
        .onAppear(perform: ensureDefaultSelections)
        .onChange(of: source) { _, _ in
            resetPreview()
        }
        .onChange(of: selectedStatementAccountID) { _, _ in
            resetPreview()
        }
        .onChange(of: selectedCounterpartyAccountID) { _, _ in
            resetPreview()
        }
        .onChange(of: appState.classificationRules) { _, _ in
            resetPreview()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            ImportHeroCard()
            missingAccountsSection
            sourceSection
            classificationRulesSection
            csvInputSection
            parseErrorSection
            previewResultsSection
        }
    }

    @ViewBuilder
    private var missingAccountsSection: some View {
        if statementAccounts.isEmpty || counterpartyAccounts.isEmpty {
            ImportMissingAccountsCard(
                needsStatementAccount: statementAccounts.isEmpty,
                needsCounterpartyAccount: counterpartyAccounts.isEmpty
            )
        }
    }

    private var sourceSection: some View {
        ImportPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Statement source")
                    .font(.headline)

                TextField("Source name", text: $source)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)

                Picker("Statement account", selection: $selectedStatementAccountID) {
                    Text("Select account").tag(AccountID?.none)
                    ForEach(statementAccounts, id: \.id) { account in
                        Text(accountPickerTitle(account)).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)

                Picker("Fallback counterparty", selection: $selectedCounterpartyAccountID) {
                    Text("Select account").tag(AccountID?.none)
                    ForEach(counterpartyAccounts, id: \.id) { account in
                        Text(accountPickerTitle(account)).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var classificationRulesSection: some View {
        ImportClassificationRulesPanel(
            rules: appState.classificationRules,
            accounts: appState.ledger.accounts,
            applicableRuleCount: appState.applicableClassificationRuleCount,
            counterpartyAccounts: counterpartyAccounts,
            selectedCounterpartyAccountID: $newRuleCounterpartyAccountID,
            needle: $newRuleNeedle,
            cleanedMemo: $newRuleMemo,
            onAdd: addClassificationRule,
            onDelete: deleteClassificationRule
        )
    }

    private var csvInputSection: some View {
        ImportPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CSV input")
                        .font(.headline)

                    Spacer()

                    Button("Use sample CSV") {
                        csvText = Self.sampleCSV
                        resetPreview()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Expected columns: date, amount, currency, description, external_id. Custom bank-specific mapping can come later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $csvText)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 170)
                    .padding(8)
                    .background(
                        Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .onChange(of: csvText) { _, _ in
                        resetPreview()
                    }

                previewButton
            }
        }
    }

    private var previewButton: some View {
        Button {
            Task {
                await buildPreview()
            }
        } label: {
            previewButtonLabel
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canPreview || isBuildingPreview)
    }

    @ViewBuilder
    private var previewButtonLabel: some View {
        if isBuildingPreview {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Label("Preview Import", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var parseErrorSection: some View {
        if let parseErrorMessage {
            ImportStatusCard(
                title: "Could not build preview",
                message: parseErrorMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    @ViewBuilder
    private var previewResultsSection: some View {
        if let preview {
            ImportPreviewResultsView(
                preview: preview,
                accounts: appState.ledger.accounts,
                applyReport: applyReport,
                isApplying: isApplying,
                onApply: {
                    Task { await applyPreview() }
                }
            )
        }
    }

    private var importBackground: some View {
        LinearGradient(
            colors: [
                Color.cyan.opacity(0.12),
                Color.indigo.opacity(0.08),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var activeAccounts: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active }
            .sortedForDisplay()
    }

    private var statementAccounts: [Account] {
        activeAccounts.filter { [.asset, .liability, .clearing].contains($0.kind) }
    }

    private var counterpartyAccounts: [Account] {
        activeAccounts.filter { [.income, .expense, .clearing].contains($0.kind) }
    }

    private var canPreview: Bool {
        selectedStatementAccountID != nil
        && selectedCounterpartyAccountID != nil
        && !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !csvText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var currentPreviewConfiguration: ImportPreviewConfiguration? {
        guard let statementAccountID = selectedStatementAccountID,
              let counterpartyAccountID = selectedCounterpartyAccountID else {
            return nil
        }

        let cleanedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCSV = csvText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedSource.isEmpty, !cleanedCSV.isEmpty else {
            return nil
        }

        return ImportPreviewConfiguration(
            source: cleanedSource,
            csvText: cleanedCSV,
            statementAccountID: statementAccountID,
            counterpartyAccountID: counterpartyAccountID,
            classificationRules: appState.classificationRules
        )
    }

    private func ensureDefaultSelections() {
        if selectedStatementAccountID == nil {
            selectedStatementAccountID = statementAccounts.first?.id
        }

        if selectedCounterpartyAccountID == nil {
            selectedCounterpartyAccountID = counterpartyAccounts.first?.id
        }

        if newRuleCounterpartyAccountID == nil {
            newRuleCounterpartyAccountID = counterpartyAccounts.first?.id
        }
    }

    @MainActor
    private func buildPreview() async {
        ensureDefaultSelections()

        guard let configuration = currentPreviewConfiguration else {
            parseErrorMessage = "Create at least one statement account and one fallback counterparty account before importing."
            preview = nil
            previewPipeline = nil
            previewConfiguration = nil
            return
        }

        let ledger = appState.ledger
        let classifier = appState.transactionClassifier()
        let dateFormats = ["yyyy-MM-dd", "dd.MM.yyyy"]

        isBuildingPreview = true
        defer { isBuildingPreview = false }

        do {
            let builtPreview = try await Task.detached(priority: .userInitiated) {
                let parser = CSVBankLineParser(
                    source: configuration.source,
                    dateFormats: dateFormats
                )

                let lines = try parser.parse(configuration.csvText)

                let pipeline = ImportPipeline(
                    source: configuration.source,
                    statementAccountID: configuration.statementAccountID,
                    defaultCounterpartyAccountID: configuration.counterpartyAccountID
                )

                return pipeline.previewImport(lines: lines, into: ledger, classifier: classifier)
            }.value

            guard currentPreviewConfiguration == configuration else {
                return
            }

            preview = builtPreview
            previewPipeline = ImportPipeline(
                source: configuration.source,
                statementAccountID: configuration.statementAccountID,
                defaultCounterpartyAccountID: configuration.counterpartyAccountID
            )
            previewConfiguration = configuration
            parseErrorMessage = nil
            applyReport = nil
        } catch {
            guard currentPreviewConfiguration == configuration else {
                return
            }

            parseErrorMessage = ImportPreviewFormatting.parseErrorMessage(error)
            preview = nil
            previewPipeline = nil
            previewConfiguration = nil
            applyReport = nil
        }
    }

    @MainActor
    private func applyPreview() async {
        guard let preview, let previewPipeline else { return }

        guard previewConfiguration == currentPreviewConfiguration else {
            parseErrorMessage = "Import settings changed. Build a new preview before applying."
            self.preview = nil
            self.previewPipeline = nil
            self.previewConfiguration = nil
            applyReport = nil
            return
        }

        isApplying = true
        defer { isApplying = false }

        if let report = await appState.applyImportPreview(preview, using: previewPipeline) {
            applyReport = report
        }
    }

    private func resetPreview() {
        preview = nil
        previewPipeline = nil
        previewConfiguration = nil
        parseErrorMessage = nil
        applyReport = nil
    }

    private func addClassificationRule() {
        Task {
            let success = await appState.createDescriptionContainsRule(
                needle: newRuleNeedle,
                counterpartyAccountID: newRuleCounterpartyAccountID,
                cleanedMemo: newRuleMemo
            )

            guard success else { return }

            newRuleNeedle = ""
            newRuleMemo = ""
            resetPreview()
        }
    }

    private func deleteClassificationRule(_ rule: ClassificationRuleConfiguration) {
        Task {
            _ = await appState.deleteClassificationRule(id: rule.id)
            resetPreview()
        }
    }

    private func accountPickerTitle(_ account: Account) -> String {
        "\(account.name) · \(account.kind.displayName)"
    }

    private static let sampleCSV = """
    date,amount,currency,description,external_id
    2026-05-01,-12.34,EUR,"Coffee, croissant",CARD-1
    2026-05-02,1000.00,EUR,Salary,SALARY-1
    2026-05-03,-8.90,EUR,Parking,
    """
}

private struct ImportHeroCard: View {
    var body: some View {
        ImportPanel {
            HStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Import preview")
                        .font(.title2.bold())

                    Text("Paste statement CSV, review proposed drafts, inspect warnings and failures, then apply only the safe draft set.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ImportMissingAccountsCard: View {
    let needsStatementAccount: Bool
    let needsCounterpartyAccount: Bool

    var body: some View {
        ImportStatusCard(
            title: "Import needs accounts first",
            message: missingMessage,
            systemImage: "person.crop.circle.badge.exclamationmark",
            tint: .orange
        )
    }

    private var missingMessage: String {
        var parts: [String] = []

        if needsStatementAccount {
            parts.append("a statement account such as Bank, Card, or Clearing")
        }

        if needsCounterpartyAccount {
            parts.append("a fallback counterparty such as Uncategorized, Groceries, or Salary")
        }

        return "Create \(parts.joined(separator: " and ")) in Accounts before previewing imports."
    }
}


private struct ImportClassificationRulesPanel: View {
    let rules: [ClassificationRuleConfiguration]
    let accounts: [AccountID: Account]
    let applicableRuleCount: Int
    let counterpartyAccounts: [Account]
    @Binding var selectedCounterpartyAccountID: AccountID?
    @Binding var needle: String
    @Binding var cleanedMemo: String
    let onAdd: () -> Void
    let onDelete: (ClassificationRuleConfiguration) -> Void

    var body: some View {
        ImportPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Classification rules")
                            .font(.headline)

                        Spacer()

                        Text("\(applicableRuleCount) applicable")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Text("Match statement descriptions and replace the fallback account or memo before previewing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Description contains, e.g. RIMI", text: $needle)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    Picker("Set counterparty", selection: $selectedCounterpartyAccountID) {
                        Text("Keep fallback account").tag(AccountID?.none)
                        ForEach(counterpartyAccounts, id: \.id) { account in
                            Text("\(account.name) · \(account.kind.displayName)").tag(Optional(account.id))
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Clean memo, optional", text: $cleanedMemo)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        onAdd()
                    } label: {
                        Label("Add rule", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAddRule)
                }

                if rules.isEmpty {
                    Text("No rules yet. Imported rows will use the selected fallback counterparty until a rule matches.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(rules) { rule in
                            ImportClassificationRuleCard(
                                rule: rule,
                                targetSummary: targetSummary(for: rule),
                                onDelete: { onDelete(rule) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var canAddRule: Bool {
        !needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (selectedCounterpartyAccountID != nil || !cleanedMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func targetSummary(for rule: ClassificationRuleConfiguration) -> String {
        var parts: [String] = []

        if let accountID = rule.counterpartyAccountID,
           let account = accounts[accountID] {
            parts.append(account.name)
        } else if rule.counterpartyAccountID != nil {
            parts.append("Unknown account")
        }

        if let memo = rule.cleanedMemo {
            parts.append("Memo: \(memo)")
        }

        return parts.isEmpty ? "No active target" : parts.joined(separator: " · ")
    }
}

private struct ImportClassificationRuleCard: View {
    let rule: ClassificationRuleConfiguration
    let targetSummary: String
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: rule.isEnabled ? "wand.and.stars" : "wand.and.stars.inverse")
                .foregroundStyle(rule.isEnabled ? .purple : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text("Contains “\(rule.needle)”")
                    .font(.subheadline.bold())
                Text(targetSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ImportPreviewResultsView: View {
    let preview: ImportPreview
    let accounts: [AccountID: Account]
    let applyReport: ImportApplyReport?
    let isApplying: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ImportSummaryStrip(preview: preview)

            if let applyReport {
                ImportStatusCard(
                    title: "Import applied",
                    message: "Inserted \(applyReport.insertedTransactions) draft transaction\(applyReport.insertedTransactions == 1 ? "" : "s") and skipped \(applyReport.skippedOutcomes) outcome\(applyReport.skippedOutcomes == 1 ? "" : "s").",
                    systemImage: "checkmark.seal.fill",
                    tint: .green
                )
            }

            ImportOutcomeSection(
                title: "Ready drafts",
                subtitle: "Clean proposed drafts with no warnings.",
                outcomes: preview.proposedOutcomes,
                accounts: accounts
            )

            ImportOutcomeSection(
                title: "Warnings",
                subtitle: "These rows can import, but deserve attention.",
                outcomes: preview.warningOutcomes,
                accounts: accounts
            )

            ImportOutcomeSection(
                title: "Skipped duplicates",
                subtitle: "These already appear to exist in the ledger.",
                outcomes: preview.skippedOutcomes,
                accounts: accounts
            )

            ImportOutcomeSection(
                title: "Failed rows",
                subtitle: "These rows will not be imported.",
                outcomes: preview.failedOutcomes,
                accounts: accounts
            )

            Button {
                onApply()
            } label: {
                if isApplying {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Apply Importable Drafts", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(preview.importableCount == 0 || isApplying || applyReport != nil)
        }
    }
}

private struct ImportSummaryStrip: View {
    let preview: ImportPreview

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ImportMetricPill(title: "Ready", value: preview.proposedCount, systemImage: "doc.badge.plus", tint: .blue)
            ImportMetricPill(title: "Warnings", value: preview.warningCount, systemImage: "exclamationmark.triangle", tint: .orange)
            ImportMetricPill(title: "Duplicates", value: preview.skippedCount, systemImage: "doc.on.doc", tint: .secondary)
            ImportMetricPill(title: "Failed", value: preview.failedCount, systemImage: "xmark.octagon", tint: .red)
        }
    }
}

private struct ImportMetricPill: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        ImportPanel {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(value)")
                        .font(.title3.bold())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }
}

private struct ImportOutcomeSection: View {
    let title: String
    let subtitle: String
    let outcomes: [(offset: Int, outcome: ImportLineOutcome)]
    let accounts: [AccountID: Account]

    var body: some View {
        if !outcomes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(outcomes, id: \.offset) { item in
                        ImportOutcomeCard(
                            index: item.offset + 1,
                            outcome: item.outcome,
                            accounts: accounts
                        )
                    }
                }
            }
        }
    }
}

private struct ImportOutcomeCard: View {
    let index: Int
    let outcome: ImportLineOutcome
    let accounts: [AccountID: Account]

    var body: some View {
        ImportPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(amountText)
                            .font(.subheadline.monospacedDigit().bold())
                    }

                    details
                }
            }
        }
    }

    private var title: String {
        switch outcome {
        case .proposed(let line, _, _), .skippedDuplicate(let line, _, _), .failed(let line, _):
            "#\(index) · \(line.description)"
        }
    }

    private var subtitle: String {
        switch outcome {
        case .proposed(let line, _, _), .skippedDuplicate(let line, _, _), .failed(let line, _):
            ImportPreviewFormatting.lineSubtitle(line)
        }
    }

    private var amountText: String {
        switch outcome {
        case .proposed(let line, _, _), .skippedDuplicate(let line, _, _), .failed(let line, _):
            MoneyDisplay.string(amount: line.amount, currency: line.currency)
        }
    }

    private var systemImage: String {
        switch outcome {
        case .proposed:
            "doc.badge.plus"
        case .skippedDuplicate:
            "doc.on.doc"
        case .failed:
            "xmark.octagon"
        }
    }

    private var tint: Color {
        switch outcome {
        case .proposed:
            .blue
        case .skippedDuplicate:
            .secondary
        case .failed:
            .red
        }
    }

    @ViewBuilder
    private var details: some View {
        switch outcome {
        case .proposed(_, let draft, let warnings):
            VStack(alignment: .leading, spacing: 6) {
                Text(accountRoute(for: draft))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if warnings.isEmpty {
                    ImportChip(text: "Proposed draft", tint: .blue)
                } else {
                    ForEach(warnings.indices, id: \.self) { index in
                        ImportChip(
                            text: ImportPreviewFormatting.warningMessage(warnings[index]),
                            tint: .orange
                        )
                    }
                }
            }

        case .skippedDuplicate(_, let origin, let existingTransactionID):
            VStack(alignment: .leading, spacing: 6) {
                ImportChip(text: "Duplicate external ID: \(origin.externalID)", tint: .secondary)
                Text("Existing transaction: \(ImportPreviewFormatting.shortID(existingTransactionID))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .failed(_, let error):
            ImportChip(
                text: ImportPreviewFormatting.importErrorMessage(error),
                tint: .red
            )
        }
    }

    private func accountRoute(for transaction: AccountantCore.Transaction) -> String {
        let names = transaction.postings
            .enumerated()
            .sorted { lhs, rhs in
                let lhsIsNegative = lhs.element.money.amount < .zero
                let rhsIsNegative = rhs.element.money.amount < .zero

                if lhsIsNegative != rhsIsNegative {
                    return lhsIsNegative && !rhsIsNegative
                }

                return lhs.offset < rhs.offset
            }
            .compactMap { accounts[$0.element.accountID]?.name }

        return names.isEmpty ? "Unmapped accounts" : names.joined(separator: " → ")
    }
}

private struct ImportChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct ImportStatusCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        ImportPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ImportPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            }
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
    }
}

private extension ImportPreview {
    var indexedOutcomes: [(offset: Int, outcome: ImportLineOutcome)] {
        outcomes.enumerated().map { (offset: $0.offset, outcome: $0.element) }
    }

    var importableOutcomes: [(offset: Int, outcome: ImportLineOutcome)] {
        indexedOutcomes.filter { item in
            if case .proposed = item.outcome {
                return true
            }

            return false
        }
    }

    var proposedOutcomes: [(offset: Int, outcome: ImportLineOutcome)] {
        indexedOutcomes.filter { item in
            if case .proposed(_, _, let warnings) = item.outcome {
                return warnings.isEmpty
            }

            return false
        }
    }

    var warningOutcomes: [(offset: Int, outcome: ImportLineOutcome)] {
        indexedOutcomes.filter { item in
            if case .proposed(_, _, let warnings) = item.outcome {
                return !warnings.isEmpty
            }

            return false
        }
    }

    var skippedOutcomes: [(offset: Int, outcome: ImportLineOutcome)] {
        indexedOutcomes.filter { item in
            if case .skippedDuplicate = item.outcome {
                return true
            }

            return false
        }
    }

    var failedOutcomes: [(offset: Int, outcome: ImportLineOutcome)] {
        indexedOutcomes.filter { item in
            if case .failed = item.outcome {
                return true
            }

            return false
        }
    }

    var importableCount: Int { importableOutcomes.count }
    var proposedCount: Int { proposedOutcomes.count }
    var skippedCount: Int { skippedOutcomes.count }
    var failedCount: Int { failedOutcomes.count }
    var warningCount: Int { warningOutcomes.count }
}

private enum ImportPreviewFormatting {
    static func parseErrorMessage(_ error: Error) -> String {
        guard let error = error as? BankLineParseError else {
            return error.localizedDescription
        }

        switch error {
        case .emptyInput:
            return "The CSV input is empty."
        case .missingHeader:
            return "The CSV file has no header row."
        case .missingRequiredColumn(let column):
            return "Missing required column: \(column)."
        case .rowColumnCountMismatch(let row, let expected, let actual):
            return "Row \(row) has \(actual) columns, but the header has \(expected)."
        case .missingRequiredValue(let row, let column):
            return "Row \(row) is missing a value for \(column)."
        case .invalidDate(let row, let column, let value, let expectedFormats):
            return "Row \(row) has invalid \(column) date \(value). Expected: \(expectedFormats.joined(separator: ", "))."
        case .invalidAmount(let row, let column, let value):
            return "Row \(row) has invalid \(column) amount \(value)."
        case .invalidCurrency(let row, let column, let value):
            return "Row \(row) has invalid \(column) currency \(value). Use a three-letter code like EUR."
        case .malformedCSV(let row, let message):
            return "Row \(row) is malformed: \(message)"
        }
    }

    static func importErrorMessage(_ error: ImportError) -> String {
        switch error {
        case .unknownAccount(let accountID):
            return "Unknown account \(shortID(accountID))."
        case .accountArchived(let accountID):
            return "Account \(shortID(accountID)) is archived."
        case .invalidTransaction:
            return "Invalid transaction."
        case .duplicateExternalIDInBatch(let origin):
            return "Duplicate external ID in this file: \(origin.externalID)."
        case .classificationFailed(let error):
            return classificationErrorMessage(error)
        }
    }

    static func warningMessage(_ warning: ImportWarning) -> String {
        switch warning {
        case .missingExternalID:
            return "Missing external ID: duplicate detection will be weaker."
        }
    }

    static func lineSubtitle(_ line: BankLine) -> String {
        var parts = [DateDisplay.transactionDate(line.date)]

        if let externalID = line.externalID {
            parts.append("ID \(externalID)")
        }

        return parts.joined(separator: " · ")
    }

    static func shortID(_ id: TransactionID?) -> String {
        guard let id else { return "unknown" }
        return String(id.rawValue.uuidString.prefix(8))
    }

    private static func shortID(_ id: AccountID) -> String {
        String(id.rawValue.uuidString.prefix(8))
    }

    private static func classificationErrorMessage(_ error: ClassificationError) -> String {
        switch error {
        case .cannotApplyToFinalized:
            return "Cannot classify a finalized transaction."
        case .statementPostingNotFound:
            return "Statement posting was not found."
        case .counterpartyPostingNotFound:
            return "Counterparty posting was not found."
        case .ambiguousCounterpartyPostings:
            return "Counterparty posting is ambiguous."
        }
    }
}

#Preview {
    NavigationStack {
        ImportPreviewScreen()
            .environmentObject(AppState(repository: ImportPreviewRepository()))
    }
}

private struct ImportPreviewRepository: LedgerRepository {
    func loadOrCreate() async throws -> Ledger {
        var ledger = Ledger()
        ledger.addAccount(Account(name: "Bank", kind: .asset))
        ledger.addAccount(Account(name: "Uncategorized", kind: .clearing))
        return ledger
    }

    func save(_ ledger: Ledger) async throws {}
}

private struct ImportPreviewConfiguration: Equatable, Sendable {
    let source: String
    let csvText: String
    let statementAccountID: AccountID
    let counterpartyAccountID: AccountID
    let classificationRules: [ClassificationRuleConfiguration]
}

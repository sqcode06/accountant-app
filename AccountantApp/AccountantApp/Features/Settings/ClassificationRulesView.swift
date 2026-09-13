import SwiftUI
import AccountantCore

/// A small, deliberate place to maintain the deterministic rules used during
/// statement import. Rule order is meaningful: the last matching rule wins.
struct ClassificationRulesView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingNewRule = false
    @State private var newRuleID = UUID()
    @State private var editingRule: ClassificationRuleConfiguration?

    var body: some View {
        List {
            Section {
                Text("Rules check description text from every imported account, including refunds and income. Matching ignores case. For category and description separately, the last matching rule that changes that field wins.")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            } header: {
                Text("How rules work")
            }

            if appState.classificationRules.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No import rules",
                        systemImage: "wand.and.stars",
                        description: Text("Add a rule for a familiar statement description, such as Rimi or a monthly subscription.")
                    )
                }
            } else {
                Section {
                    ForEach(Array(appState.classificationRules.enumerated()), id: \.element.id) { index, rule in
                        RuleRow(rule: rule, position: index + 1, onEdit: { editingRule = rule })
                            .environmentObject(appState)
                            .accessibilityIdentifier("rules.row.\(rule.id.uuidString)")
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await appState.deleteClassificationRule(id: rule.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onMove { source, destination in
                        Task {
                            _ = await appState.moveClassificationRules(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                    }
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Tap Edit, then drag to change the numbered order. Paused rules and rules with unavailable categories do not run, including their description changes.")
                }
            }

            RuleTester()
                .environmentObject(appState)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Import rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newRuleID = UUID()
                    isPresentingNewRule = true
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
                .accessibilityIdentifier("rules.add")
            }

            if !appState.classificationRules.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .accessibilityIdentifier("rules.reorder")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewRule) {
            ClassificationRuleForm(mode: .create(id: newRuleID))
                .environmentObject(appState)
        }
        .sheet(item: $editingRule) { rule in
            ClassificationRuleForm(mode: .edit(rule))
                .environmentObject(appState)
        }
        .appErrorAlert()
    }
}

private struct RuleTester: View {
    @EnvironmentObject private var appState: AppState

    @State private var sampleDescription = ""

    var body: some View {
        Section {
            TextField("e.g. RIMI EESTI", text: $sampleDescription)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("rules.tryText")

            result
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("rules.tryResult")
        } header: {
            Text("Try a description")
        } footer: {
            Text("This tests active text matches. The import preview also checks the chosen accounts and currencies. Existing transactions stay as they are.")
        }
    }

    @ViewBuilder
    private var result: some View {
        let trimmedSample = sampleDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSample.isEmpty {
            Text("Type a statement description to see which rules match.")
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)
        } else {
            let evaluation = appState.classificationRuleTest(sampleDescription: trimmedSample)

            if evaluation.matches.isEmpty {
                Text("No active rules match this description.")
                    .font(.uiCaption)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                VStack(alignment: .leading, spacing: Metrics.Space.s) {
                    Text("Matches")
                        .fieldLabel()

                    ForEach(evaluation.matches, id: \.id) { match in
                        Text(ruleReference(match))
                            .font(.uiCaption)
                            .foregroundStyle(Theme.ink)
                    }

                    Divider()

                    Text("Result")
                        .fieldLabel()

                    resultLine(
                        "Category",
                        value: categoryResult(for: evaluation),
                        winnerID: evaluation.counterpartyWinnerRuleID,
                        matches: evaluation.matches
                    )
                    resultLine(
                        "Transaction description",
                        value: evaluation.suggestion?.cleanedMemo ?? "Unchanged",
                        winnerID: evaluation.memoWinnerRuleID,
                        matches: evaluation.matches
                    )
                }
                .padding(.vertical, Metrics.Space.xs)
            }
        }
    }

    private func categoryResult(for evaluation: ClassificationRuleEvaluation) -> String {
        guard let accountID = evaluation.suggestion?.counterpartyAccountID else {
            return "Unchanged"
        }

        return appState.ledger.accounts[accountID]?.name ?? "Unavailable category"
    }

    private func resultLine(
        _ label: String,
        value: String,
        winnerID: UUID?,
        matches: [ClassificationRuleMatch]
    ) -> some View {
        let winnerName = winnerID.flatMap { id in
            matches.first(where: { $0.id == id }).map(ruleReference)
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.uiCaption)
                .foregroundStyle(Theme.inkMuted)

            Text(winnerName.map { "\(value) · from \($0)" } ?? value)
                .font(.uiRowTitle)
                .foregroundStyle(Theme.ink)
        }
    }

    private func ruleReference(_ match: ClassificationRuleMatch) -> String {
        guard let index = appState.classificationRules.firstIndex(where: { $0.id == match.id }) else {
            return "rule containing “\(match.needle)”"
        }
        return "rule \(index + 1) (“\(match.needle)”)"
    }
}

private struct RuleRow: View {
    @EnvironmentObject private var appState: AppState

    let rule: ClassificationRuleConfiguration
    let position: Int
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: Metrics.Space.m) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(position). Contains \u{201c}\(rule.needle)\u{201d}")
                        .font(.uiRowTitle)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)

                    Text(summary)
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(2)

                    if let unavailableReason {
                        Label(rule.isEnabled ? "Not running: \(unavailableReason)" : unavailableReason,
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.pending)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Metrics.Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rules.edit.\(rule.id.uuidString)")

            Spacer(minLength: Metrics.Space.s)

            Toggle("Enable rule containing \(rule.needle)", isOn: enabledBinding)
                .labelsHidden()
                .tint(Theme.accent)
                .accessibilityIdentifier("rules.enabled.\(rule.id.uuidString)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rule \(position). Contains \(rule.needle). \(summary)")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { isEnabled in
                Task {
                    _ = await appState.setClassificationRuleEnabled(
                        id: rule.id,
                        isEnabled: isEnabled
                    )
                }
            }
        )
    }

    private var unavailableReason: String? {
        appState.classificationRuleUnavailableReason(rule)
    }

    private var summary: String {
        var parts: [String] = []

        if let accountID = rule.counterpartyAccountID {
            let name = appState.ledger.accounts[accountID]?.name ?? "Missing category"
            parts.append("category: \(name)")
        }

        if let memo = rule.cleanedMemo {
            parts.append("transaction description: \u{201c}\(memo)\u{201d}")
        }

        if !rule.isEnabled {
            parts.append("paused")
        }

        return parts.isEmpty ? "No result selected" : parts.joined(separator: " \u{00b7} ")
    }
}

private struct ClassificationRuleForm: View {
    enum Mode {
        case create(id: UUID)
        case edit(ClassificationRuleConfiguration)
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private let id: UUID
    private let existingName: String?
    private let isCreating: Bool

    @State private var needle: String
    @State private var categoryID: AccountID?
    @State private var memo: String
    @State private var isEnabled: Bool
    @State private var isSaving = false

    init(mode: Mode) {
        switch mode {
        case let .create(id):
            self.id = id
            self.existingName = nil
            self.isCreating = true
            _needle = State(initialValue: "")
            _categoryID = State(initialValue: nil)
            _memo = State(initialValue: "")
            _isEnabled = State(initialValue: true)
        case let .edit(rule):
            self.id = rule.id
            // Preserve custom names from backups while letting automatically
            // derived names follow an edited description or match text.
            self.existingName = rule.name == (rule.cleanedMemo ?? rule.needle) ? nil : rule.name
            self.isCreating = false
            _needle = State(initialValue: rule.needle)
            _categoryID = State(initialValue: rule.counterpartyAccountID)
            _memo = State(initialValue: rule.cleanedMemo ?? "")
            _isEnabled = State(initialValue: rule.isEnabled)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Matching statement description")
                        .fieldLabel()

                    TextField("e.g. Rimi or Netflix", text: $needle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("rules.matchText")

                    Text("Matches any part of a statement description, ignoring upper and lower case.")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                } header: {
                    Text("When this statement description appears")
                }

                Section {
                    Picker("Category", selection: $categoryID) {
                        Text("Keep category unchanged").tag(AccountID?.none)

                        ForEach(activeCategories, id: \.id) { account in
                            Text(account.name).tag(Optional(account.id))
                        }

                        if let unavailableCategory {
                            Text("\(unavailableCategory.name) — unavailable")
                                .tag(Optional(unavailableCategory.id))
                        }
                    }
                    .tint(Theme.accent)
                    .accessibilityIdentifier("rules.category")

                    if unavailableCategory != nil {
                        Label(
                            unavailableCategoryReason,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.uiCaption)
                        .foregroundStyle(Theme.pending)
                    }

                    Text("Transaction description (optional)")
                        .fieldLabel()

                    TextField("e.g. Weekly groceries", text: $memo)
                        .accessibilityIdentifier("rules.memo")

                    Text("Choose a category, set a clearer transaction description, or do both.")
                        .font(.uiCaption)
                        .foregroundStyle(Theme.inkMuted)
                } header: {
                    Text("Then change the transaction")
                }

                Section {
                    Toggle("Rule is active", isOn: $isEnabled)
                        .tint(Theme.accent)

                    if !isEnabled {
                        Text("Paused rules are kept for later and do not run during import.")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.uiCaption)
                            .foregroundStyle(Theme.pending)
                    }
                }
            }
            .navigationTitle(isCreating ? "New rule" : "Edit rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("rules.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("rules.save")
                }
            }
            .appErrorAlert()
        }
    }

    private var activeCategories: [Account] {
        appState.ledger.accounts.values
            .filter { $0.status == .active && ($0.kind == .expense || $0.kind == .income) }
            .sortedForDisplay()
    }

    private var unavailableCategory: Account? {
        guard let categoryID, !activeCategories.contains(where: { $0.id == categoryID }) else {
            return nil
        }

        return appState.ledger.accounts[categoryID]
            ?? Account(id: categoryID, name: "Missing category", kind: .expense)
    }

    private var unavailableCategoryReason: String {
        guard var rule = currentRule else {
            return "This category is unavailable. Choose an active category or pause the rule."
        }
        rule.isEnabled = true
        return appState.classificationRuleUnavailableReason(rule)
            ?? "This category is unavailable. Choose an active category or pause the rule."
    }

    private var currentRule: ClassificationRuleConfiguration? {
        let normalizedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNeedle.isEmpty else { return nil }

        return ClassificationRuleConfiguration(
            id: id,
            name: existingName,
            needle: normalizedNeedle,
            counterpartyAccountID: categoryID,
            cleanedMemo: memo,
            isEnabled: isEnabled
        )
    }

    private var validationMessage: String? {
        let trimmedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedNeedle.isEmpty {
            return "Enter a statement description to match."
        }

        if categoryID == nil && trimmedMemo.isEmpty {
            return "Choose a category, enter a transaction description, or do both."
        }

        if isEnabled && unavailableCategory != nil {
            return "An active rule needs an available category. Choose another category or pause this rule."
        }

        return nil
    }

    private var canSave: Bool { validationMessage == nil }

    private func save() {
        guard let rule = currentRule, canSave else { return }
        isSaving = true

        Task {
            let saved: Bool

            if isCreating {
                saved = await appState.createDescriptionContainsRule(
                    needle: rule.needle,
                    counterpartyAccountID: rule.counterpartyAccountID,
                    cleanedMemo: rule.cleanedMemo,
                    id: id,
                    isEnabled: rule.isEnabled
                )
            } else {
                saved = await appState.updateClassificationRule(rule)
            }

            isSaving = false

            if saved {
                dismiss()
            }
        }
    }
}

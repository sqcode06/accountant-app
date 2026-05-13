import Foundation

public protocol ClassificationRule: Sendable {
    func classify(line: BankLine, current transaction: Transaction) -> ClassificationSuggestion?
}

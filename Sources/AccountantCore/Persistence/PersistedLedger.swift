import Foundation

public struct PersistedLedger: Codable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let savedAt: Date
    public let ledger: Ledger

    public init(schemaVersion: Int = Self.currentSchemaVersion, savedAt: Date = Date(), ledger: Ledger) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.ledger = ledger
    }
}

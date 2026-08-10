import Foundation

public struct PersistedLedger: Codable, Sendable {
    /// Version 4 adds account currency, display ordering and icon/colour tokens,
    /// plus per-posting cleared state.
    ///
    /// Decoding stays tolerant of version 3 files: every field introduced in 4 has
    /// a default, so an older ledger loads with no declared currencies and nothing
    /// marked cleared — which is exactly the correct reading of a file written
    /// before those concepts existed.
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    public let savedAt: Date
    public let ledger: Ledger

    public init(schemaVersion: Int = Self.currentSchemaVersion, savedAt: Date = Date(), ledger: Ledger) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.ledger = ledger
    }
}

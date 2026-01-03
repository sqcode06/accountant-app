import Foundation

public enum LedgerStoreError: Error, Equatable {
    case fileNotFound
    case unsupportedSchemaVersion(Int)
}

public protocol LedgerStore: Sendable {
    func load() throws -> Ledger
    func save(_ ledger: Ledger) throws
}

public struct JSONLedgerStore: LedgerStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LedgerStoreError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        let persisted = try decoder.decode(PersistedLedger.self, from: data)

        guard persisted.schemaVersion == PersistedLedger.currentSchemaVersion else {
            throw LedgerStoreError.unsupportedSchemaVersion(persisted.schemaVersion)
        }

        return persisted.ledger
    }

    public func save(_ ledger: Ledger) throws {
        let persisted = PersistedLedger(ledger: ledger)
        let data = try encoder.encode(persisted)

        // Ensure directory exists
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: fileURL, options: [.atomic])
    }
}

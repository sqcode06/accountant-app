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

        enc.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            let bits = date.timeIntervalSince1970.bitPattern
            // Store as hex string (JSON-safe, exact, platform-independent)
            try c.encode(String(bits, radix: 16))
        }
        self.encoder = enc

        let dec = JSONDecoder()

        // Decode from either:
        // 1) New format: hex string bitPattern
        // 2) Double seconds (new format)
        // 2) ISO8601 string (old format, for backward compat)
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()

            // New format: hex string bitPattern
            if let s = try? c.decode(String.self),
            let bits = UInt64(s, radix: 16) {
                return Date(timeIntervalSince1970: Double(bitPattern: bits))
            }

            // Older format you used: JSON number
            if let t = try? c.decode(Double.self) {
                return Date(timeIntervalSince1970: t)
            }

            // Even older: ISO8601 string fallback
            let s = try c.decode(String.self)

            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoFrac.date(from: s) { return d }

            let isoNoFrac = ISO8601DateFormatter()
            isoNoFrac.formatOptions = [.withInternetDateTime]
            if let d = isoNoFrac.date(from: s) { return d }

            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date value: \(s)")
        }
        self.decoder = dec
    }

    public func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LedgerStoreError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        let persisted = try decoder.decode(PersistedLedger.self, from: data)

        guard persisted.schemaVersion <= PersistedLedger.currentSchemaVersion else {
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

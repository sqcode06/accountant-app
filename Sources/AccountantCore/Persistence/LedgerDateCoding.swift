import Foundation

/// How dates are written in this app's own files.
///
/// Extracted so the ledger store and the backup format cannot drift apart. They
/// have to agree exactly: a backup written with a different strategy is one this
/// app cannot read back, which is the only thing a backup has to be able to do.
///
/// Dates go out as the hex bit pattern of the interval since 1970 — JSON-safe,
/// platform-independent, and exact. Exactness is not fussiness here: `createdAt`
/// and `updatedAt` order transactions with identical dates, and the merge
/// fingerprint compares them, so a round trip that loses microseconds changes
/// behaviour.
enum LedgerDateCoding {

    static func apply(to encoder: JSONEncoder) {
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let bits = date.timeIntervalSince1970.bitPattern
            try container.encode(String(bits, radix: 16))
        }
    }

    /// Reads the current format and both older ones.
    ///
    /// Files written before the hex format exist on real devices, so dropping
    /// these fallbacks would strand them.
    static func apply(to decoder: JSONDecoder) {
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            // Current: hex bit pattern.
            if let text = try? container.decode(String.self),
               let bits = UInt64(text, radix: 16) {
                return Date(timeIntervalSince1970: Double(bitPattern: bits))
            }

            // Older: a plain JSON number of seconds.
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            // Oldest: ISO 8601, with or without fractional seconds.
            let text = try container.decode(String.self)

            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: text) { return date }

            let withoutFraction = ISO8601DateFormatter()
            withoutFraction.formatOptions = [.withInternetDateTime]
            if let date = withoutFraction.date(from: text) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date value: \(text)"
            )
        }
    }
}

import Foundation

/// Reads and writes one `Codable` value as a JSON file, distinguishing "nothing
/// here yet" from "something here I cannot read".
///
/// Extracted so the budget and classification-rule stores get the same protection
/// as the ledger. All three previously shared the same shape — decode failure
/// surfaces as an error, the caller starts empty, and the next save overwrites the
/// real file — so all three need the same fix rather than a bespoke one each.
public struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    private let fileURL: URL
    private let fallback: @Sendable () -> Value

    /// - Parameter fallback: what `empty` means for this value — `Budget()`, `[]`.
    public init(fileURL: URL, fallback: @escaping @Sendable () -> Value) {
        self.fileURL = fileURL
        self.fallback = fallback
    }

    public func loadOutcome() -> StoreLoadOutcome<Value> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return .loaded(try JSONDecoder().decode(Value.self, from: data))
        } catch {
            return .unreadable(
                FileQuarantine.move(fileURL, reason: String(describing: error))
            )
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(value).write(to: fileURL, options: [.atomic])
    }

    /// The value to use when there is genuinely nothing stored yet.
    public func emptyValue() -> Value { fallback() }
}

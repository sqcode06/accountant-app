import Foundation

public struct Currency: Hashable, Codable, Sendable {
    public let code: String

    public init(_ code: String) {
        self.code = code.uppercased()
    }

    internal var hasValidCode: Bool {
        code.count == 3 && code.allSatisfy { $0 >= "A" && $0 <= "Z" }
    }
}

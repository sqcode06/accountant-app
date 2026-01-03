import Foundation

public struct Currency: Hashable, Codable, Sendable {
    public let code: String

    public init(_ code: String) {
        self.code = code.uppercased()
    }
}

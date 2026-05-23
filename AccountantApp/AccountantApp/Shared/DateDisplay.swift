import Foundation

enum DateDisplay {
    static func transactionDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

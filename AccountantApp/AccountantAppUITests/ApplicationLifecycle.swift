import XCTest

extension XCUIApplication {
    /// iOS may suspend the process before XCTest observes the Home transition.
    /// Both background states are valid; a terminated process still fails.
    func waitUntilBackgrounded(timeout: TimeInterval = 10) -> Bool {
        let backgrounded = XCTNSPredicateExpectation(
            predicate: NSPredicate { [self] _, _ in
                state == .runningBackground || state == .runningBackgroundSuspended
            },
            object: nil
        )
        return XCTWaiter.wait(for: [backgrounded], timeout: timeout) == .completed
    }
}

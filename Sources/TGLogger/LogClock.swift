import Foundation

/// Supplies timestamps for ``LogRecord/timestamp``. Inject a fake clock in tests.
public protocol LogClock: Sendable {
    func now() -> Date
}

/// `Date()` at the moment ``now()`` is called.
public struct SystemLogClock: LogClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

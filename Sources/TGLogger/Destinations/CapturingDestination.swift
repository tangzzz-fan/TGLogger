import os

/// Unbounded in-memory sink intended for unit tests.
///
/// Prefer this over ``MemoryDestination`` when every record must be retained.
public final class CapturingDestination: LogDestination, Sendable {
    public let name: String
    public let minimumLevel: LogLevel

    private let lock: OSAllocatedUnfairLock<[LogRecord]>

    public init(minimumLevel: LogLevel = .trace, name: String = "capturing") {
        self.name = name
        self.minimumLevel = minimumLevel
        self.lock = OSAllocatedUnfairLock(initialState: [])
    }

    public func write(_ record: LogRecord) {
        lock.withLock { records in
            records.append(record)
        }
    }

    public func snapshot() -> [LogRecord] {
        lock.withLock { $0 }
    }

    public func clear() {
        lock.withLock { $0.removeAll(keepingCapacity: true) }
    }
}

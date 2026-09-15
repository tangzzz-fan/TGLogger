import os

/// In-process ring buffer for debug inspection and future UI consoles.
///
/// When the buffer is full, the oldest record is dropped. `write` is thread-safe
/// and does not hop to `MainActor`.
public final class MemoryDestination: LogDestination, Sendable {
    public let name: String
    public let minimumLevel: LogLevel

    private let lock: OSAllocatedUnfairLock<Ring>

    public init(capacity: Int = 1000, minimumLevel: LogLevel = .trace, name: String = "memory") {
        self.name = name
        self.minimumLevel = minimumLevel
        self.lock = OSAllocatedUnfairLock(initialState: Ring(capacity: max(1, capacity)))
    }

    public var capacity: Int {
        lock.withLock { $0.capacity }
    }

    public func write(_ record: LogRecord) {
        lock.withLock { ring in
            ring.append(record)
        }
    }

    public func snapshot() -> [LogRecord] {
        lock.withLock { $0.snapshot() }
    }

    public func clear() {
        lock.withLock { $0.clear() }
    }
}

private struct Ring: Sendable {
    let capacity: Int
    private var slots: [LogRecord?]
    private var head: Int
    private var count: Int

    init(capacity: Int) {
        self.capacity = capacity
        slots = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }

    mutating func append(_ record: LogRecord) {
        if count < capacity {
            slots[(head + count) % capacity] = record
            count += 1
        } else {
            slots[head] = record
            head = (head + 1) % capacity
        }
    }

    func snapshot() -> [LogRecord] {
        guard count > 0 else { return [] }
        var records: [LogRecord] = []
        records.reserveCapacity(count)
        for offset in 0..<count {
            if let record = slots[(head + offset) % capacity] {
                records.append(record)
            }
        }
        return records
    }

    mutating func clear() {
        slots = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }
}

import os

/// In-process ring buffer for debug inspection and future UI consoles.
///
/// When the buffer is full, the oldest record is dropped. `write` is thread-safe
/// and does not hop to `MainActor`.
///
/// Besides pulling with ``snapshot()``, consumers can subscribe with
/// ``makeRecordsStream(bufferingPolicy:)`` for a live tail.
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

    /// Number of currently subscribed record streams. Exposed for tests.
    var activeStreamCount: Int {
        lock.withLock { $0.streams.count }
    }

    public func write(_ record: LogRecord) {
        let streams = lock.withLock { ring -> [StreamBox] in
            ring.append(record)
            return ring.streams
        }
        for stream in streams {
            stream.continuation.yield(record)
        }
    }

    /// Returns a live tail of records written **after** the subscription.
    ///
    /// The stream never replays buffered history — call ``snapshot()`` for that.
    /// Every call creates an independent stream; cancelling the consuming task
    /// (or breaking out of `for await`) tears the subscription down. `clear()`
    /// does not finish the stream.
    ///
    /// The default buffering is unbounded: a consumer that stops reading without
    /// terminating accumulates memory. Pass a tighter `bufferingPolicy` (for
    /// example `.bufferingNewest(1)`) to trade dropped records for a hard cap.
    public func makeRecordsStream(
        bufferingPolicy: AsyncStream<LogRecord>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<LogRecord> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LogRecord.self,
            bufferingPolicy: bufferingPolicy
        )
        let box = StreamBox(continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            self?.removeStream(box)
        }
        lock.withLock { ring in
            ring.streams.append(box)
        }
        return stream
    }

    public func snapshot() -> [LogRecord] {
        lock.withLock { $0.snapshot() }
    }

    public func clear() {
        lock.withLock { $0.clear() }
    }

    private func removeStream(_ box: StreamBox) {
        lock.withLock { ring in
            ring.streams.removeAll { $0 === box }
        }
    }
}

/// Identity wrapper: `AsyncStream.Continuation` is a struct, so removal by
/// identity needs a class box. `Continuation` is `Sendable`, so the box can be too.
private final class StreamBox: Sendable {
    let continuation: AsyncStream<LogRecord>.Continuation

    init(continuation: AsyncStream<LogRecord>.Continuation) {
        self.continuation = continuation
    }
}

private struct Ring: Sendable {
    let capacity: Int
    private var slots: [LogRecord?]
    private var head: Int
    private var count: Int
    var streams: [StreamBox] = []

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

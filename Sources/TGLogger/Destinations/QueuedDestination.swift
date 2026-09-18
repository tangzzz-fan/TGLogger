import Foundation
import os

/// Wraps a slow ``LogDestination`` so `write` never blocks the calling thread.
///
/// `write` encodes nothing and touches no I/O: it appends the record to a bounded
/// in-memory queue and returns. A private serial queue (never `MainActor`) drains
/// the queue into the wrapped destination, preserving per-destination order.
///
/// This is the escape hatch for destinations whose real cost is unavoidable —
/// `fsync` on rotation, opening a file, streaming somewhere. It is **not** needed
/// to make ``FileDestination`` safe on the main thread: since 0.5.0 that
/// destination no longer flushes per line, so its `write` is a microsecond-scale
/// page-cache append.
///
/// ## Overflow
///
/// The queue is bounded by `capacity` records. When it is full, the **oldest**
/// queued record is dropped (matching ``MemoryDestination``'s ring philosophy) and
/// counted in ``droppedLineCount``. The next drained batch starts with a synthetic
/// `notice` line under the `tglogger.queue` category reporting how many lines were
/// lost, so a log file explains its own gaps.
///
/// ## Durability
///
/// ``flush()`` waits for everything enqueued before the call to reach the wrapped
/// destination, then flushes it if it conforms to ``FlushableDestination``.
/// ``close()`` does the same and closes it. Records still sitting in the queue when
/// the process dies are lost — that window is the price of not blocking the caller.
public final class QueuedDestination: FlushableDestination, Sendable {
    public let name: String
    public let minimumLevel: LogLevel
    /// Maximum number of records held in memory before the oldest are dropped.
    public let capacity: Int

    private let inner: any LogDestination
    private let innerFlushable: (any FlushableDestination)?
    private let lock: OSAllocatedUnfairLock<QueueState>
    private let queue: DispatchQueue

    /// Total records dropped due to overflow since the destination was created.
    public var droppedLineCount: UInt64 {
        lock.withLock { $0.dropped }
    }

    /// Records currently waiting to be written.
    public var pendingLineCount: Int {
        lock.withLock { $0.pending.count }
    }

    public init(
        wrapping destination: any LogDestination,
        capacity: Int = 4096,
        name: String? = nil
    ) {
        self.inner = destination
        self.innerFlushable = destination as? any FlushableDestination
        self.minimumLevel = destination.minimumLevel
        self.capacity = max(1, capacity)
        self.name = name ?? "queued(\(destination.name))"
        self.lock = OSAllocatedUnfairLock(initialState: QueueState())
        self.queue = DispatchQueue(label: "tglogger.destination.\(self.name)", qos: .utility)
    }

    public func write(_ record: LogRecord) {
        let shouldStartDraining = lock.withLock { state -> Bool in
            if state.pending.count >= capacity {
                state.pending.removeFirst()
                state.dropped += 1
            }
            state.pending.append(record)
            guard !state.isDraining else { return false }
            state.isDraining = true
            return true
        }
        if shouldStartDraining {
            queue.async { [self] in drain() }
        }
    }

    /// Waits until everything enqueued before this call has reached the wrapped
    /// destination, then flushes it. Blocks the calling thread.
    public func flush() {
        queue.sync { drain() }
        innerFlushable?.flush()
    }

    /// Flushes and closes the wrapped destination. The next ``write(_:)`` still
    /// works — the wrapped destination reopens on demand.
    public func close() {
        flush()
        innerFlushable?.close()
    }

    private func drain() {
        while let batch = nextBatch() {
            for record in batch {
                inner.write(record)
            }
        }
    }

    /// Takes all pending records, prefixed by a drop marker when lines were lost.
    /// Returns `nil` and clears the draining flag when the queue is empty.
    private func nextBatch() -> [LogRecord]? {
        lock.withLock { state in
            guard !state.pending.isEmpty else {
                state.isDraining = false
                return nil
            }
            var batch = state.pending
            state.pending.removeAll(keepingCapacity: true)
            if state.dropped > state.announcedDropped {
                let lost = state.dropped - state.announcedDropped
                batch.insert(Self.dropMarker(count: lost), at: 0)
                state.announcedDropped = state.dropped
            }
            return batch
        }
    }

    private static func dropMarker(count: UInt64) -> LogRecord {
        LogRecord(
            id: 0,
            timestamp: Date(),
            level: .notice,
            message: "queued log lines dropped: \(count)",
            subsystem: "TGLogger",
            category: "tglogger.queue",
            source: LogSource(fileID: #fileID, function: #function, line: #line, column: #column)
        )
    }
}

public extension FileDestination {
    /// Wraps this destination in a ``QueuedDestination`` so no caller thread ever
    /// performs file I/O.
    func queued(capacity: Int = 4096) -> QueuedDestination {
        QueuedDestination(wrapping: self, capacity: capacity)
    }
}

private struct QueueState: Sendable {
    var pending: [LogRecord] = []
    var isDraining = false
    var dropped: UInt64 = 0
    var announcedDropped: UInt64 = 0
}

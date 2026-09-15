import Foundation
import Observation
import TGLogger

/// Filter state for ``LogConsoleView``.
///
/// Empty string fields mean "match everything". The level field is a floor,
/// mirroring ``LogCenter`` semantics.
public struct LogConsoleFilter: Sendable, Equatable {
    /// Records below this level are hidden.
    public var minimumLevel: LogLevel
    /// Case-insensitive substring match on `LogRecord.category`.
    public var category: String
    /// Case-insensitive match on message and metadata values.
    public var text: String
    /// Case-insensitive substring match on the correlation ID.
    public var correlationID: String

    public init(
        minimumLevel: LogLevel = .trace,
        category: String = "",
        text: String = "",
        correlationID: String = ""
    ) {
        self.minimumLevel = minimumLevel
        self.category = category
        self.text = text
        self.correlationID = correlationID
    }
}

/// `@Observable` state backing ``LogConsoleView``.
///
/// The store seeds itself from `MemoryDestination.snapshot()` and then keeps
/// the newest-first list in sync via ``MemoryDestination/makeRecordsStream()``.
/// Trimming follows the destination's ring capacity, so the UI never holds more
/// than the buffer does.
///
/// `LogCenter` never knows this type exists: the store sits above the pipeline
/// and only reads `LogRecord` values.
@MainActor
@Observable
public final class LogConsoleStore {
    /// Newest first.
    public private(set) var records: [LogRecord]

    private let destination: MemoryDestination

    /// Optional so `self` counts as fully initialized before the escaping task
    /// closure captures it (a `let` task property cannot be self-capturing in
    /// its own initializer expression).
    @ObservationIgnored
    private var consumptionTask: Task<Void, Never>?

    /// Ids already present in the seed snapshot. The stream is subscribed
    /// *before* the snapshot is taken, so records written in that window show
    /// up on both sides and must be deduplicated.
    @ObservationIgnored
    private var seedIDs: Set<UInt64>

    public init(destination: MemoryDestination) {
        // Subscribe first, snapshot second: registering the stream is
        // synchronous, so from this line on no record can slip between the
        // two sources.
        let stream = destination.makeRecordsStream()

        self.destination = destination
        let snapshot = destination.snapshot()
        self.seedIDs = Set(snapshot.map(\.id))
        self.records = snapshot.reversed()

        self.consumptionTask = Task { [weak self] in
            for await record in stream {
                guard let self else { return }
                append(record)
            }
        }
    }

    deinit {
        consumptionTask?.cancel()
    }

    /// Empties both the destination ring buffer and the displayed list.
    public func clear() {
        destination.clear()
        records.removeAll()
    }

    /// Applies the filter to the displayed records.
    public func filteredRecords(using filter: LogConsoleFilter) -> [LogRecord] {
        records.filter { record in
            record.level >= filter.minimumLevel
                && (filter.category.isEmpty
                    || record.category.localizedCaseInsensitiveContains(filter.category))
                && (filter.text.isEmpty || matchesText(filter.text, record: record))
                && (filter.correlationID.isEmpty
                    || (record.correlationID ?? "")
                        .localizedCaseInsensitiveContains(filter.correlationID))
        }
    }

    private func append(_ record: LogRecord) {
        // Records written between stream subscription and snapshot seeding are
        // delivered by both sources; keep the snapshot copy.
        guard !seedIDs.contains(record.id) else { return }
        records.insert(record, at: 0)
        let capacity = destination.capacity
        if records.count > capacity {
            records.removeLast(records.count - capacity)
        }
    }

    private func matchesText(_ text: String, record: LogRecord) -> Bool {
        if record.message.localizedCaseInsensitiveContains(text) {
            return true
        }
        for key in record.metadata.keys {
            if key.localizedCaseInsensitiveContains(text)
                || (record.metadata[key]?.rendered ?? "")
                    .localizedCaseInsensitiveContains(text) {
                return true
            }
        }
        return false
    }
}

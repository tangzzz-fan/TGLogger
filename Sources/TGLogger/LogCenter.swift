import Foundation
import os

/// Owns destinations, the global level floor, timestamps, and a monotonic record id.
///
/// `Logger` values created from a center share this pipeline. All emission is synchronous
/// and never hops to `MainActor`.
public final class LogCenter: Sendable {
    public let subsystem: String
    public let minimumLevel: LogLevel

    private let destinations: [any LogDestination]
    private let clock: any LogClock
    private let sequence: OSAllocatedUnfairLock<UInt64>

    public init(
        subsystem: String,
        destinations: [any LogDestination] = [OSLogDestination()],
        minimumLevel: LogLevel = .defaultMinimum,
        clock: any LogClock = SystemLogClock()
    ) {
        self.subsystem = subsystem
        self.destinations = destinations
        self.minimumLevel = minimumLevel
        self.clock = clock
        self.sequence = OSAllocatedUnfairLock(initialState: 0)
    }

    public func logger(category: String) -> Logger {
        Logger(center: self, category: category, boundMetadata: [:])
    }

    public func logger<C: LogCategory>(_ category: C) -> Logger {
        logger(category: category.categoryName)
    }

    func emit(
        level: LogLevel,
        category: String,
        message: () -> String,
        metadata: LogMetadata,
        boundMetadata: LogMetadata,
        messagePrivacy: LogPrivacy,
        fileID: String,
        function: String,
        line: UInt,
        column: UInt
    ) {
        guard level >= minimumLevel else { return }

        let active = destinations.filter { level >= $0.minimumLevel }
        guard !active.isEmpty else { return }

        let record = LogRecord(
            id: nextID(),
            timestamp: clock.now(),
            level: level,
            message: message(),
            messagePrivacy: messagePrivacy,
            subsystem: subsystem,
            category: category,
            source: LogSource(fileID: fileID, function: function, line: line, column: column),
            metadata: boundMetadata.merging(metadata),
            correlationID: LogContext.correlationID
        )

        for destination in active {
            destination.write(record)
        }
    }

    private func nextID() -> UInt64 {
        sequence.withLock { value in
            value += 1
            return value
        }
    }
}

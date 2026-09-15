import Foundation

/// Immutable event produced by ``LogCenter`` and written to every accepting ``LogDestination``.
public struct LogRecord: Sendable, Equatable, Identifiable {
    public let id: UInt64
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let messagePrivacy: LogPrivacy
    public let subsystem: String
    public let category: String
    public let source: LogSource
    public let metadata: LogMetadata
    public let correlationID: String?

    public init(
        id: UInt64,
        timestamp: Date,
        level: LogLevel,
        message: String,
        messagePrivacy: LogPrivacy = .public,
        subsystem: String,
        category: String,
        source: LogSource,
        metadata: LogMetadata = [:],
        correlationID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.messagePrivacy = messagePrivacy
        self.subsystem = subsystem
        self.category = category
        self.source = source
        self.metadata = metadata
        self.correlationID = correlationID
    }
}

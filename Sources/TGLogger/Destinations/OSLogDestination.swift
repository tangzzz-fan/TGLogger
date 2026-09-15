import os

/// Writes records into Unified Logging via `os.Logger`.
///
/// `trace` uses the debug channel. Message and metadata privacy are combined: if any
/// field is `sensitive` the whole line is `.sensitive`; otherwise `private` wins over `public`.
public struct OSLogDestination: LogDestination, Sendable {
    public let name: String
    public let minimumLevel: LogLevel

    public init(minimumLevel: LogLevel = .trace, name: String = "oslog") {
        self.minimumLevel = minimumLevel
        self.name = name
    }

    public func write(_ record: LogRecord) {
        let logger = os.Logger(subsystem: record.subsystem, category: record.category)
        let text = LogRecordFormatter.line(record)
        let privacy = LogRecordFormatter.effectivePrivacy(record)
        emit(logger, level: record.level, privacy: privacy, text: text)
    }

    private func emit(_ logger: os.Logger, level: LogLevel, privacy: LogPrivacy, text: String) {
        switch (level, privacy) {
        case (.trace, .public), (.debug, .public):
            logger.debug("\(text, privacy: .public)")
        case (.trace, .private), (.debug, .private):
            logger.debug("\(text, privacy: .private)")
        case (.trace, .sensitive), (.debug, .sensitive):
            logger.debug("\(text, privacy: .sensitive)")

        case (.info, .public):
            logger.info("\(text, privacy: .public)")
        case (.info, .private):
            logger.info("\(text, privacy: .private)")
        case (.info, .sensitive):
            logger.info("\(text, privacy: .sensitive)")

        case (.notice, .public):
            logger.notice("\(text, privacy: .public)")
        case (.notice, .private):
            logger.notice("\(text, privacy: .private)")
        case (.notice, .sensitive):
            logger.notice("\(text, privacy: .sensitive)")

        case (.warning, .public):
            logger.warning("\(text, privacy: .public)")
        case (.warning, .private):
            logger.warning("\(text, privacy: .private)")
        case (.warning, .sensitive):
            logger.warning("\(text, privacy: .sensitive)")

        case (.error, .public):
            logger.error("\(text, privacy: .public)")
        case (.error, .private):
            logger.error("\(text, privacy: .private)")
        case (.error, .sensitive):
            logger.error("\(text, privacy: .sensitive)")

        case (.fault, .public):
            logger.fault("\(text, privacy: .public)")
        case (.fault, .private):
            logger.fault("\(text, privacy: .private)")
        case (.fault, .sensitive):
            logger.fault("\(text, privacy: .sensitive)")
        }
    }
}

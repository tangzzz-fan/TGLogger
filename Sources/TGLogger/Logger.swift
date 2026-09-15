/// Category-scoped, `Sendable` log emitter. Methods are synchronous.
public struct Logger: Sendable {
    private let center: LogCenter
    public let category: String
    private let boundMetadata: LogMetadata

    init(center: LogCenter, category: String, boundMetadata: LogMetadata) {
        self.center = center
        self.category = category
        self.boundMetadata = boundMetadata
    }

    /// Returns a logger that merges `metadata` into every subsequent record.
    /// Call-site metadata supplied to log methods overrides these keys.
    public func with(metadata: LogMetadata) -> Logger {
        Logger(
            center: center,
            category: category,
            boundMetadata: boundMetadata.merging(metadata)
        )
    }

    public func trace(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .trace,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    public func debug(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .debug,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    public func info(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .info,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    public func notice(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .notice,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    public func warning(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .warning,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    public func error(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .error,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    public func fault(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        emit(
            .fault,
            message: message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }

    private func emit(
        _ level: LogLevel,
        message: () -> String,
        metadata: LogMetadata,
        privacy: LogPrivacy,
        fileID: String,
        function: String,
        line: UInt,
        column: UInt
    ) {
        center.emit(
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            boundMetadata: boundMetadata,
            messagePrivacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }
}

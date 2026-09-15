/// Severity of a log record, ordered from finest to most severe.
///
/// `trace` is retained on ``LogRecord`` but emitted through the `os.Logger` debug channel.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable, Hashable {
    case trace = 0
    case debug = 1
    case info = 2
    case notice = 3
    case warning = 4
    case error = 5
    case fault = 6

    /// Global floor used when ``LogCenter`` is created without an explicit level.
    ///
    /// Debug builds default to ``debug`` (so ``trace`` stays opt-in). Release builds default to ``notice``.
    public static var defaultMinimum: LogLevel {
        #if DEBUG
        .debug
        #else
        .notice
        #endif
    }

    /// Stable uppercase token used by text destinations.
    public var name: String {
        switch self {
        case .trace: "TRACE"
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .warning: "WARNING"
        case .error: "ERROR"
        case .fault: "FAULT"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

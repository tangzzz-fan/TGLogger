/// A thread-safe, synchronous sink for ``LogRecord`` values.
///
/// Destinations must not hop to `MainActor`. `write` may be called concurrently.
public protocol LogDestination: Sendable {
    /// Stable identifier for diagnostics (for example `"oslog"` or `"memory"`).
    var name: String { get }

    /// Records below this level are not delivered to this destination.
    var minimumLevel: LogLevel { get }

    func write(_ record: LogRecord)
}

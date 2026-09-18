/// A thread-safe, synchronous sink for ``LogRecord`` values.
///
/// "Synchronous" means the call performs all of its work before returning — no
/// `async` call site, no completion handler — **not** that the calling thread has
/// to perform expensive I/O. The contract is about cost:
///
/// - `write` must return promptly: encode plus in-process buffering, on the order
///   of microseconds. Logging happens on the main thread, so a destination that
///   `fsync`s or uploads per record turns into UI stalls.
/// - Expensive work may be handed to a private queue, but per-destination order
///   must be preserved (see ``QueuedDestination``), and `write` must **never**
///   hop to `MainActor`.
/// - `write` may be called concurrently from any thread.
/// - Destinations that own a backing store conform to ``FlushableDestination`` so
///   callers can reach an explicit durability point.
public protocol LogDestination: Sendable {
    /// Stable identifier for diagnostics (for example `"oslog"` or `"memory"`).
    var name: String { get }

    /// Records below this level are not delivered to this destination.
    var minimumLevel: LogLevel { get }

    func write(_ record: LogRecord)
}

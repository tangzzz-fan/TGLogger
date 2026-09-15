/// Privacy classification for a log message or metadata value.
///
/// Maps to `OSLogPrivacy` in ``OSLogDestination``. In-process destinations
/// (print / memory / capturing) keep the original value so debug tools can inspect it.
public enum LogPrivacy: Sendable, Equatable, Hashable {
    /// Visible in Console.app without a debugger.
    case `public`
    /// Redacted in Console.app unless the process is attached.
    case `private`
    /// Treated as highly sensitive (`OSLogPrivacy.sensitive`).
    case sensitive
}

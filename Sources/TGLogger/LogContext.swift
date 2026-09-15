/// Task-scoped tracing fields inherited by child tasks.
public enum LogContext: Sendable {
    /// Optional correlation identifier merged into every ``LogRecord`` emitted in this task tree.
    @TaskLocal public static var correlationID: String?
}

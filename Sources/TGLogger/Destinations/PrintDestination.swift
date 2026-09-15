/// Formats each record as a single line and forwards it to a `print`-compatible sink.
public struct PrintDestination: LogDestination, Sendable {
    public let name: String
    public let minimumLevel: LogLevel
    private let printer: @Sendable (String) -> Void

    public init(
        minimumLevel: LogLevel = .debug,
        name: String = "print",
        printer: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.minimumLevel = minimumLevel
        self.name = name
        self.printer = printer
    }

    public func write(_ record: LogRecord) {
        printer(LogRecordFormatter.line(record))
    }
}

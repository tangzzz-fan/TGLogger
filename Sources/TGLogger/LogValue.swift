/// A typed metadata payload with a per-value privacy classification.
///
/// Values default to ``LogPrivacy/private``. Lift privacy with ``public(_:)`` / ``private(_:)`` / ``sensitive(_:)``:
///
/// ```swift
/// ["userId": .private(.string(userID))]
/// ["retry": .public(.int(3))]
/// ```
public struct LogValue: Sendable, Equatable, Hashable {
    public enum Payload: Sendable, Equatable, Hashable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
    }

    public let payload: Payload
    public let privacy: LogPrivacy

    public init(_ payload: Payload, privacy: LogPrivacy = .private) {
        self.payload = payload
        self.privacy = privacy
    }

    public static func string(_ value: String, privacy: LogPrivacy = .private) -> LogValue {
        LogValue(.string(value), privacy: privacy)
    }

    public static func int(_ value: Int, privacy: LogPrivacy = .private) -> LogValue {
        LogValue(.int(value), privacy: privacy)
    }

    public static func double(_ value: Double, privacy: LogPrivacy = .private) -> LogValue {
        LogValue(.double(value), privacy: privacy)
    }

    public static func bool(_ value: Bool, privacy: LogPrivacy = .private) -> LogValue {
        LogValue(.bool(value), privacy: privacy)
    }

    public static func `public`(_ value: LogValue) -> LogValue {
        LogValue(value.payload, privacy: .public)
    }

    public static func `private`(_ value: LogValue) -> LogValue {
        LogValue(value.payload, privacy: .private)
    }

    public static func sensitive(_ value: LogValue) -> LogValue {
        LogValue(value.payload, privacy: .sensitive)
    }

    /// Canonical text form used by formatters (does not apply redaction).
    public var rendered: String {
        switch payload {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        }
    }
}

/// Typed logger category, typically an enum of `String` raw values.
///
/// ```swift
/// enum AppLog: String, LogCategory {
///     case auth, network, store
/// }
/// logs.logger(AppLog.auth)
/// ```
public protocol LogCategory: RawRepresentable, Sendable, Hashable where RawValue == String {
    var categoryName: String { get }
}

public extension LogCategory {
    var categoryName: String { rawValue }
}

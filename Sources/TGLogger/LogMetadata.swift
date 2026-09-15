/// Structured key-value fields attached to a ``LogRecord``.
///
/// Call-site metadata overrides keys already bound on a ``Logger`` via ``Logger/with(metadata:)``.
public struct LogMetadata: Sendable, Equatable, Hashable, ExpressibleByDictionaryLiteral {
    private var storage: [String: LogValue]

    public init(_ values: [String: LogValue] = [:]) {
        storage = values
    }

    public init(dictionaryLiteral elements: (String, LogValue)...) {
        var values: [String: LogValue] = [:]
        values.reserveCapacity(elements.count)
        for (key, value) in elements {
            values[key] = value
        }
        storage = values
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var count: Int { storage.count }

    public func value(for key: String) -> LogValue? {
        storage[key]
    }

    public subscript(key: String) -> LogValue? {
        storage[key]
    }

    /// Keys sorted for stable formatting and tests.
    public var keys: [String] {
        storage.keys.sorted()
    }

    /// `other` wins on key collisions.
    public func merging(_ other: LogMetadata) -> LogMetadata {
        guard !other.isEmpty else { return self }
        guard !isEmpty else { return other }
        var merged = storage
        for (key, value) in other.storage {
            merged[key] = value
        }
        return LogMetadata(merged)
    }
}

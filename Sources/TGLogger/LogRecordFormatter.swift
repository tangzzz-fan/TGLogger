import Foundation

enum LogRecordFormatter {
    static func line(_ record: LogRecord) -> String {
        var parts: [String] = [
            record.timestamp.ISO8601Format(),
            record.level.name,
            "[\(record.category)]",
            record.message
        ]

        if !record.metadata.isEmpty {
            let fields = record.metadata.keys.map { key in
                let value = record.metadata[key]?.rendered ?? ""
                return "\(key)=\(value)"
            }
            parts.append(fields.joined(separator: " "))
        }

        parts.append("src=\(record.source.fileName):\(record.source.function):\(record.source.line)")

        if let correlationID = record.correlationID, !correlationID.isEmpty {
            parts.append("corr=\(correlationID)")
        }

        return parts.joined(separator: " ")
    }

    static func effectivePrivacy(_ record: LogRecord) -> LogPrivacy {
        var privacy = record.messagePrivacy
        for key in record.metadata.keys {
            guard let value = record.metadata[key] else { continue }
            privacy = stronger(privacy, value.privacy)
        }
        return privacy
    }

    private static func stronger(_ lhs: LogPrivacy, _ rhs: LogPrivacy) -> LogPrivacy {
        switch (lhs, rhs) {
        case (.sensitive, _), (_, .sensitive):
            return .sensitive
        case (.private, _), (_, .private):
            return .private
        case (.public, .public):
            return .public
        }
    }
}

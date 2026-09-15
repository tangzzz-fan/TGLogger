import SwiftUI
import TGLogger

#if canImport(UIKit)
import UIKit

private func copyToClipboard(_ text: String) {
    UIPasteboard.general.string = text
}
#elseif canImport(AppKit)
import AppKit

private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
#endif

/// DEBUG log console over a ``MemoryDestination``.
///
/// Embed it from an app's debug menu, or present it with
/// ``View/logConsoleOnShake(destination:isEnabled:)`` (DEBUG iOS):
///
/// ```swift
/// #if DEBUG
/// ContentView()
///     .logConsoleOnShake(destination: memory)
/// #endif
/// ```
///
/// The view only takes the destination (a `LogRecord` source), never a
/// `LogCenter`, so production logging stays unaware of the UI. UIKit apps can
/// wrap this view in a `UIHostingController`.
public struct LogConsoleView: View {
    @State private var store: LogConsoleStore
    @State private var filter = LogConsoleFilter()

    public init(destination: MemoryDestination) {
        _store = State(initialValue: LogConsoleStore(destination: destination))
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            List(store.filteredRecords(using: filter)) { record in
                LogRecordRow(record: record)
            }
            .listStyle(.plain)
        }
        .navigationTitle("Log Console")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Copy") {
                    copyToClipboard(Self.exportText(store.filteredRecords(using: filter)))
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear", role: .destructive) {
                    store.clear()
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $filter.minimumLevel) {
                ForEach(LogLevel.allCases.reversed(), id: \.self) { level in
                    Text(level.name).tag(level)
                }
            }
            .labelsHidden()

            TextField("Category", text: $filter.category)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)

            TextField("Search", text: $filter.text)
                .textFieldStyle(.roundedBorder)

            TextField("Corr ID", text: $filter.correlationID)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
        }
        .font(.caption)
    }

    /// Flat text export of the given records, newest first.
    static func exportText(_ records: [LogRecord]) -> String {
        records.map { record in
            var parts: [String] = [
                record.timestamp.ISO8601Format(),
                record.level.name,
                "[\(record.category)]",
                record.message,
            ]
            if !record.metadata.isEmpty {
                let fields = record.metadata.keys.map { key in
                    "\(key)=\(record.metadata[key]?.rendered ?? "")"
                }
                parts.append(fields.joined(separator: " "))
            }
            parts.append("src=\(record.source.fileName):\(record.source.line)")
            if let correlationID = record.correlationID {
                parts.append("corr=\(correlationID)")
            }
            return parts.joined(separator: " ")
        }
        .joined(separator: "\n")
    }
}

private struct LogRecordRow: View {
    let record: LogRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(record.level.name)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(levelColor.opacity(0.18))
                    .foregroundStyle(levelColor)
                    .clipShape(Capsule())
                Text(record.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("#\(record.id)")
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.tertiary)
            }

            Text(record.message)
                .font(.body)
                .contextMenu {
                    Button("Copy message") {
                        copyToClipboard(record.message)
                    }
                    Button("Copy record") {
                        copyToClipboard(LogConsoleView.exportText([record]))
                    }
                }

            if !record.metadata.isEmpty {
                Text(metadataLine)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("\(record.source.fileName):\(record.source.line)")
                if let correlationID = record.correlationID {
                    Text("corr=\(correlationID)")
                        .monospaced()
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var metadataLine: String {
        record.metadata.keys
            .sorted()
            .map { key in
                "\(key)=\(record.metadata[key]?.rendered ?? "")"
            }
            .joined(separator: " ")
    }

    private var levelColor: Color {
        switch record.level {
        case .trace, .debug: .gray
        case .info, .notice: .blue
        case .warning: .orange
        case .error, .fault: .red
        }
    }
}

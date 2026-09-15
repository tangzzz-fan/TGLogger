import SwiftUI
import TGLogger

struct ContentView: View {
    @Environment(DemoLogStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SPM consumers only link the TGLogger product. This app is an Example target, not a package product.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Bootstrap: OSLog + Print + Memory ring. Categories are AppLog.auth / network / store.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Emit") {
                    Button("Log every level") {
                        store.logLevels()
                    }
                    Button("Simulate login (TaskLocal corr ID)") {
                        Task {
                            await store.simulateLogin()
                        }
                    }
                    Button("Checkout pay tapped (bound metadata)") {
                        store.payTapped()
                    }
                    Button("Concurrent burst (40 debug lines)") {
                        store.burst()
                    }
                    if let correlationID = store.lastCorrelationID {
                        LabeledContent("Last corr") {
                            Text(correlationID)
                                .font(.caption)
                                .monospaced()
                        }
                    }
                }

                Section("Memory buffer") {
                    LabeledContent("Records") {
                        Text("\(store.records.count)")
                            .monospacedDigit()
                    }
                    Button("Refresh snapshot") {
                        store.refresh()
                    }
                    Button("Clear buffer", role: .destructive) {
                        store.clear()
                    }
                }

                Section("Latest records") {
                    if store.records.isEmpty {
                        Text("No records yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.records) { record in
                            LogRecordRow(record: record)
                        }
                    }
                }
            }
            .navigationTitle("TGLogger Demo")
        }
    }
}

private struct LogRecordRow: View {
    let record: LogRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
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

            if !record.metadata.isEmpty {
                Text(metadataLine)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(record.source.fileName):\(record.source.line)")
                if let correlationID = record.correlationID {
                    Text("corr=\(correlationID)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private var metadataLine: String {
        record.metadata.keys.map { key in
            let value = record.metadata[key]?.rendered ?? ""
            return "\(key)=\(value)"
        }
        .joined(separator: " ")
    }

    private var levelColor: Color {
        switch record.level {
        case .trace, .debug: .secondary
        case .info, .notice: .blue
        case .warning: .orange
        case .error, .fault: .red
        }
    }
}

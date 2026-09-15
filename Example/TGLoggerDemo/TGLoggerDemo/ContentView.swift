import SwiftUI
import TGLoggerUI

struct ContentView: View {
    @Environment(DemoLogStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SPM consumers link the TGLogger and TGLoggerUI products. This app is an Example target, not a package product.")
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
                    Button("Clear buffer", role: .destructive) {
                        store.clear()
                    }
                }

                Section("Console") {
                    NavigationLink("Open log console") {
                        LogConsoleView(destination: store.memory)
                    }
                }
            }
            .navigationTitle("TGLogger Demo")
        }
    }
}

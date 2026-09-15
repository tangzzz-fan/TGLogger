import SwiftUI
import TGLoggerUI

struct ContentView: View {
    @Environment(DemoLogStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SPM consumers link TGLogger and optional TGLoggerUI. This app is an Example target, not a package product.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Bootstrap: OSLog + Print + Memory. One `LogRecord` is fanned out to every destination.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Same records as Xcode, on the phone")
                            .font(.headline)
                        Text("Xcode’s debug console is mostly PrintDestination (`print`). The in-app console is MemoryDestination — the same LogRecord, another window. No Wi-Fi relay.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("1. Emit below, then compare Xcode with Open log console.\n2. Product → Stop (or unplug). Print is gone; the in-app list still tails live.\n3. Accessory session is the hardware-shaped example of that flow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Untethered logging")
                }

                Section("Emit") {
                    Button("Simulate accessory session") {
                        store.simulateAccessorySession()
                    }
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

                Section {
                    NavigationLink("Open log console") {
                        LogConsoleView(destination: store.memory)
                    }
                } header: {
                    Text("Console")
                } footer: {
                    Text("Stop the debugger, tap Simulate accessory session, then come back here — new lines should still appear.")
                }
            }
            .navigationTitle("TGLogger Demo")
        }
    }
}

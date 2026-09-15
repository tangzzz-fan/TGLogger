import Foundation
import Observation
import TGLogger

enum AppLog: String, LogCategory {
    case auth
    case network
    case store
}

/// Composition root for the demo. Keeps `MemoryDestination` so the UI can snapshot records.
/// This type lives in the example app, not in the TGLogger package.
@Observable
@MainActor
final class DemoLogStore {
    let center: LogCenter
    let memory: MemoryDestination
    private(set) var records: [LogRecord] = []
    private(set) var lastCorrelationID: String?

    var auth: Logger { center.logger(AppLog.auth) }

    var network: Logger { center.logger(AppLog.network) }

    var checkout: Logger {
        center.logger(AppLog.store).with(metadata: [
            "screen": .public(.string("Checkout"))
        ])
    }

    init() {
        let memory = MemoryDestination(capacity: 200)
        self.memory = memory
        self.center = LogCenter(
            subsystem: Bundle.main.bundleIdentifier ?? "com.tango.TGLoggerDemo",
            destinations: [
                OSLogDestination(),
                PrintDestination(minimumLevel: .debug),
                memory
            ],
            minimumLevel: .trace
        )
        center.logger(AppLog.auth).notice("demo launched")
        refresh()
    }

    func refresh() {
        records = memory.snapshot().reversed()
    }

    func clear() {
        memory.clear()
        refresh()
    }

    func logLevels() {
        auth.trace("token refresh skipped")
        auth.debug("using cached session")
        auth.info("session started")
        auth.notice("rate limit approaching")
        auth.warning("retrying after timeout")
        auth.error("payment declined")
        auth.fault("unrecoverable store corruption")
        refresh()
    }

    func simulateLogin() async {
        let requestID = "req-\(UUID().uuidString.prefix(8))"
        lastCorrelationID = requestID

        await LogContext.$correlationID.withValue(requestID) {
            auth.info("login started", metadata: [
                "userId": .private(.string("user-42"))
            ])
            await Task {
                network.debug("POST /session")
            }.value
            auth.info("login succeeded", metadata: [
                "userId": .private(.string("user-42")),
                "retry": .public(.int(0))
            ])
        }
        refresh()
    }

    func payTapped() {
        checkout.notice("pay tapped", metadata: [
            "amount": .public(.double(19.9))
        ])
        refresh()
    }

    func burst() {
        let network = center.logger(AppLog.network)
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            network.debug("heartbeat \(index)")
        }
        refresh()
    }
}

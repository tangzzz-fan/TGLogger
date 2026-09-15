import Foundation
import Observation
import TGLogger

enum AppLog: String, LogCategory {
    case auth
    case network
    case store
    case accessory
}

/// Composition root for the demo. Holds the destinations and the emit actions;
/// the log list UI comes from the TGLoggerUI product (`LogConsoleView`).
/// This type lives in the example app, not in the TGLogger package.
@Observable
@MainActor
final class DemoLogStore {
    let center: LogCenter
    let memory: MemoryDestination
    private(set) var lastCorrelationID: String?

    var auth: Logger { center.logger(AppLog.auth) }

    var network: Logger { center.logger(AppLog.network) }

    var checkout: Logger {
        center.logger(AppLog.store).with(metadata: [
            "screen": .public(.string("Checkout"))
        ])
    }

    var accessory: Logger { center.logger(AppLog.accessory) }

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
    }

    func clear() {
        memory.clear()
    }

    func logLevels() {
        auth.trace("token refresh skipped")
        auth.debug("using cached session")
        auth.info("session started")
        auth.notice("rate limit approaching")
        auth.warning("retrying after timeout")
        auth.error("payment declined")
        auth.fault("unrecoverable store corruption")
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
    }

    func payTapped() {
        checkout.notice("pay tapped", metadata: [
            "amount": .public(.double(19.9))
        ])
    }

    func burst() {
        let network = center.logger(AppLog.network)
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            network.debug("heartbeat \(index)")
        }
    }

    /// Typical hardware-session lines: they still reach Memory (and thus
    /// `LogConsoleView`) after the debugger is detached.
    func simulateAccessorySession() {
        let sessionID = "acc-\(UUID().uuidString.prefix(6))"
        LogContext.$correlationID.withValue(sessionID) {
            accessory.notice("accessory session started", metadata: [
                "protocol": .public(.string("com.example.hw"))
            ])
            accessory.debug("TX handshake")
            accessory.debug("RX ack")
            accessory.info("firmware reported", metadata: [
                "version": .public(.string("1.4.2"))
            ])
            accessory.warning("retry packet 3")
            accessory.info("sample committed", metadata: [
                "count": .public(.int(12))
            ])
        }
        lastCorrelationID = sessionID
    }
}

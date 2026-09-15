import Foundation
import os
import Testing
@testable import TGLogger

private struct FixedClock: LogClock {
    let date: Date
    func now() -> Date { date }
}

private enum AppLog: String, LogCategory {
    case auth
    case network
}

private func makeCenter(
    _ destinations: [any LogDestination],
    minimumLevel: LogLevel = .trace,
    clock: any LogClock = SystemLogClock()
) -> LogCenter {
    LogCenter(
        subsystem: "tests.tglogger",
        destinations: destinations,
        minimumLevel: minimumLevel,
        clock: clock
    )
}

@Suite("LogLevel")
struct LogLevelTests {
    @Test("Levels are ordered from trace to fault")
    func ordering() {
        #expect(LogLevel.trace < .debug)
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .notice)
        #expect(LogLevel.notice < .warning)
        #expect(LogLevel.warning < .error)
        #expect(LogLevel.error < .fault)
    }

    @Test("Default minimum is debug in DEBUG builds")
    func defaultMinimum() {
        #if DEBUG
        #expect(LogLevel.defaultMinimum == .debug)
        #else
        #expect(LogLevel.defaultMinimum == .notice)
        #endif
    }
}

@Suite("Filtering")
struct FilteringTests {
    @Test("Center minimum level skips destinations and does not evaluate the message")
    func centerFloorSkipsAutoclosure() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing], minimumLevel: .error).logger(category: "auth")
        var evaluated = false

        logger.debug({
            evaluated = true
            return "should not run"
        }())

        #expect(!evaluated)
        #expect(capturing.snapshot().isEmpty)
    }

    @Test("Destination minimum level skips write without evaluating the message")
    func destinationFloorSkipsAutoclosure() {
        let capturing = CapturingDestination(minimumLevel: .error)
        let logger = makeCenter([capturing], minimumLevel: .trace).logger(category: "auth")
        var evaluated = false

        logger.debug({
            evaluated = true
            return "should not run"
        }())

        #expect(!evaluated)
        #expect(capturing.snapshot().isEmpty)
    }

    @Test("A record is delivered only to destinations that accept its level")
    func perDestinationFilter() {
        let debugSink = CapturingDestination(minimumLevel: .debug, name: "debug")
        let errorSink = CapturingDestination(minimumLevel: .error, name: "error")
        let logger = makeCenter([debugSink, errorSink]).logger(category: "auth")

        logger.info("hello")
        logger.error("boom")

        #expect(debugSink.snapshot().map(\.message) == ["hello", "boom"])
        #expect(errorSink.snapshot().map(\.message) == ["boom"])
    }
}

@Suite("Source and context")
struct SourceAndContextTests {
    @Test("LogSource captures fileID, function, and line of the call site")
    func sourceIncludesCallSite() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(category: "auth")

        let expectedLine = UInt(#line + 1)
        logger.info("probe")

        let record = capturing.snapshot()[0]
        #expect(record.source.line == expectedLine)
        #expect(record.source.function.contains("sourceIncludesCallSite"))
        #expect(record.source.fileID.contains("TGLoggerTests.swift"))
        #expect(record.source.fileName == "TGLoggerTests.swift")
        #expect(record.source.column > 0)
    }

    @Test("Correlation ID is copied from the task-local context")
    func correlationIDOnRecord() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(category: "auth")

        LogContext.$correlationID.withValue("req-1") {
            logger.info("tagged")
        }

        #expect(capturing.snapshot()[0].correlationID == "req-1")
    }

    @Test("Correlation ID is inherited by child tasks")
    func correlationIDInheritsToChildTask() async {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(category: "auth")

        await LogContext.$correlationID.withValue("req-2") {
            await Task {
                logger.info("child")
            }.value
        }

        #expect(capturing.snapshot()[0].correlationID == "req-2")
    }

    @Test("Injected clock is stored on the record")
    func injectedClock() {
        let capturing = CapturingDestination()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let logger = makeCenter([capturing], clock: FixedClock(date: date)).logger(category: "auth")

        logger.info("timed")

        #expect(capturing.snapshot()[0].timestamp == date)
    }
}

@Suite("Logger metadata")
struct LoggerMetadataTests {
    @Test("with(metadata:) binds fields and call-site keys override")
    func mergeAndOverride() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(AppLog.auth)
            .with(metadata: [
                "a": .string("1"),
                "b": .string("2")
            ])

        logger.info("merged", metadata: [
            "b": .string("3"),
            "c": .string("4")
        ])

        let metadata = capturing.snapshot()[0].metadata
        #expect(logger.category == "auth")
        #expect(metadata["a"]?.rendered == "1")
        #expect(metadata["b"]?.rendered == "3")
        #expect(metadata["c"]?.rendered == "4")
    }

    @Test("Privacy helpers wrap payload values")
    func privacyHelpers() {
        let secret = LogValue.private(.string("token"))
        let visible = LogValue.public(.int(3))
        let hidden = LogValue.sensitive(.bool(true))

        #expect(secret.privacy == .private)
        #expect(secret.rendered == "token")
        #expect(visible.privacy == .public)
        #expect(visible.payload == .int(3))
        #expect(hidden.privacy == .sensitive)
    }

    @Test("Record ids are monotonic")
    func monotonicIDs() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(category: "auth")
        logger.info("one")
        logger.info("two")

        let records = capturing.snapshot()
        #expect(records.map(\.id) == [1, 2])
    }
}

@Suite("MemoryDestination")
struct MemoryDestinationTests {
    @Test("Ring buffer drops the oldest records")
    func ringDropsOldest() {
        let memory = MemoryDestination(capacity: 3)
        let logger = makeCenter([memory]).logger(category: "ring")

        for index in 1...5 {
            logger.info("\(index)")
        }

        #expect(memory.capacity == 3)
        #expect(memory.snapshot().map(\.message) == ["3", "4", "5"])
    }

    @Test("clear empties the buffer")
    func clear() {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "ring")
        logger.info("keep")
        memory.clear()
        #expect(memory.snapshot().isEmpty)
    }

    @Test("Concurrent writes stay within capacity and do not crash")
    func concurrentWrites() {
        let memory = MemoryDestination(capacity: 50)
        let logger = makeCenter([memory]).logger(category: "ring")

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            logger.info("n=\(index)")
        }

        let snapshot = memory.snapshot()
        #expect(snapshot.count == 50)
        #expect(Set(snapshot.map(\.id)).count == 50)
    }
}

@Suite("Capturing and print destinations")
struct SinkTests {
    @Test("CapturingDestination retains every record")
    func capturingRetainsAll() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(category: "cap")
        logger.trace("t")
        logger.debug("d")
        logger.info("i")
        #expect(capturing.snapshot().map(\.message) == ["t", "d", "i"])
        capturing.clear()
        #expect(capturing.snapshot().isEmpty)
    }

    @Test("PrintDestination writes a formatted line")
    func printFormat() {
        let lines = OSAllocatedUnfairLock(initialState: [String]())
        let printer = PrintDestination(minimumLevel: .debug) { line in
            lines.withLock { $0.append(line) }
        }
        let logger = makeCenter([printer], clock: FixedClock(date: Date(timeIntervalSince1970: 0)))
            .logger(category: "auth")

        logger.info("hello", metadata: ["retry": .public(.int(2))])

        let line = lines.withLock { $0[0] }
        #expect(line.contains("INFO"))
        #expect(line.contains("[auth]"))
        #expect(line.contains("hello"))
        #expect(line.contains("retry=2"))
        #expect(line.contains("src=TGLoggerTests.swift"))
    }

    @Test("OSLogDestination accepts every level without throwing")
    func osLogSmoke() {
        let capturing = CapturingDestination()
        let logger = makeCenter([OSLogDestination(), capturing]).logger(category: "os")

        logger.trace("t")
        logger.debug("d")
        logger.info("i")
        logger.notice("n")
        logger.warning("w")
        logger.error("e")
        logger.fault("f", metadata: ["token": .sensitive(.string("s"))], privacy: .private)

        #expect(capturing.snapshot().count == 7)
        #expect(capturing.snapshot()[6].messagePrivacy == .private)
        #expect(LogRecordFormatter.effectivePrivacy(capturing.snapshot()[6]) == .sensitive)
    }

    @Test("Concurrent capturing writes keep unique ids")
    func concurrentCapturing() {
        let capturing = CapturingDestination()
        let logger = makeCenter([capturing]).logger(category: "cap")

        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            logger.info("n=\(index)")
        }

        let records = capturing.snapshot()
        #expect(records.count == 1000)
        #expect(Set(records.map(\.id)).count == 1000)
    }
}

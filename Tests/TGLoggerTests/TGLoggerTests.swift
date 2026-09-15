import Foundation
import os
import Testing
@testable import TGLogger
import TGLoggerUI

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

@Suite("MemoryDestination streaming")
struct MemoryStreamTests {
    /// Polls `condition` for up to ~2s so subscription / teardown races are deterministic.
    private func waitFor(
        _ condition: @autoclosure () async -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @Test("Stream yields records written after subscription")
    func yieldsNewRecords() async {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "stream")

        let task = Task {
            var messages: [String] = []
            for await record in memory.makeRecordsStream() {
                messages.append(record.message)
                if messages.count == 2 { break }
            }
            return messages
        }

        let subscribed = await waitFor(memory.activeStreamCount == 1)
        #expect(subscribed)

        logger.info("first")
        logger.info("second")

        let messages = await task.value
        #expect(messages == ["first", "second"])

        let cleanedUp = await waitFor(memory.activeStreamCount == 0)
        #expect(cleanedUp)
    }

    @Test("Records written before subscription are not replayed")
    func noReplayOfHistory() async {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "stream")
        logger.info("history")

        let task = Task {
            var messages: [String] = []
            for await record in memory.makeRecordsStream() {
                messages.append(record.message)
                if messages.count == 1 { break }
            }
            return messages
        }
        _ = await waitFor(memory.activeStreamCount == 1)

        logger.info("live")

        let messages = await task.value
        #expect(messages == ["live"])
    }

    @Test("Two streams each receive every record")
    func twoConsumers() async {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "stream")

        func collectOne() -> Task<String, Never> {
            Task {
                var message = ""
                for await record in memory.makeRecordsStream() {
                    message = record.message
                    break
                }
                return message
            }
        }
        let first = collectOne()
        let second = collectOne()

        let subscribed = await waitFor(memory.activeStreamCount == 2)
        #expect(subscribed)

        logger.info("fanout")

        #expect(await first.value == "fanout")
        #expect(await second.value == "fanout")
        #expect(await waitFor(memory.activeStreamCount == 0))
    }

    @Test("clear() does not finish the stream")
    func clearKeepsStreamAlive() async {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "stream")

        let task = Task {
            var messages: [String] = []
            for await record in memory.makeRecordsStream() {
                messages.append(record.message)
                if messages.count == 2 { break }
            }
            return messages
        }
        _ = await waitFor(memory.activeStreamCount == 1)

        logger.info("before clear")
        memory.clear()
        logger.info("after clear")

        let messages = await task.value
        #expect(messages == ["before clear", "after clear"])
    }
}

@Suite("LogConsoleStore")
struct LogConsoleStoreTests {
    /// Polls until `condition` holds (up to ~2s) so stream delivery is deterministic.
    @MainActor
    private func waitFor(_ condition: @autoclosure () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    @MainActor
    @Test("Store seeds from snapshot and then follows the live stream")
    func seedsAndFollows() async {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "console")
        logger.info("history")

        let store = LogConsoleStore(destination: memory)
        #expect(store.records.map(\.message) == ["history"])

        logger.info("live")
        let followed = await waitFor(store.records.count == 2)
        #expect(followed)
        #expect(store.records.map(\.message) == ["live", "history"])
    }

    @MainActor
    @Test("Store trims to the destination capacity, newest first")
    func trimsToCapacity() async {
        let memory = MemoryDestination(capacity: 3)
        let logger = makeCenter([memory]).logger(category: "console")

        let store = LogConsoleStore(destination: memory)
        for index in 1...5 {
            logger.info("n\(index)")
        }

        let trimmed = await waitFor(store.records.count == 3)
        #expect(trimmed)
        #expect(store.records.map(\.message) == ["n5", "n4", "n3"])
    }

    @MainActor
    @Test("Filter applies level floor, category, text, and correlation ID")
    func filtering() async {
        let memory = MemoryDestination(capacity: 32)
        let center = makeCenter([memory])
        let auth = center.logger(category: "auth")
        let net = center.logger(category: "network")

        let store = LogConsoleStore(destination: memory)

        LogContext.$correlationID.withValue("req-1") {
            auth.info("login ok")
            net.warning("slow retry")
        }
        auth.error("payment declined", metadata: ["code": .public(.int(500))])
        _ = await waitFor(store.records.count == 3)

        var filter = LogConsoleFilter()
        #expect(store.filteredRecords(using: filter).count == 3)

        filter.minimumLevel = .warning
        #expect(store.filteredRecords(using: filter).count == 2)

        filter.category = "auth"
        #expect(store.filteredRecords(using: filter).map(\.message) == ["payment declined"])

        filter = LogConsoleFilter(text: "slow")
        #expect(store.filteredRecords(using: filter).map(\.message) == ["slow retry"])

        filter = LogConsoleFilter(correlationID: "req-1")
        #expect(store.filteredRecords(using: filter).count == 2)

        filter = LogConsoleFilter(text: "500")
        #expect(store.filteredRecords(using: filter).map(\.message) == ["payment declined"])
    }

    @MainActor
    @Test("clear empties both the store and the destination")
    func clearBoth() async {
        let memory = MemoryDestination(capacity: 8)
        let logger = makeCenter([memory]).logger(category: "console")

        let store = LogConsoleStore(destination: memory)
        logger.info("one")
        _ = await waitFor(store.records.count == 1)

        store.clear()
        #expect(store.records.isEmpty)
        #expect(memory.snapshot().isEmpty)
    }
}

@Suite("FileDestination")
struct FileDestinationTests {
    private func makeLogDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TGLogger-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func combinedText(_ destination: FileDestination) throws -> String {
        try destination.existingFileURLs()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined()
    }

    @Test("Writes formatted lines to the active file")
    func writesLines() throws {
        let dir = try makeLogDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = FileDestination(
            directory: dir,
            maxFileSize: 50_000,
            maxFileCount: 2,
            minimumLevel: .trace
        )
        let logger = makeCenter(
            [destination],
            clock: FixedClock(date: Date(timeIntervalSince1970: 0))
        ).logger(category: "file")

        logger.info("alpha", metadata: ["n": .public(.int(1))])
        destination.close()

        let text = try String(contentsOf: destination.currentFileURL, encoding: .utf8)
        #expect(text.contains("alpha"))
        #expect(text.contains("INFO"))
        #expect(text.contains("[file]"))
        #expect(text.contains("n=1"))
        #expect(destination.existingFileURLs() == [destination.currentFileURL])
    }

    @Test("Rotates when the active file would exceed maxFileSize")
    func rotates() throws {
        let dir = try makeLogDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = FileDestination(
            directory: dir,
            fileName: "rot",
            maxFileSize: 180,
            maxFileCount: 3,
            minimumLevel: .trace
        )
        let logger = makeCenter([destination]).logger(category: "file")
        for index in 0..<40 {
            logger.info("line-\(index)")
        }
        destination.close()

        #expect(destination.existingFileURLs().count >= 2)
        let text = try combinedText(destination)
        #expect(text.contains("line-39"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("rot.1.log").path))
    }

    @Test("Keeps at most maxFileCount files")
    func respectsFileCount() throws {
        let dir = try makeLogDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = FileDestination(
            directory: dir,
            fileName: "cap",
            maxFileSize: 80,
            maxFileCount: 2,
            minimumLevel: .trace
        )
        let logger = makeCenter([destination]).logger(category: "file")
        for index in 0..<80 {
            logger.info("x\(index)")
        }
        destination.close()

        #expect(destination.existingFileURLs().count <= 2)
    }

    @Test("maxFileCount of 1 truncates instead of unbounded growth")
    func singleFileTruncates() throws {
        let dir = try makeLogDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = FileDestination(
            directory: dir,
            fileName: "one",
            maxFileSize: 80,
            maxFileCount: 1,
            minimumLevel: .trace
        )
        let logger = makeCenter([destination]).logger(category: "file")
        for index in 0..<40 {
            logger.info("only-\(index)")
        }
        destination.close()

        #expect(destination.existingFileURLs() == [destination.currentFileURL])
        let text = try String(contentsOf: destination.currentFileURL, encoding: .utf8)
        #expect(text.contains("only-39"))
    }

    @Test("Concurrent writes stay on disk without crashing")
    func concurrentWrites() throws {
        let dir = try makeLogDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = FileDestination(
            directory: dir,
            maxFileSize: 200_000,
            maxFileCount: 3,
            minimumLevel: .trace
        )
        let logger = makeCenter([destination]).logger(category: "file")

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            logger.info("n=\(index)")
        }
        destination.close()

        let text = try combinedText(destination)
        #expect(text.components(separatedBy: "\n").filter { $0.contains("n=") }.count == 200)
    }
}

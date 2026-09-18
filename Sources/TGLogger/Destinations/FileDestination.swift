import Foundation
import os

/// Appends UTF-8 log lines to disk with size-based rotation.
///
/// Survives process death; does **not** replace ``MemoryDestination`` / ``LogConsoleView``
/// for live on-device viewing. `write` is synchronous, serialized, and never hops
/// to `MainActor`. I/O failures are swallowed so logging cannot crash the app.
///
/// **Caller-thread cost.** One `write` is an encode plus an append into the kernel
/// page cache (microseconds), so `write` is safe on the main thread. Storage round
/// trips are not: they happen on rotation, on ``close()``, on ``flush()``, and —
/// only with ``FileFlushPolicy/everyWrite`` — per line. ``FileFlushPolicy/never``
/// (the default) keeps `fsync` off the main thread; wrap the destination in
/// ``QueuedDestination`` when even rotation or the first open must leave the caller.
///
/// Nothing touches the file system until the first ``write(_:)``: ``init`` only
/// stores configuration.
///
/// Layout (``maxFileCount`` = 3): `name.log` (active), `name.1.log` (previous),
/// `name.2.log` (oldest kept). When the active file exceeds ``maxFileSize``,
/// it is rotated and a new empty `name.log` is opened.
public final class FileDestination: FlushableDestination, Sendable {
    public let name: String
    public let minimumLevel: LogLevel
    public let directory: URL
    public let fileName: String
    public let maxFileSize: Int
    public let maxFileCount: Int
    public let flushPolicy: FileFlushPolicy

    private let lock: OSAllocatedUnfairLock<FileIO>

    /// Background queue for ``FileFlushPolicy/interval(_:)`` flushes; never `MainActor`.
    private static let flushQueue = DispatchQueue(label: "tglogger.file.flush", qos: .utility)

    /// Caches directory + `folderName`, creating nothing until the destination is used.
    public static func cachesDirectory(folderName: String = "TGLogger") -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    public init(
        directory: URL,
        fileName: String = "tglogger",
        maxFileSize: Int = 512_000,
        maxFileCount: Int = 3,
        flushPolicy: FileFlushPolicy = .never,
        minimumLevel: LogLevel = .debug,
        name: String = "file"
    ) {
        self.name = name
        self.minimumLevel = minimumLevel
        self.directory = directory
        self.fileName = Self.sanitizedFileName(fileName)
        self.maxFileSize = max(1, maxFileSize)
        self.maxFileCount = max(1, maxFileCount)
        self.flushPolicy = flushPolicy
        self.lock = OSAllocatedUnfairLock(initialState: FileIO())
    }

    deinit {
        lock.withLock { io in
            io.timer?.cancel()
            io.timer = nil
        }
    }

    /// The file currently being appended.
    public var currentFileURL: URL {
        directory.appendingPathComponent("\(fileName).log")
    }

    /// Existing rotated files, active first, then `.1`, `.2`, …
    public func existingFileURLs() -> [URL] {
        ([currentFileURL] + (1..<maxFileCount).map(rotatedURL))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func write(_ record: LogRecord) {
        let data = Data((LogRecordFormatter.line(record) + "\n").utf8)
        lock.withLock { io in
            if io.handle == nil {
                openCurrentLocked(&io)
            }
            if io.byteCount > 0, io.byteCount + UInt64(data.count) > UInt64(maxFileSize) {
                rotateLocked(&io)
            }
            guard let handle = io.handle else { return }
            do {
                try handle.write(contentsOf: data)
                if flushPolicy == .everyWrite {
                    try handle.synchronize()
                }
                io.byteCount += UInt64(data.count)
            } catch {
                io.handle = nil
            }
        }
    }

    /// Pushes written lines to storage. Blocks the calling thread; a no-op when
    /// nothing is open.
    public func flush() {
        lock.withLock { io in
            try? io.handle?.synchronize()
        }
    }

    /// Flushes, stops the interval timer, and releases the handle. The next
    /// ``write(_:)`` reopens the file.
    public func close() {
        lock.withLock { io in
            try? io.handle?.synchronize()
            try? io.handle?.close()
            io.handle = nil
            io.timer?.cancel()
            io.timer = nil
        }
    }

    private func rotatedURL(_ index: Int) -> URL {
        directory.appendingPathComponent("\(fileName).\(index).log")
    }

    private func openCurrentLocked(_ io: inout FileIO) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = currentFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            io.byteCount = try handle.seekToEnd()
            io.handle = handle
            startTimerLocked(&io)
        } catch {
            io.handle = nil
            io.byteCount = 0
        }
    }

    private func startTimerLocked(_ io: inout FileIO) {
        guard let interval = flushPolicy.timerInterval, io.timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: Self.flushQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        io.timer = timer
        timer.activate()
    }

    private func rotateLocked(_ io: inout FileIO) {
        try? io.handle?.synchronize()
        try? io.handle?.close()
        io.handle = nil
        io.byteCount = 0

        let active = currentFileURL
        if maxFileCount == 1 {
            try? FileManager.default.removeItem(at: active)
            openCurrentLocked(&io)
            return
        }

        let oldest = rotatedURL(maxFileCount - 1)
        try? FileManager.default.removeItem(at: oldest)
        for index in stride(from: maxFileCount - 2, through: 1, by: -1) {
            let source = rotatedURL(index)
            let destination = rotatedURL(index + 1)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: source, to: destination)
        }
        if FileManager.default.fileExists(atPath: active.path) {
            let firstRotated = rotatedURL(1)
            try? FileManager.default.removeItem(at: firstRotated)
            try? FileManager.default.moveItem(at: active, to: firstRotated)
        }
        openCurrentLocked(&io)
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "tglogger" : trimmed
    }
}

private struct FileIO: @unchecked Sendable {
    var handle: FileHandle?
    var byteCount: UInt64 = 0
    var timer: DispatchSourceTimer?
}

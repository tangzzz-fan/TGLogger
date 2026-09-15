# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`docs/FACTORY.md`**: 应用已用 Factory 时如何注册 `LogCenter` / destination（singleton、同一实例、测试替换）。不把 Factory 加进本包。
- **`docs/ANTI_CORRUPTION.md`**: 面向协议的 App 如何在功能模块与 TGLogger 之间自建端口 + 适配器。不把业务协议加进本包。

### Fixed
- Example `ContentView` 启动说明补上 `FileDestination`（与实际 bootstrap 一致）。

## [0.3.0] - 2026-09-16

### Added
- **`FileDestination`**: UTF-8 line log on disk with size-based rotation (`maxFileSize` / `maxFileCount`). Synchronous, lock-serialized, no `MainActor` hop. `existingFileURLs()` / `currentFileURL` for share-sheet export. Example adds **Share log files**.
- **`docs/APP_INTEGRATION.md`**: DEBUG + 连硬件时的接线清单（控制台及时看、文件事后拷）。

## [0.2.0] - 2026-09-16

### Fixed
- `docs/` is no longer excluded by `.gitignore`: the bare `docs/` rule also matched `Docs/` on macOS case-insensitive filesystems, so hand-written docs silently never got committed. The directory is now lowercase `docs/` and README/DesignInfo links were updated.
- CI: `workflow_dispatch` was nested under `pull_request` and could not be triggered manually.

### Added
- **Example app now uses `TGLoggerUI`**: the demo links both products, replaces its hand-rolled record list with `LogConsoleView` (reachable via "Open log console"), and drops the manual "Refresh snapshot" flow.
- **`TGLoggerUI` product** (optional, depends only on `TGLogger`): `LogConsoleView` (filter bar + newest-first list + copy/clear toolbar), `LogConsoleStore` (`@MainActor @Observable`, seeds from `snapshot()` then follows the live stream with seed-dedup, trims to the ring capacity), and `LogConsoleFilter` (level floor / category / text / correlation ID). DEBUG-console scope per `docs/SWIFTUI_CONSOLE.md` §5.
- **`MemoryDestination.makeRecordsStream(bufferingPolicy:)`**: live tail as `AsyncStream<LogRecord>`. Yields records written after subscription (no replay of buffered history); multiple independent streams per destination; teardown on task cancellation; `clear()` keeps the stream alive.
- CI guard that fails when a file under `docs/` exists on disk but is not tracked by git (defends against the ignore rule above).
- `docs/devnotes/`: development notes index, template, and the first note documenting the `.gitignore` trap.
- **Untethered logging**: `docs/UNTETHERED_LOGGING.md` plus Example copy. Same `LogRecord` as Xcode’s `print` window, live on-device via `LogConsoleView`, no Wi-Fi relay. Demo adds **Simulate accessory session**.

## [0.1.0] - 2026-09-15

### Added
- **`LogCenter` / `Logger`**: Synchronous, `Sendable` logging pipeline with subsystem + category (string or `LogCategory`).
- **`LogRecord`**: Immutable event with monotonic id, timestamp, level, message privacy, source, metadata, and optional correlation id.
- **Levels**: `trace` / `debug` / `info` / `notice` / `warning` / `error` / `fault`, mapped onto `os.Logger`.
- **Call-site tracing**: `#fileID` / `#function` / `#line` / `#column` on every record.
- **`LogContext.$correlationID`**: `@TaskLocal` correlation id inherited by child tasks.
- **`LogMetadata` / `LogValue`**: Typed fields (`string` / `int` / `double` / `bool`) with per-key `LogPrivacy`.
- **`Logger.with(metadata:)`**: Bound metadata; call-site keys override.
- **Destinations**: `OSLogDestination`, `PrintDestination`, `MemoryDestination` (ring buffer), `CapturingDestination` (tests).
- **`LogClock`**: Inject timestamps in tests.
- **Filtering**: Center + per-destination `minimumLevel`; `@autoclosure` messages are not evaluated when dropped.
- **Tests / CI**: Swift Testing suite and GitHub Actions `swift build` + `swift test`.
- **Example**: `Example/TGLoggerDemo` iOS app (local package path `../..`). Not declared in `Package.swift`.

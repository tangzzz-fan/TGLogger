# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `docs/` is no longer excluded by `.gitignore`: the bare `docs/` rule also matched `Docs/` on macOS case-insensitive filesystems, so hand-written docs silently never got committed. The directory is now lowercase `docs/` and README/DesignInfo links were updated.
- CI: `workflow_dispatch` was nested under `pull_request` and could not be triggered manually.

### Added
- **`MemoryDestination.makeRecordsStream(bufferingPolicy:)`**: live tail as `AsyncStream<LogRecord>`. Yields records written after subscription (no replay of buffered history); multiple independent streams per destination; teardown on task cancellation; `clear()` keeps the stream alive. First slice of the 0.2.0 `TGLoggerUI` plan.
- CI guard that fails when a file under `docs/` exists on disk but is not tracked by git (defends against the ignore rule above).
- `docs/devnotes/`: development notes index, template, and the first note documenting the `.gitignore` trap.

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

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

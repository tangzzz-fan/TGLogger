# TGLogger

[![CI](https://github.com/tangzzz-fan/TGLogger/actions/workflows/ci.yml/badge.svg)](https://github.com/tangzzz-fan/TGLogger/actions/workflows/ci.yml)

A Swift 6 logging library for Apple platforms. Write logs synchronously like `print`, with levels, categories, call-site tracing, task-local correlation IDs, and pluggable destinations. The default sink is Unified Logging (`os.Logger`).

## Platforms

iOS 17+, macOS 14+, tvOS 17+, watchOS 10+

## Features

- **Levels**: `trace` / `debug` / `info` / `notice` / `warning` / `error` / `fault`
- **Categories**: `subsystem` + `category`, plus a `LogCategory` protocol for typed enums
- **Call-site tracing**: `#fileID` / `#function` / `#line` / `#column` on every `LogRecord`
- **Correlation IDs**: `LogContext.$correlationID` (`@TaskLocal`) inherited by child tasks
- **Structured metadata**: typed `LogValue` (`string` / `int` / `double` / `bool`) with per-key privacy
- **Destinations**: `OSLogDestination`, `PrintDestination`, `MemoryDestination` (ring buffer + live `AsyncStream`), `CapturingDestination` (tests)
- **Optional `TGLoggerUI`**: in-process debug console (`LogConsoleView`) over a `MemoryDestination`; not linked unless you add that product
- **Filtering**: `LogCenter.minimumLevel` plus per-destination floors; messages are `@autoclosure` so filtered calls skip string work
- **Swift 6**: `Sendable` types, synchronous emission, no `MainActor` hop, no `Any`, no `fatalError` in the public API

Not in 0.2.0: file rotation, remote upload, network tracing.

## Example app

Open [`Example/TGLoggerDemo/TGLoggerDemo.xcodeproj`](Example/TGLoggerDemo/TGLoggerDemo.xcodeproj). It is **not** a Swift package product: adding this repo via SPM exposes the `TGLogger` library and the optional `TGLoggerUI` console, never a demo target.

The demo bootstraps `OSLogDestination` + `PrintDestination` + `MemoryDestination`, exercises levels, `LogCategory`, `Logger.with(metadata:)` and `LogContext.$correlationID`, and embeds `LogConsoleView` from `TGLoggerUI` under "Open log console".

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/tangzzz-fan/TGLogger.git", from: "0.2.0")
]
```

Link `TGLogger` always. Add `TGLoggerUI` only for a debug console (typically `#if DEBUG`):

```swift
.product(name: "TGLogger", package: "TGLogger"),
.product(name: "TGLoggerUI", package: "TGLogger"),
```

```swift
#if DEBUG
import TGLoggerUI
// sheet / navigationDestination
LogConsoleView(destination: memory)
#endif
```

## Usage

```swift
import TGLogger

let logs = LogCenter(
    subsystem: Bundle.main.bundleIdentifier ?? "TGLogger",
    destinations: [
        OSLogDestination(),
        MemoryDestination(capacity: 2000)
    ]
)

enum AppLog: String, LogCategory {
    case auth, network, store
}

let auth = logs.logger(AppLog.auth)

auth.info("session started", metadata: [
    "userId": .private(.string(userID))
])

await LogContext.$correlationID.withValue(requestID) {
    auth.debug("refresh token")
}

let checkout = auth.with(metadata: ["screen": .public(.string("Checkout"))])
checkout.notice("pay tapped")
```

Release builds default `minimumLevel` to `.notice`. Debug builds default to `.debug` (`trace` stays opt-in).

Put secrets and user identifiers in metadata, not in the interpolated message string.

## Testing

```swift
let capturing = CapturingDestination()
let logs = LogCenter(
    subsystem: "tests",
    destinations: [capturing],
    minimumLevel: .trace
)
logs.logger(category: "auth").info("hello")
#expect(capturing.snapshot()[0].message == "hello")
```

## Continuous Integration

GitHub Actions runs `swift build` and `swift test` for pushes and PRs targeting `main`.

See [DesignInfo.md](DesignInfo.md) for architecture, [docs/SWIFTUI_CONSOLE.md](docs/SWIFTUI_CONSOLE.md) for the `TGLoggerUI` product split, and [docs/UNTETHERED_LOGGING.md](docs/UNTETHERED_LOGGING.md) for viewing the same records on-device after detaching from Xcode.

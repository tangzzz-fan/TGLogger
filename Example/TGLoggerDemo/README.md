# TGLoggerDemo

iOS 17+ SwiftUI app that shows how to bootstrap and use TGLogger, including the `TGLoggerUI` debug console.

This Xcode project is **not** part of the Swift package. `Package.swift` publishes the `TGLogger` library and the optional `TGLoggerUI` console — the demo links both — but no demo product, so `File → Add Package Dependencies` will not offer an example target.

## Open

1. Open `TGLoggerDemo.xcodeproj` (not the package's `Package.swift`).
2. The app links the local package via `../..` (the package root).
3. Run on an iPhone simulator and use "Open log console" to inspect `LogConsoleView`.

Do not add a second `Package.swift` under `Example/`, and do not depend on `../../../TGLogger`.

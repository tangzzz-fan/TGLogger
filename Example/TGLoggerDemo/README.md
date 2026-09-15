# TGLoggerDemo

iOS 17+ SwiftUI app that shows how to bootstrap and use TGLogger.

This Xcode project is **not** part of the Swift package. `Package.swift` only publishes the `TGLogger` library, so `File → Add Package Dependencies` will not offer a demo product.

## Open

1. Open `TGLoggerDemo.xcodeproj` (not the package's `Package.swift`).
2. The app links TGLogger via a local package reference: `../..` (the package root).
3. Run on an iPhone simulator.

Do not add a second `Package.swift` under `Example/`, and do not depend on `../../../TGLogger`.

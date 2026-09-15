# TGLoggerDemo

iOS 17+ SwiftUI app that shows how to bootstrap and use TGLogger, including the `TGLoggerUI` debug console.

This Xcode project is **not** part of the Swift package. `Package.swift` publishes the `TGLogger` library and the optional `TGLoggerUI` console — the demo links both — but no demo product, so `File → Add Package Dependencies` will not offer an example target.

## Open

1. Open `TGLoggerDemo.xcodeproj` (not the package's `Package.swift`).
2. The app links the local package via `../..` (the package root).
3. Run on an iPhone simulator or device. Use "Open log console", or **shake** (Device → Shake in Simulator; DEBUG iOS only).

## Same records as Xcode (untethered)

One `logger.info` builds one `LogRecord` and writes it to Print (Xcode), Memory (the in-app console), and File (share after kill). They are the same events, not a second reconstructed log.

1. Tap **Simulate accessory session**, then compare Xcode’s console with **Open log console** (or shake).
2. **Product → Stop** (or unplug from the Mac). `print` is gone; the in-app list still tails live. No Wi-Fi relay.
3. Copy from the console toolbar if you need to take a snippet off the phone.
4. **Share log files** sends on-disk `FileDestination` logs (still there after the app is killed).

Details: [docs/UNTETHERED_LOGGING.md](../../docs/UNTETHERED_LOGGING.md).

Do not add a second `Package.swift` under `Example/`, and do not depend on `../../../TGLogger`.

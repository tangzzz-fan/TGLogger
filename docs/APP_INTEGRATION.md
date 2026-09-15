# 真实 App 接入（DEBUG + 连硬件）

给已经发布的 0.3.0 用：现场看日志走手机控制台，会话后再看走落盘文件。不要做 WiFi 回传。

## 1. 依赖

```swift
.package(url: "https://github.com/tangzzz-fan/TGLogger.git", from: "0.3.0")

.product(name: "TGLogger", package: "TGLogger"),
#if DEBUG
.product(name: "TGLoggerUI", package: "TGLogger"),
#endif
```

## 2. Composition root

```swift
import TGLogger
#if DEBUG
import TGLoggerUI
#endif

let memory = MemoryDestination(capacity: 4000)
let file = FileDestination(
    directory: FileDestination.cachesDirectory(),
    maxFileSize: 512_000,
    maxFileCount: 3
)
let logs = LogCenter(
    subsystem: Bundle.main.bundleIdentifier ?? "app",
    destinations: [OSLogDestination(), memory, file]
)
```

Release 可以去掉 `memory`，只留 `OSLogDestination()`（再加 `file` 若你要测完拷文件）。不要把 `PrintDestination` 当成断链后的监视器。

## 3. 打日志

全程用 `logs.logger(...)`，不要用裸 `print`。硬件协议、握手、重试放进 `LogCategory`（例如 `accessory`），需要串起来的请求用 `LogContext.$correlationID`。

## 4. 现场看（及时）

入口必须在**不连 Xcode** 时能打开（调试页 / 连点版本号），不要依赖 LLDB：

```swift
#if DEBUG
LogConsoleView(destination: memory)
#endif
```

这和 Xcode 控制台是同一条 `LogRecord`，只是窗口换成手机。详见 [UNTETHERED_LOGGING.md](UNTETHERED_LOGGING.md)。

## 5. 测完带走

杀进程后内存列表没了，磁盘上的 `file.currentFileURL` / `file.existingFileURLs()` 还在。用系统分享（隔空投送 / 文件）拷走。Demo 里的 **Share log files** 就是这个。

## 6. 不要做的

- WiFi / Bonjour 把日志打到电脑
- 把 `TGLoggerUI` 链进 Release 的默认路径
- 改 `Logger` 为 `async`

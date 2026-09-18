# TGLogger

[![CI](https://github.com/tangzzz-fan/TGLogger/actions/workflows/ci.yml/badge.svg)](https://github.com/tangzzz-fan/TGLogger/actions/workflows/ci.yml)

面向 Apple 平台的 Swift 6 日志库。写法像 `print` 一样同步，但带等级、分类、调用来源、任务内关联 ID，以及可插拔出口。默认写入系统统一日志（`os.Logger`）。

## 平台

iOS 17+、macOS 14+、tvOS 17+、watchOS 10+

## 能力

- **等级**：`trace` / `debug` / `info` / `notice` / `warning` / `error` / `fault`
- **分类**：`subsystem` + `category`；也可用 `LogCategory` 协议做成类型化枚举
- **来源追踪**：每条 `LogRecord` 带 `#fileID` / `#function` / `#line` / `#column`
- **关联 ID**：`LogContext.$correlationID`（`@TaskLocal`），子任务会继承
- **结构化字段**：`LogValue` 为 `string` / `int` / `double` / `bool`，并可按键设置隐私
- **出口**：`OSLogDestination`、`PrintDestination`、`MemoryDestination`（环形缓冲 + 实时 `AsyncStream`）、`FileDestination`（落盘 + 按大小轮转，默认不每行 fsync）、`CapturingDestination`（测试用）
- **可选 `TGLoggerUI`**：基于 `MemoryDestination` 的进程内调试控制台（`LogConsoleView`）；不主动链接就不会带上
- **过滤**：`LogCenter.minimumLevel` 与每个 Destination 自己的下限；`message` 用 `@autoclosure`，被丢掉时不拼字符串
- **Swift 6**：`Sendable`、同步写出、不 hop `MainActor`、公开 API 不用 `Any` / `fatalError`

未做：远程上报、网络抓包 / WiFi 回传。及时看现场用 `TGLoggerUI`；杀进程后再看用 `FileDestination`。

`FileDestination` 默认 **不** 每行落盘（`FileFlushPolicy.never`）：写一行只是写进内核 page cache，进程被杀也不丢；落盘发生在轮转、`close()`、`flush()`，或用 `flushPolicy: .interval(1)` 交给后台定时器。真机主线程上的秒级卡顿正来自旧的「每行 `fsync`」，需要旧行为请显式传 `.everyWrite`。若连轮转和首次开文件都不许占用调用线程，用 `FileDestination.queued()` 包一层（`QueuedDestination`：有界队列 + 丢行记账）。

## 示例工程

打开 [`Example/TGLoggerDemo/TGLoggerDemo.xcodeproj`](Example/TGLoggerDemo/TGLoggerDemo.xcodeproj)。它**不是** Swift 包的 product：用 SPM 添加本仓库时只会看到 `TGLogger` 和可选的 `TGLoggerUI`，不会出现 Demo target。

Demo 会同时挂上 `OSLogDestination`、`PrintDestination`、`MemoryDestination`、`FileDestination`，演示等级、`LogCategory`、`Logger.with(metadata:)`、`LogContext.$correlationID`。点 **Open log console** 或 **摇一摇**（DEBUG iOS）打开 `TGLoggerUI` 的 `LogConsoleView`；**Share log files** 可把落盘文件拷走（杀进程后仍在）。

**和 Xcode 控制台是不是同一批日志：** 一次 `logger.info` 只生成一条 `LogRecord`，再分发给各个出口。Xcode 调试控制台主要是 `PrintDestination`（`print`）；手机上的及时列表是 `MemoryDestination`。内容相同，窗口不同。连硬件必须和 Xcode 断链时，Stop 调试器后 `print` 没了，应用内控制台仍会实时追加。详见 [docs/UNTETHERED_LOGGING.md](docs/UNTETHERED_LOGGING.md)。

## 安装

```swift
dependencies: [
    .package(url: "https://github.com/tangzzz-fan/TGLogger.git", from: "0.5.0")
]
```

日常只链 `TGLogger`。调试控制台再加 `TGLoggerUI`（一般包在 `#if DEBUG`）：

```swift
.product(name: "TGLogger", package: "TGLogger"),
.product(name: "TGLoggerUI", package: "TGLogger"),
```

```swift
#if DEBUG
import TGLoggerUI
// 调试菜单按钮，或根视图摇一摇（仅 DEBUG iOS；Release 为空操作）
ContentView()
    .logConsoleOnShake(destination: memory)
#endif
```

## 用法

```swift
import TGLogger

let logs = LogCenter(
    subsystem: Bundle.main.bundleIdentifier ?? "TGLogger",
    destinations: [
        OSLogDestination(),
        MemoryDestination(capacity: 2000),
        FileDestination(directory: FileDestination.cachesDirectory())
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

Release 构建默认 `minimumLevel` 为 `.notice`；Debug 默认为 `.debug`（`trace` 需显式放低）。

密钥和用户标识放进 metadata，不要插进 message 字符串。

## 测试

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

## 持续集成

推送到 `main` 的提交和 PR 会跑 GitHub Actions：`swift build` 与 `swift test`。

架构见 [DesignInfo.md](DesignInfo.md)；真实 App 接线见 [docs/APP_INTEGRATION.md](docs/APP_INTEGRATION.md)；已有 Factory 时见 [docs/FACTORY.md](docs/FACTORY.md)；面向协议 + 防腐层见 [docs/ANTI_CORRUPTION.md](docs/ANTI_CORRUPTION.md)；`TGLoggerUI` 为何单独成 product 见 [docs/SWIFTUI_CONSOLE.md](docs/SWIFTUI_CONSOLE.md)；断链 Xcode 后如何现场看日志见 [docs/UNTETHERED_LOGGING.md](docs/UNTETHERED_LOGGING.md)。

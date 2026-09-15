# TGLogger 设计说明

TGLogger 是 **同步、Sendable、可插拔 Destination** 的日志管道。调用方像 `print` 一样写日志，但每条记录带等级、分类、调用来源、可选关联 ID，并默认进入系统统一日志。

本库 **不依赖** TGReduxKit / TGFeatureFlag / swift-log。

---

## 1. 数据流

```text
Logger (category + bound metadata)
  → LogCenter（全局最低等级、时钟、单调 id）
      → 读取 LogContext.$correlationID
      → 组装 LogRecord
      → 按 Destination.minimumLevel 过滤
      → Destination.write(_:)（同步、可并发）
```

- `Logger`：值类型，方法全部同步。
- `LogCenter`：引用类型，同一 center 上创建的 logger 共享管道。
- `LogRecord`：不可变 `Sendable` 值。形状保持稳定，后续控制台 / 导出直接消费 `MemoryDestination.snapshot()`，或用 `MemoryDestination.makeRecordsStream()` 订阅实时流。

---

## 2. 并发

- **禁止** 为写日志 hop 到 `MainActor`。
- Destination 必须 `Sendable`，`write` 可被任意线程同时调用。
- `MemoryDestination` / `CapturingDestination` / `LogCenter` 的序号使用 `OSAllocatedUnfairLock`（iOS 16+，满足本包的 iOS 17 下限）。不使用 iOS 18 才有的 `Mutex`。
- `message` 为 `@autoclosure`：center 与全部 destination 都过滤掉时，不拼接字符串。

---

## 3. 隐私

- 日志正文默认 `LogPrivacy.public`（开发者写的静态句子）。
- `LogValue` 默认 `.private`。用 `.public(_:)` / `.private(_:)` / `.sensitive(_:)` 提升或收紧。
- `OSLogDestination` 把整行映射到 `OSLogPrivacy`：任一元数据为 `sensitive` 则整行 `.sensitive`，否则 `private` 优先于 `public`。
- 进程内 destination（print / memory / capturing）保留原文，方便测试与调试。

PII 放进 metadata，不要插进 message。

---

## 4. 等级

| TGLogger | os.Logger |
|----------|-----------|
| trace    | debug 通道，record.level 仍为 trace |
| debug    | debug |
| info     | info |
| notice   | notice |
| warning  | warning |
| error    | error |
| fault    | fault |

`LogCenter.minimumLevel` 默认：DEBUG 为 `debug`，Release 为 `notice`。

---

## 5. 非目标（0.1.0）

- 把 SwiftUI 控制台做成 **package product**（Demo 里用 `MemoryDestination.snapshot()` 自学即可）。为何 Demo 列表 ≠ 库控制台：见 [docs/SWIFTUI_CONSOLE.md](docs/SWIFTUI_CONSOLE.md)。
- 文件轮转、远程上报、网络抓包
- `Logger` 方法变成 `async`
- 公开 API 使用 `Any` 或 `fatalError`

文件与远程应做成新的 `LogDestination`，不必改 `Logger`。

---

## 6. 版本节奏

| 版本 | 内容 |
|------|------|
| **0.1.x** | 核心 API 冻结试用：`LogCenter` / `Logger` / Destination / 来源与 correlation ID。Example 只作教具。 |
| **0.2.0** | 可选独立 product `TGLoggerUI`（进程内控制台）。不放进默认 `TGLogger`，避免只想打日志的 App 链到 SwiftUI。决策见 [docs/SWIFTUI_CONSOLE.md](docs/SWIFTUI_CONSOLE.md)。**进度（2026-09-15）：stream 与 `TGLoggerUI` 已落地，Example 改造待做。** |
| **0.3.0** | `FileDestination`（轮转、体积上限）。仍是新 Destination，不改 Logger。 |
| **1.0.0** | 至少有一个真实 App 用过后再锁公开 API。 |

不单独开 Demo 仓库：Example 跟库同仓，但 **禁止** 写进 `Package.swift` 的 `products` / `targets`。SPM 「Add Package」只会看到 `TGLogger`。克隆仓库的人能看见 `Example/`，这是可接受的折中。

相对 TG 系列现有 Demo 要避开的问题：

- 不要 `executableTarget` / 第二 library，否则安装 SPM 时会出现 Demo product。
- 不要在 Example 里再放一个 `Package.swift`（TGReduxKit 的 Shopping 嵌套包会让仓库结构变乱）。
- 本地包路径用相对 **package 根** 的 `../..`，不要 `../../../TGLogger`（依赖父目录碰巧叫这个名字）。
- 每个 product 只链一次，不要重复 `packageProductDependencies`。

---

## 7. 后续接线（应用侧，不进本包）

TGReduxKitDebug 的 `(String) -> Void` 可接到：

```swift
let logger = logs.logger(category: "redux")
actionLoggingMiddleware { line in
    logger.debug(line)
}
```

TGFeatureFlag 的 `FeatureFlagLogger` 可适配为：

```swift
struct TGLogFeatureFlagLogger: FeatureFlagLogger {
    let logger: Logger
    func log(flag: String, resolvedBy provider: String?, value: FeatureFlagValue?) {
        logger.info(
            "flag resolved",
            metadata: [
                "flag": .public(.string(flag)),
                "provider": .public(.string(provider ?? "default"))
            ]
        )
    }
}
```

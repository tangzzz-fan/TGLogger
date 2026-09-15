# 面向协议 + 防腐层

应用侧做法，**不进** TGLogger 包。本库已经用 `LogDestination` 做出口扩展；那是库内部的插拔点，不是业务模块该依赖的端口。

**可以。** 业务面向协议开发时，在 App / 功能模块和 TGLogger 之间加一层端口（protocol）+ 适配器，用来固定依赖方向、方便以后换实现或收紧可见 API。Composition root、DEBUG 控制台、`FileDestination` 仍按 [APP_INTEGRATION.md](APP_INTEGRATION.md) 接线。

---

## 1. 防腐的是哪条边界

```text
功能模块  →  AppLogging 协议（应用拥有）
                 ↑
                 │ 适配器（唯一 import TGLogger 的业务入口）
                 │
           LogCenter / Logger / Destination / TGLoggerUI
```

| 留在 composition | 功能模块只看见 |
|------------------|----------------|
| `LogCenter`、各 Destination、`TGLoggerUI` | 自己的 `AppLogging` / `CategoryLogging` |
| 文件轮转、控制台、Factory 注册 | `info` / `debug` / 关联 ID / category |

不要把 `LogDestination` 再包一层当业务协议。换日志库时改的是适配器，不是再实现一个 Destination。

---

## 2. 三种厚度（选一层即可）

| | 功能模块依赖 | 换库成本 | 代价 |
|--|-------------|----------|------|
| **A. 只藏管道** | 直接用 `Logger` | 中（类型仍来自本库） | 最低。`Logger` 已是 `Sendable` 值，不知道 Destination |
| **B. 端口 + 适配器（推荐）** | 应用协议；签名可继续用 `LogMetadata` / `LogPrivacy` | 低：改适配器，必要时改协议 | 见 §4 的 `@autoclosure` |
| **C. 类型完全隔离** | 自己的 level / fields 枚举 | 最低 | 映射样板最多，日常重复高 |

多数面向协议的 App 用 **B**：隔离 `LogCenter` 和 UI，不重复造一套 metadata。

---

## 3. 推荐端口（B）

协议放在**不依赖 UI** 的模块。默认参数写在 **extension** 里，这样 `#fileID` / `#line` 是调用方，而不是适配器。

```swift
import TGLogger

enum AppLog: String, Sendable {
    case auth, network, accessory
}

protocol AppLogging: Sendable {
    func logger(_ category: AppLog) -> any CategoryLogging
}

protocol CategoryLogging: Sendable {
    func with(metadata: LogMetadata) -> any CategoryLogging

    func info(
        _ message: @escaping () -> String,
        metadata: LogMetadata,
        privacy: LogPrivacy,
        fileID: String,
        function: String,
        line: UInt,
        column: UInt
    )
    // debug / warning / error / … 同样形状
}

extension CategoryLogging {
    func info(
        _ message: @autoclosure @escaping () -> String,
        metadata: LogMetadata = [:],
        privacy: LogPrivacy = .public,
        fileID: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        info(
            message,
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }
}
```

`with(metadata:)` 返回 `any CategoryLogging`，避免 `Self` 在 existential 上不好用。关联 ID 继续 `LogContext.$correlationID`（TaskLocal，与协议无关）。若连 `LogContext` 也不想让功能模块看见，在适配器的每条 emit 上把自己的 TaskLocal 映射进去。

---

## 4. 适配器

```swift
import TGLogger

struct TGAppLogging: AppLogging {
    let center: LogCenter

    func logger(_ category: AppLog) -> any CategoryLogging {
        TGCategoryLog(logger: center.logger(category: category.rawValue))
    }
}

struct TGCategoryLog: CategoryLogging {
    let logger: Logger

    func with(metadata: LogMetadata) -> any CategoryLogging {
        TGCategoryLog(logger: logger.with(metadata: metadata))
    }

    func info(
        _ message: @escaping () -> String,
        metadata: LogMetadata,
        privacy: LogPrivacy,
        fileID: String,
        function: String,
        line: UInt,
        column: UInt
    ) {
        logger.info(
            message(),
            metadata: metadata,
            privacy: privacy,
            fileID: fileID,
            function: function,
            line: line,
            column: column
        )
    }
}
```

`LogCategory` 可以让 `AppLog` 直接遵循，于是写成 `center.logger(category)`，不必 `.rawValue`。

**`@autoclosure`：** 功能侧 extension 仍然懒求值；适配器调用 `message()` 后再交给 `Logger.info` 时，字符串会在适配器里求一次。公开 API 目前没有 `() -> String` 重载，过滤掉的日志**过了防腐层就会拼字符串**。这是这层的代价，不是去把 `Logger` 改成 `async`。若「未过阈值绝不拼」是硬约束，用 §2 的 A，功能模块直接持有 `Logger`。

---

## 5. 功能模块怎么写

```swift
final class SessionService: Sendable {
    private let logging: any AppLogging

    init(logging: any AppLogging) {
        self.logging = logging
    }

    func start(userID: String) {
        logging.logger(.auth).info(
            "session started",
            metadata: ["userId": .private(.string(userID))]
        )
    }
}
```

不要 `import TGLoggerUI`，不要拿 `LogCenter`。测试塞一个录音假类型即可，不必起 `LogCenter`：

```swift
final class RecordingLog: CategoryLogging, @unchecked Sendable {
    var messages: [String] = []
    func with(metadata: LogMetadata) -> any CategoryLogging { self }
    func info(_ message: @escaping () -> String, metadata: LogMetadata, privacy: LogPrivacy, fileID: String, function: String, line: UInt, column: UInt) {
        messages.append(message())
    }
}
```

---

## 6. 和 Factory 一起用

管道仍按 [FACTORY.md](FACTORY.md) 做 **singleton**。功能模块注入协议，不注入 `LogCenter`：

```swift
extension Container {
    var appLogging: Factory<any AppLogging> {
        self { TGAppLogging(center: self.logCenter()) }
            .singleton
    }
}

final class SessionService {
    @Injected(\.appLogging) private var logging
}
```

`LogConsoleView` / `ShareLink` 仍然解析 `memoryDestination` / `fileDestination` 那两个 singleton，不要从 `any AppLogging` 里掏。

---

## 7. 不要做的

- 在 TGLogger 包里加 `AppLogging`（端口属于应用）
- 协议方法写成 `async`，或在适配器里 hop `MainActor`
- 默认参数写在适配器实现上（来源会全部变成适配器文件）
- 功能模块直接 new `MemoryDestination` / `FileDestination`（和 center 不是同一实例）
- 为了「以后好换」去包 Destination 或做 WiFi 回传

# 已有 Factory 时怎么接 TGLogger

应用侧接线，**不进** TGLogger 包：本库不依赖 [Factory](https://github.com/hmlongco/Factory)，也不提供 Container 扩展。

Factory 2.5+ 用 `import FactoryKit`；2.4 及更早用 `import Factory`。下面的注册写法相同。

场景与出口选择仍按 [APP_INTEGRATION.md](APP_INTEGRATION.md)：及时看用同一个 `MemoryDestination` + `LogConsoleView`；杀进程后再看用同一个 `FileDestination`。不要做 WiFi 回传。

---

## 1. 原则

| 对象 | Factory 作用域 | 原因 |
|------|----------------|------|
| `MemoryDestination` | **`.singleton`** | `LogCenter` 与 `LogConsoleView` 必须拿**同一实例** |
| `FileDestination` | **`.singleton`** | 分享面板必须拿挂在 center 上的那份文件 |
| `LogCenter` | **`.singleton`** | 全应用一条管道、一套单调 id |
| `Logger` | 默认 unique，或根本不注册 | 值类型，内部只握着 center；按 category 现取即可 |

不要在 `LogCenter` 的闭包里 `MemoryDestination()` / `FileDestination(...)` 再 new 一份，同时又注册了这两个 Factory：控制台或分享会接到**空的另一份** destination。

不要给这些 Factory 标 `@MainActor`。写出日志禁止 hop 主线程；后台代码也要能解析。

---

## 2. Container 注册

```swift
import FactoryKit
import TGLogger

enum AppLog: String, LogCategory {
    case auth, network, accessory
}

extension Container {
    var memoryDestination: Factory<MemoryDestination> {
        self { MemoryDestination(capacity: 4000) }
            .singleton
    }

    var fileDestination: Factory<FileDestination> {
        self {
            FileDestination(
                directory: FileDestination.cachesDirectory(),
                maxFileSize: 512_000,
                maxFileCount: 3
            )
        }
        .singleton
    }

    var logCenter: Factory<LogCenter> {
        self {
            LogCenter(
                subsystem: Bundle.main.bundleIdentifier ?? "app",
                destinations: [
                    OSLogDestination(),
                    self.memoryDestination(),
                    self.fileDestination()
                ]
            )
        }
        .singleton
    }
}
```

Release 不想带内存控制台时，用 `#if DEBUG` 决定 `destinations` 数组里要不要 `memoryDestination()`；**不要**把 `PrintDestination` 当成断链后的监视器。

---

## 3. 业务里怎么打日志

推荐注入 `LogCenter`，在类型里按 category 取 `Logger`（廉价值）：

```swift
final class SessionService: Sendable {
    @Injected(\.logCenter) private var logs

    func start(userID: String) {
        let auth = logs.logger(AppLog.auth)
        auth.info("session started", metadata: [
            "userId": .private(.string(userID))
        ])
    }
}
```

`@Observable` 类型里写成 `@ObservationIgnored @Injected(\.logCenter)`，避免宏把包装器当状态。

需要串起来的请求仍然用 `LogContext.$correlationID`，与 Factory 无关。

功能模块若走自己的 `AppLogging` 协议，Container 注册 `any AppLogging` 而不是把 `LogCenter` 注进每个服务。见 [ANTI_CORRUPTION.md](ANTI_CORRUPTION.md)。

若某模块只关心一个 category，可以再加具名 Factory，**不要**用带 `.singleton` / `.cached` 的 `ParameterFactory<String, Logger>`（默认按第一次参数缓存，后面的 category 会拿到错误的 Logger）：

```swift
extension Container {
    var authLogger: Factory<Logger> {
        self { self.logCenter().logger(AppLog.auth) }
    }
}
```

---

## 4. 调试控制台与分享（同一实例）

```swift
#if DEBUG
import TGLoggerUI

struct DebugLogPage: View {
    var body: some View {
        LogConsoleView(destination: Container.shared.memoryDestination())
    }
}
#endif

ShareLink(
    "Share log files",
    items: Container.shared.fileDestination().existingFileURLs()
)
```

入口必须在不连 Xcode 时能打开。详见 [UNTETHERED_LOGGING.md](UNTETHERED_LOGGING.md)。

---

## 5. 测试

测业务时把管道换成 `CapturingDestination`。它也必须是 singleton，断言与写入是同一份：

```swift
extension Container {
    var capturingDestination: Factory<CapturingDestination> {
        self { CapturingDestination() }
            .singleton
    }
}

// 每个用例前
Container.shared.manager.reset()
Container.shared.logCenter.register {
    LogCenter(
        subsystem: "tests",
        destinations: [Container.shared.capturingDestination()],
        minimumLevel: .trace
    )
}

// 触发被测代码后
#expect(Container.shared.capturingDestination().snapshot()[0].message == "session started")
```

若项目已用 Factory 的 `.onTest { }`，可以把上面的 `register` 写进 `logCenter` 的 `.onTest`，效果相同。

---

## 6. 不要做的

- 把 Factory 加进 TGLogger 的 `Package.swift`
- `LogCenter` 与 `LogConsoleView` / `ShareLink` 各自 new destination
- 给 `Logger` 的 `ParameterFactory` 加上会忽略后续参数的 scope
- 把 `logCenter` 标成 `@MainActor`，或把 `Logger` 改成 `async`
- WiFi / Bonjour 把日志打到电脑

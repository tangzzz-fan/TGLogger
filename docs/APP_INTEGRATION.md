# 真实 App 接入（DEBUG + 连硬件）

给已经发布的 0.4.0 用：现场看日志走手机控制台（按钮或摇一摇），会话后再看走落盘文件。不要做 WiFi 回传。

## 1. 依赖

```swift
.package(url: "https://github.com/tangzzz-fan/TGLogger.git", from: "0.4.0")

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

项目里已经用了 Factory（`FactoryKit` / `import Factory`）时，把 `LogCenter`、`MemoryDestination`、`FileDestination` 注册成 **singleton**，控制台和分享必须解析到挂在 center 上的同一实例。完整写法见 [FACTORY.md](FACTORY.md)。TGLogger **不**依赖 Factory。

面向协议开发、想在功能和本库之间加防腐层时：协议放在应用模块，composition root 再接到 `Logger`。见 [ANTI_CORRUPTION.md](ANTI_CORRUPTION.md)。

## 3. 打日志

全程用 `logs.logger(...)`，不要用裸 `print`。硬件协议、握手、重试放进 `LogCategory`（例如 `accessory`），需要串起来的请求用 `LogContext.$correlationID`。

## 4. 现场看（及时）

入口必须在**不连 Xcode** 时能打开（调试页 / 连点版本号 / **摇一摇**），不要依赖 LLDB：

```swift
#if DEBUG
ContentView()
    .logConsoleOnShake(destination: memory)
#endif
```

`.logConsoleOnShake` 只在 **DEBUG iOS** 生效（Release / 其它平台是空操作）。系统「摇一摇撤销」会抢走事件，DEBUG 下设 `UIApplication.shared.applicationSupportsShakeToEdit = false`。手机平放连硬件时仍保留按钮。自定义 `UIWindow` 可在 `motionEnded(.motionShake)` 里调用 `LogConsoleShake.notify()`（FLEX 同类接法）。

这和 Xcode 控制台是同一条 `LogRecord`，只是窗口换成手机。详见 [UNTETHERED_LOGGING.md](UNTETHERED_LOGGING.md)。

## 5. 测完带走

杀进程后内存列表没了，磁盘上的 `file.currentFileURL` / `file.existingFileURLs()` 还在。用系统分享（隔空投送 / 文件）拷走。Demo 里的 **Share log files** 就是这个。

## 6. 不要做的

- WiFi / Bonjour 把日志打到电脑
- 把 `TGLoggerUI` 链进 Release 的默认路径
- 改 `Logger` 为 `async`

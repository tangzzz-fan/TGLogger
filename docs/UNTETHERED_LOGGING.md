# 与 Xcode 断链后如何拿到及时日志

**场景**：App 要连硬件设备（口被配件占用、或调试器不能挂着），必须和 Xcode 断开。Xcode 控制台、`print`、`PrintDestination` 都没了。

**约束**：不需要 WiFi / 局域网把日志回传到 Mac。开发人员能在**当时当地**看见日志即可。

**结论**：用已经随 0.2.0 发布的 `MemoryDestination` + `TGLoggerUI`。日志打在手机上的控制台里，流式更新，不经过 Mac。

---

## 1. 断链之后，现有出口各自还剩什么

| 出口 | 断链 Xcode 之后 | 及时？ |
|------|-----------------|--------|
| `PrintDestination` / `print` | 没有 stderr 接收方 | 否 |
| `OSLogDestination` | 仍写入系统日志；要插回电脑用 Console.app 才能搜 | 否（事后） |
| `MemoryDestination` | 还在进程里 | 是（给 UI 用） |
| `LogConsoleView` | 手机屏幕上的列表，跟 `makeRecordsStream` 走 | **是** |

所以「及时」= 人盯着手机，不是盯着 Mac。不要做网络 Destination，也不要把 `os.Logger` 当成现场监视器。

---

## 2. 推荐接法（DEBUG）

```swift
import TGLogger
#if DEBUG
import TGLoggerUI
#endif

let memory = MemoryDestination(capacity: 4000)
let logs = LogCenter(
    subsystem: Bundle.main.bundleIdentifier ?? "app",
    destinations: [
        OSLogDestination(),
        memory
    ]
)

#if DEBUG
// 调试菜单 / 连点版本号 / 摇一摇 → 推出
LogConsoleView(destination: memory)
#endif
```

要点：

- `PrintDestination` 在断链场合并上没有意义，可以不加。
- 环形缓冲按硬件会话长度加容量（几千条），避免刷协议日志时把关键错误挤掉。
- 入口必须能在**不连 Xcode** 时打开：应用内 DEBUG 页，不要依赖 LLDB。
- 控制台已有过滤和 Copy。需要把一段日志拷到备忘录 / 隔空投送时用 Copy，这是人触发的带走，不是日志通道回传。

Example 工程里的 **Simulate accessory session** + **Open log console** 就是这个模型：先对比 Xcode 与手机列表，再 Product → Stop，列表仍会追加。

---

## 3. 做了仍然看不到时

1. 有没有把同一个 `MemoryDestination` 实例交给 `LogCenter` **和** `LogConsoleView`。
2. `LogCenter.minimumLevel` 是否把硬件协议的 `debug`/`trace` 滤掉了（DEBUG 默认是 `debug`，`trace` 要显式放低）。
3. 进程被杀掉则内存缓冲清空——这是「及时看现场」的代价。若还要**杀进程之后**再看，那是 0.3.0 `FileDestination` 的事，不是本场景的及时性。

---

## 4. 明确不做

- WiFi / Bonjour / WebSocket 把日志打到电脑。
- 把控制台塞进默认 `TGLogger` product。
- 为了连硬件去改 `Logger` 变成 `async`。

`FileDestination` 仍列在 0.3.0：只解决「会话结束或崩溃后把文件拷出来」，不替代手机上的即时列表。

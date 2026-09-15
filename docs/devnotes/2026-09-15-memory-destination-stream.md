# 给 `MemoryDestination` 加实时流：0.2.0 的第一刀

`标签: 功能落地` | `模块: Sources/TGLogger/Destinations/MemoryDestination.swift` | `深度: BRIEF` | `状态: 已解决`

## 3 行速览

- **结论**：`MemoryDestination` 新增 `makeRecordsStream(bufferingPolicy:)`，返回 `AsyncStream<LogRecord>` 实时尾流。这是 `docs/SWIFTUI_CONSOLE.md` §6 二选一里的第 1 方案；第 2 方案（同步回调）按决定永久不做。
- **影响**：核心库新增一个公开方法（纯增量，0.1.x 行为不变）；`TGLoggerUI` 的 store 以后只 `for await` 就能更新列表，不用再按 Refresh。
- **细读建议**：只要知道「订阅在写入之后、取消即清理」就够用；好奇为什么多个消费者要靠一个包装类摘除订阅，看 §2。

## 形成过程

1. **需求边界先于实现**：§6 早已冻结三条——不许 hop `MainActor`、不许用 Combine、`LogRecord` 不改形状。剩下的自由度只有：流要不要重放历史？答：**不重放**。历史是 `snapshot()` 的职责，流只做 live tail，职责不重叠，行为最好解释。
2. **岔路口——多消费者怎么存**：`AsyncStream` 一个流只支持一个消费者，所以每个订阅者发一条独立流，`write` 后逐个 `yield`。第一直觉是把 `AsyncStream<LogRecord>.Continuation` 直接塞进 `Ring` 数组，摘除订阅时用 `===` 按身份移除。
3. **被推翻**：编译器打脸——`AsyncStream.Continuation` 是 **struct**，`===` 不编译（`Tests` 红灯先给出这个信号）。修法：加一个极小的 `final class StreamBox: Sendable` 持有 continuation，数组存 box，摘除按 box 身份。`Continuation` 本身是 `Sendable`，box 才能也标 `Sendable`。
4. **第二个取舍——背压**：默认缓冲策略选 `.unbounded`，代价是「停止读取但不取消的消费者会积内存」；所以 API 留了 `bufferingPolicy` 参数，UI 场景可以传 `.bufferingNewest(1)` 用丢记录换上限。为什么不默认收紧？控制台场景丢记录比占内存更难被用户接受，且消费者就是自己写的 store，可控。

## 落地要点

| 文件 | 改动 |
|------|------|
| `MemoryDestination.swift` | `makeRecordsStream(bufferingPolicy:)` + `StreamBox` 身份包装 + `write` 里在锁内取快照、锁外 yield（缩短临界区）；`activeStreamCount` 为 internal，仅供测试观察 |
| `TGLoggerTests.swift` | 新 suite「MemoryDestination streaming」4 例：订阅后收新记录、**不重放历史**、双流 fanout、`clear()` 不断流 |
| `CHANGELOG.md` / `DesignInfo.md` / `docs/SWIFTUI_CONSOLE.md` §6 | 状态同步：方案 1 已实现 |

时序：测试先写、先红（`no member 'makeRecordsStream'`），实现后绿。

## 验证

- 23 用例 / 7 suite 全绿，连跑 3 次无抖动（异步测试里用「轮询 `activeStreamCount` + 2s 超时」把订阅竞态变成确定性等待，而不是 `Task.yield` 碰运气）。
- **未验证**：真实 SwiftUI 消费端（`TGLoggerUI` 还不存在）——留给下一步实现 store 时验收；`bufferingNewest` 收紧策略目前没有专项测试。
- 约束自查：`write` 全程无 `MainActor`、无 `Task { @MainActor }`；未引入 Combine；`LogRecord` 零改动。

## 下一步与遗留

1. `TGLoggerUI` product：`LogConsoleStore`（`@MainActor @Observable`）订阅此流 + `snapshot()` 补历史。
2. Example 改用 `TGLoggerUI`，删自制 List。
3. 可选：给 `.bufferingNewest` 策略补一条专项测试。

---

## 相关手记

- [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md)（同日的仓库卫生修复）；决策背景见 [`docs/SWIFTUI_CONSOLE.md`](../SWIFTUI_CONSOLE.md) §6。

# `TGLoggerUI` 落地：控制台 product、两个 Swift 6 / 时序坑

`标签: 功能落地` | `模块: Sources/TGLoggerUI/` | `深度: BRIEF` | `状态: 已解决`

## 3 行速览

- **结论**：新增可选 product `TGLoggerUI`（只依赖 `TGLogger`）：`LogConsoleView`（过滤条 + 倒序列表 + 复制/清空）、`LogConsoleStore`（`@MainActor @Observable`）、`LogConsoleFilter`（等级/分类/全文/corr ID）。规格出自 `docs/SWIFTUI_CONSOLE.md` §5–§7，未超出。
- **影响**：SPM「Add Package」现在会看到两个 library——这是设计内行为（可选能力 ≠ Demo 升格）；`TGLogger` 本体依然零 SwiftUI。
- **细读建议**：两个坑都有复用价值——① 初始化表达式里 Task 捕获未初始化完的 `self`；② 「先快照后订阅」的时序缺口。见 §2。

## 形成过程（两段弯路）

**坑 ①：`Task { [weak self] }` 赋给 `let` 属性，编译器报 `used before being initialized`。**
第一直觉是按常见模式 `self.task = Task { ... }` 写。报错的本意：逃逸捕获发生在 `consumptionTask` 自己的初始化表达式里，此刻 `self` 还没初始化完，任何 self 捕获都非法。
修法：属性改成 `private var consumptionTask: Task<Void, Never>?`（optional var 一出生就是 `nil`，等所有非 optional 属性赋完，`self` 即视为完整），并标 `@ObservationIgnored` 防 `@Observable` 宏把它当状态。`deinit` 里 `consumptionTask?.cancel()` 断流取消订阅。

**坑 ②：先 `snapshot()` 后异步订阅，缝隙丢记录（测试先红抓到的）。**
第一版 store：init 里先 `records = snapshot().reversed()`，再在 Task 里 `for await makeRecordsStream()`。测试立刻失败——store 永远只有 history，没有 live。本质陈述卡：
- **因果链**：因为快照在 init 同步执行、而订阅要等 Task 被调度后才注册 → 快照与订阅之间存在窗口 → 窗口内写入的记录既不在快照里、也不会被流推送 → 界面静默丢日志。
- **层级**：③ 根因 = 两个数据源的接续点依赖「任务调度时机」，没有同步原语保证先后衔接。
- **代码定位**：`LogConsoleStore.init`（修复前 `LogConsoleStore.swift:55-65`）。
- **可切换性**：把测试的写入挪到订阅注册之后则消失（已在 stream 测试里用 `activeStreamCount` 轮询验证过这个机制）；本修复后在无人工等待下用例转绿。置信度: 高 ｜ 反证：若日后发现 UI 仍偶发缺最早一条，优先怀疑此处窗口回归。
- 修法顺序反转：**先 `makeRecordsStream()`（注册是同步的，注册即无丢窗）→ 再 `snapshot()`**。代价是窗口期记录两边都出现，用 `seedIDs: Set<UInt64>` 去重——比「比较最大 id」稳，因为多 `LogCenter` 共用一个 destination 时 id 不再全局单调。

## 落地要点

| 文件 | 改动 |
|------|------|
| `Package.swift` | product `TGLoggerUI` + target（依赖 `TGLogger`）；测试 target 加依赖 |
| `Sources/TGLoggerUI/LogConsoleStore.swift` | store + filter（详见速览） |
| `Sources/TGLoggerUI/LogConsoleView.swift` | 过滤条、行视图（等级徽标/分类/id/message/metadata/来源/corr）、复制单条或整份导出、清空；剪贴板按 `canImport(UIKit/AppKit)` 分派 |
| `Tests` | 新 suite 4 例：种子+跟随、容量修剪、四种过滤、`clear` 双清 |

**仍未做（有意的）**：Example 改用 `TGLoggerUI` 需动 Xcode 工程的 `packageProductDependencies`，放到下一刀单独做，避免和本次 SPM 改动混在一个提交里。
**（当晚追加）Example 迁移已完成**：pbxproj 增加 `TGLoggerUI` product 依赖（沿用既有编号风格，`plutil -lint` 通过）；`ContentView` 删掉自制 List/Row，改为 "Open log console" 推入 `LogConsoleView`；`DemoLogStore` 去掉 `records`/`refresh()`，只留发射动作与 `memory`。**用户在 Xcode 中确认编译通过。**

**验证的环境教训（会重复）**：本机代理环境里 `xcodebuild` / 裸 `swiftc` 的宏插件链路会报 `sandbox-exec: sandbox_apply: Operation not permitted`（Xcode 内部 SwiftPM 申请嵌套 seatbelt 被拒；独立的 `sandbox-exec` 反而可用，`SWIFTPM_DISABLE_SANDBOX` 无效）。**能走通的替代路径**：① `swift test --disable-sandbox`；② 在 /tmp 造一个检查包，把待验证源文件作为 `executableTarget`（`swiftSettings: [.defaultIsolation(MainActor.self)]`，注意该 API 需 tools 6.2）依赖本包两个 product，`swift build --disable-sandbox`。注意 `swift build --triple <iOS sim>` 不行：SDKROOT 会泄漏进 manifest 编译。最终仍需 Xcode 里真机/模拟器确认渲染。

## 验证

- 27 用例 / 8 suite 全绿 × 3 次（含新 4 例；红→绿路径：坑②先被用例抓出）。
- `swift package describe` 确认两个 product 各自正确。
- **Example 编译：用户在 Xcode 中确认通过**（代理环境的 xcodebuild 沙箱限制挡住了命令行验证路径，见落地要点末尾的环境教训）。
- **未验证**：模拟器上的 SwiftUI 渲染与交互（"Open log console" 推入、过滤、清空）——留给真实使用反馈；`UIHostingController` 嵌入路径同样未跑。

## 下一步与遗留

1. Example 改 `import TGLoggerUI`，删自制 `LogRecordRow`（下一刀，需动 pbxproj）。
2. 发 0.2.0 tag；README 安装段届时补 `TGLoggerUI` 用法。

---

## 相关手记

- [memory-destination-stream](2026-09-15-memory-destination-stream.md)（流的最小口子，本篇的依赖前提）；决策背景 [`docs/SWIFTUI_CONSOLE.md`](../SWIFTUI_CONSOLE.md) §5–§7。

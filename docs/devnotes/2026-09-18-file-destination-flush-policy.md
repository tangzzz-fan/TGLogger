# `FileDestination` 每行 fsync 卡死主线程：从「app 包异步」到删掉补偿层

`标签: bug 修复 + 功能落地` | `模块: Sources/TGLogger/Destinations/FileDestination.swift` | `深度: FULL` | `状态: 已解决（待真机复测）`

## 3 行速览

- **结论**：0.3.0 / 0.4.0 的 `FileDestination` 每写一行就在调用线程 `synchronize()`，iOS 日志几乎全从主线程打 → 每行一次闪存 `fsync`。真机 stall **7931 / 3062 / 861 ms**、启动到首帧 **30607 ms**，模拟器 **0 笔**。默认改为 `FileFlushPolicy.never`，并把「同步」的契约写清楚。
- **影响**：0.5.0 起 `FileDestination` 的 `write` 只剩微秒级 page-cache 追加；`init` 不再碰磁盘；新增 `flush()`、`FileFlushPolicy`、`FlushableDestination`，以及预备好的逃生口 `QueuedDestination`。**行为变更**：需要 0.3/0.4 的每行落盘要显式 `.everyWrite`。
- **细读建议**：§4 本质（「同步」被误读成「调用线程做 I/O」）是这次最值得记的一段；§2 有一个差点做错的方向（把异步搬进库）。

---

## 1. 现象

App（joveview）真机 DEBUG，`FileDestination` 直连 `LogCenter`、未做任何异步包装：

| 观测 | 值 |
|------|-----|
| 主线程 stall | **7931 / 3062 / 861 ms** |
| 启动到首帧 | **30607 ms** |
| 同一段调用里两行日志的时间戳差 | **9 s**（时间戳在 record 创建时取） |
| 模拟器 | **0 笔**（Mac SSD 的 fsync 快，Demo 验收看不到） |
| 从管道拿掉 `FileDestination` | 秒级 hang 消失 |

反馈原文还带一句精确的定位：「协议要求 `write` 同步、不 hop `MainActor` —— 这条对。但『不 hop MainActor』不等于『可以在主线程 fsync』。」

## 2. 第一直觉与它的偏差

**第一直觉（我）**：「每行落盘是为了崩溃时不丢日志，这是耐久性取舍，去掉要慎重。」
**实际**：`FileHandle.write` 落到的是**内核 page cache**，**进程崩溃（含 jetsam 强杀）本来就不丢**；`fsync` 只防**整机断电 / 内核崩溃**。所以「每行 fsync」换来的不是「不丢日志」，而是「从『崩溃不丢』升级到『断电不丢』」——用一个 9 秒级的主线程 stall 去换一个 DEBUG 场景根本不在乎的属性。

第二个偏差更值得记：被告知「app 侧已经用异步队列包了 `write`」时，我的第一反应是把这层异步**搬进库**（`FileDestination` 内建队列）。复审后推翻：**那圈异步是补偿层**。根因修掉后它不再解决任何问题，正确的动作是**删掉它**，而不是给它搬家——把补偿层固化进库，等于把「默认行为有毒」这个事实永久合法化。

补一条量化依据（本机 macOS SSD，仅用于看量级，真机闪存差 2–3 个数量级）：

| 操作 | 实测 |
|------|------|
| `open + seekToEnd` | 0.006 ms / 次 |
| `write` 一行（140 B，不 fsync） | **1.9 µs / 行** |
| `write + synchronize` | **25.8 µs / 行**（本机 13×） |
| `remove + move + create`（一次 rotate） | 0.37 ms / 次 |

结论：去掉每行 fsync 后，1000 行/秒的主线程成本 ≈ 1.9 ms/秒（0.02%）。

## 3. 排查路径

| 假设 | 验证 | 结论 |
|------|------|------|
| 是 `MemoryDestination` / 控制台在拖 | 反馈已做对照：从管道拿掉 `FileDestination` 后 hang 消失 | ✗ 排除 |
| 是 `LogCenter` 串行化（锁）导致 | 读代码：`LogCenter.emit` 只做过滤 + 组装，无 I/O | ✗ 排除 |
| 是每行 `synchronize()` | 定位 `FileDestination.swift:73`（0.4.0），确认在调用线程、且**持 unfair lock** | ✓ 成立 |
| 是不是必须有它 | 追 durability 语义 → page cache 事实（见 §2） | ✓ 默认可以去掉 |
| 该把异步放进库还是删掉补偿层 | 复审（见 §2 第二偏差） | ✓ 删补偿层；异步做成可选装饰器 |

死胡同记录：一度想用「单元测试断言 fsync 没发生」来验收这次修复——**做不到**。读了 page cache 就知道读文件结果与 fsync 无关，见 §6。

## 4. 本质陈述卡

- **一句话**：把「写日志保持同步」这条**调用约定**，实现成了「调用线程亲自做存储 I/O」，于是在主线程上放了一次行级 `fsync`。
- **因果链**：因为 `write` 被要求同步完成 → 实现者把「同步」理解成「此刻必须在调用线程做完落盘」→ 每行 `handle.write` 后跟 `handle.synchronize()` → 调用线程阻塞在闪存往返上 → iOS 日志几乎全在主线程打 → 主线程 stall 达秒级，且时间戳间隔被拉长到 9 秒。
- **边界**：
  - 必然发生：只要「调用线程 = 主线程」且「日志速率 × 单次 fsync 成本」超过帧预算（真机 fsync 毫秒级，几十行就够）。
  - 不会发生：模拟器 / Mac（SSD fsync 快，Demo 验收看不到）；后台线程写日志的场景；日志量极低（每分钟几行）时不明显。
- **层级**：① 触发条件 = 日志从主线程打 + 每行 fsync；② 机制 = 调用线程同步 `fsync`；③ **根因** = 「同步」这一调用约定被实现为「调用线程亲自执行 I/O」，即契约只约束了「什么时候返回」，没约束「谁付成本」；④ 系统性原因 = 包内只规定了「不 hop `MainActor`」，没有一条写死 `write` 的成本上限，也没有真机性能回归门禁。
- **代码定位**（0.4.0 `9b8fed9`）：`Sources/TGLogger/Destinations/FileDestination.swift:73`（每行 `synchronize()`）；`init` 在 `:45-47` 构造即 open，与同文件 `:23` 的 "creating nothing until used" 自相矛盾。
- **解释力自查**：
  - 能解释：真机秒级 stall、两行日志隔 9 秒、模拟器 0 笔、拿掉 destination 即恢复、启动到首帧 30 秒（构造在主线程 + 首屏期间的首批日志各付一次 fsync）。
  - **解释不了**：为什么单次 stall 高达 7931 ms（单次 fsync 通常 <100 ms，推测是**持锁排队**把后续写入全部串在同一缓存线上 + 现场存储压力；**（猜测，未验证）**）。
- **可切换性验证**：
  - 移除 → 消失：**已验**（反馈侧从管道拿掉 `FileDestination`，hang 消失）。
  - 加回 → 复现：**部分已验**（模拟器上加不回来——同一份代码在本机 fsync 只要 25.8 µs，这本身是个反例，见下）；真机加回复现由反馈方提供。
- **反例**：模拟器 / Mac 上，同样的代码**不会**产生任何可观 stall —— 同一 bug 的行为完全依赖「底层存储的 fsync 成本」，说明它不是逻辑错误而是**成本量级错配**，这也是它能在 0.3/0.4 两次发版中存活的原因。
- **复核提示**：若将来 `FileDestination` 改为内建异步队列、或 iOS 引入 write-behind 语义，本节机制失效。
- **置信度**：**高**（真机数据 + 代码定位 + 本机量级三重一致）。**如果我错了，会怎么发现**：真机复测（T3）里删掉 app 侧异步包装、直连 `FileDestination` 后仍出现 >100 ms 的主线程尖峰。

## 5. 修复方案

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `FileFlushPolicy.swift`（新） | `.never`（默认）/ `.interval(_:)` / `.everyWrite`；`interval` 下限钳到 50 ms | 把「耐久性策略」从隐藏行为变成显式选择；需求方自己说了算 |
| `FileDestination.swift` | 默认 `.never`：`write` 只在 `.everyWrite` 时 `synchronize()`；`init` 不再碰磁盘（首次 `write` 才 open/create/seek）；新增 `public func flush()`；`close()` 同时取消定时器；`deinit` 取消定时器；`.interval` 用 `DispatchSourceTimer` 在私有串行队列（非 `MainActor`）落盘 | 修根因；`rotate` / `close` / `flush` 保留强制落盘点 |
| `FlushableDestination.swift`（新） | `LogDestination` + `flush()` / `close()` | 让「有后备存储的 destination」有一个统一的、不靠 downcast 的落盘入口 |
| `QueuedDestination.swift`（新，预备） | 有界队列 + 私有串行队列写出 + `flush()` 屏障 + 溢出丢最旧并记账 + 批次头部插入 `tglogger.queue` 说明行；`FileDestination.queued()` convenience | 万一真机复测仍有尖峰，逃生口已就位，**且由库提供**——不让每个接入方各写一份 |
| `LogDestination.swift` | 契约文案：`write` 必须**及时返回**（微秒级 encode + 进程内缓冲）、必须保持每 destination 顺序、绝不 hop `MainActor`；慢 I/O 交给私有队列或 `FlushableDestination` | 这次事故的直接原因是契约只写了「不 hop MainActor」，没写成本上限 |

**取舍与债**：`QueuedDestination` 的代价是「进程死时队列里未写出的那几行会丢」，且 `flush()` 之后新来的日志仍可能未落盘（语义 = 「本次调用之前入队的都写出」）。默认路径不用它，所以这笔债只在需要时才付。

## 6. 验证

**已验（可自动化的部分）**：`swift test --disable-sandbox` → **43 用例 / 10 suite 全绿，连跑 3 次**。新增：

- `FileDestination`：构造后磁盘**完全无痕迹**、首次 `write` 才建目录/文件；`flush()` 在未 open 时是 no-op；`close()` 幂等且可重新 open；`.everyWrite` 旧行为可用；`.interval` 钳位与 smoke。
- `QueuedDestination`（用会记录线程与延迟的 `SpyDestination`）：顺序保持、**内层写出不发生在调用线程**（线程身份比对）、`flush()` 是屏障、`close()` 传递、并发 500 条不丢、`correlationID`/metadata 原样透传、溢出丢最旧 + 记账 + 说明行、名称/等级继承。

**验证边界（重要，不可混为一谈）**：

- 「每行 fsync 已经去掉」**无法用单元测试证明**：page cache 让「读了有内容」与「fsync 过」完全不可区分，单元测试只能证明 API 行为与队列语义。这条断言的真凭据是**真机 stall 剖面**。
- 「模拟器全绿」也**不能**作为验收：本机同一对比里 fsync 仅 25.8 µs，正是这个 bug 在 0.3/0.4 两次发版中未被发现的原因。

**未验（交给 T3，在哪跑写明）**：app 侧删掉自建异步包装、直连 `FileDestination`（或按需 `.queued()`），在**真机**重跑 stall 剖面；判据：**0 笔 >100 ms 则结案，`QueuedDestination` 保持不启用**；若仍有尖峰，启用 `.queued()` 并复测。

**怎么确认「是真好了」而不是「没触发」**：复测必须包含**同一段启动 + 同一段高频日志**（即当初产生 861–7931 ms 的那段路径），并同时看「启动到首帧」是否从 30607 ms 回到正常值。

## 7. 沉淀

**可迁移教训（两条）**：

1. **「同步」是调用约定，不是成本分配**。写进契约的应该是「多久返回 / 谁付成本 / 顺序如何」，而不是「同步」这种可被两种解读的形容词。这条已回写进 `LogDestination` 文档与 `docs/APP_INTEGRATION.md`。
2. **在修根因之前，先判断补偿层该不该存在**。用户已经包了异步 → 直觉是「搬进库」；正确动作是「修默认行为，然后删掉补偿层」。判据：**补偿层解决的问题是否由库的默认值制造**？是 → 删；否 → 才考虑内建。

**防复发措施**：① 契约文案写死成本上限（已落地）；② `FileFlushPolicy` 的默认值被测试锁住（`#expect(destination.flushPolicy == .never)`，防有人「顺手」改回 `.everyWrite`）；③ 真机性能回归门禁**尚未落地**（见未解决清单）。

---

## 修订记录

- **2026-09-18**：初稿。此时真机复测（T3）未做，`QueuedDestination` 已实现但未接入默认路径。

## 相关手记

- [tgloggerui-product](2026-09-15-tgloggerui-product.md)（当日环境教训：本机 xcodebuild 沙箱限制）；反馈来源为 app 侧性能排查（joveview）。

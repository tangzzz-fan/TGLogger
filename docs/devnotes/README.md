# 开发手记索引（devnotes）

本目录放**给人读得懂**的过程记录：结论 + 推理路径，明确**不是 ADR**。
规范与骨架见 [`~/.workbuddy/skills/dev-notes/SKILL.md`]，本文只维护索引与规则。

**职责边界**：commit 说「改了什么」｜PR 说「怎么验」｜每日日志说「做了什么」｜**手记只说「看代码看不出来的东西」**。

---

## 1. 时间倒序

| 日期 | 类型 | 一句话 | 文件 |
|------|------|--------|------|
| 2026-09-15 | 功能 | `MemoryDestination` 新增 `makeRecordsStream()` 实时流（0.2.0 第一刀），多消费者靠 `StreamBox` 身份摘除 | [memory-destination-stream](2026-09-15-memory-destination-stream.md) |
| 2026-09-15 | bug | `.gitignore` 里裸 `docs/` 在 macOS 上连 `Docs/` 一起吞，手写文档「本地存在但 git 永远不收」 | [2026-09-15-docs-gitignore-swallow.md](2026-09-15-docs-gitignore-swallow.md) |

## 2. 症状反查（出问题时人是按症状找，这张最常用）

| 我看到的信号 | 大概是什么问题 | 手记 |
|--------------|----------------|------|
| `===` 编译报错「expected to be an instance of a class」 | 被比较的类型是 struct（如 `AsyncStream.Continuation`），要包一层 class 做身份 | [memory-destination-stream](2026-09-15-memory-destination-stream.md) |
| `git status` 里看不到刚写好的 `docs/*.md`，文件明明在磁盘上 | 被 `.gitignore` 的目录级规则吞了（大小写不敏感匹配） | [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md) |
| README 里链的文档在 GitHub 上 404，本地却能打开 | 该文档从未入库（同上，同一个原因） | [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md) |
| `git check-ignore -v <path>` 有输出，但你没写过匹配它的规则 | 命中的是大小写别名（`docs/` 命中 `Docs/`） | [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md) |

## 3. 规则表（会重复的教训必须变成防护，不能只留一篇手记）

| 规则 | 来源 | 落地状态 |
|------|------|----------|
| 不要在 `.gitignore` 写裸 `docs/` 或 `Docs/`；手写文档必须入库，只忽略生成物 | [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md) | 已落地为 `.gitignore` 反例注释 |
| 新写文档后立刻 `git status --short` 确认它出现在待提交列表里 | 同上 | **CI 守卫已落地**：磁盘上有、索引里没有的 `docs/` 文件会让构建失败（`ci.yml` checkout 之后） |

## 4. 未解决清单

| 手记 | 卡在哪 | 下一步 | 复查日期 |
|------|--------|--------|----------|
| [memory-destination-stream](2026-09-15-memory-destination-stream.md) | 没有 SwiftUI 消费端，`bufferingNewest` 策略无专项测试 | 实现 `TGLoggerUI` 的 `LogConsoleStore` 时一并验收 | 0.2.0 开工时 |
| [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md) | 守卫在 CI 的首次实跑还没发生（本地已双向验证） | 看下一次 CI 运行是否绿灯 | 下次 push 后 |
| [docs-gitignore-swallow](2026-09-15-docs-gitignore-swallow.md) | 兄弟仓库 `TGFeatureFlag` 用的是同一份 `.gitignore` 模板 | 决定是否一起删掉那条 `docs/` | 下次动该仓库时 |

---

## 命名与归档

- 命名：`YYYY-MM-DD-<kebab-slug>.md`，slug 用 ASCII；同主题追加 `-2`。
- 位置：仓库内 `docs/devnotes/`；非仓库场景落 `<工作区>/.workbuddy/memory/devnotes/`。
- 深度：`BRIEF` 5–15 行 / `FULL` 60–150 行，超过 200 行拆篇。
- 写之前用 [`_TEMPLATE.md`](_TEMPLATE.md)；填好的真实范例见 [2026-09-15-docs-gitignore-swallow.md](2026-09-15-docs-gitignore-swallow.md)（本质陈述卡逐栏填满的那篇）。

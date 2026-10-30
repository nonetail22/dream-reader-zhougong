# 贡献指南 / Contributing

<p>
<b><a href="#中文">简体中文</a></b> · <b><a href="#english">English</a></b>
</p>

> **维护预期**：本项目由个人业余维护，Issue 回复与 PR 合并**没有时限承诺**——
> 可能几天，也可能几周，但不会被无视。需要确定性支持请自行 fork（AGPL 允许）。
> **Maintenance note**: maintained in spare time; no SLA for replies or merges.
> Nothing is ignored, but patience is appreciated. Forks are legitimate.

---

<a id="中文"></a>

## 中文

欢迎 Issue 与 PR。语言不限，中文 / English / 繁體中文都可以。

### 提 Issue

- 报 bug 请附：设备与系统版本、复现步骤、预期 vs 实际、（如涉及 UI）截图。
- 涉及解析质量的，请附**完整口述原文与解析输出**（可隐去隐私内容，但请保持
  JSON 结构与引号原样）。

### 提 PR 前必须通过

```bash
cd app
flutter analyze    # 零告警
flutter test       # 全量通过
```

硬红线（reviewer 会盯）：

1. **周公版契约测试不许跳过或删除断言**。`app/test/prompt_builder_test.dart` 在继承
   社区版全部工程护栏之外，另钉本版流派护栏（吉凶不定命、断语直引、有分歧才并陈、睡瘫禁按凶兆解）。
   改 `app/assets/framework_prompt.md` 必须同步跑这组测试；改动护栏句子必须同步更新
   测试钉点，并在 PR 里说明理由。
2. **典籍引用不得超出封闭清单**（Z1-Z4）。给清单加典籍属于改解析契约，需要先开
   Issue 讨论，给出版本依据（书目、通行本信息）。
3. **落盘键（SharedPreferences / 数据库字段名）不可更改**。改了会丢用户数据。
4. **不许添加任何形式的遥测/上报**。本项目零后端零埋点，这是产品承诺。

### 开发环境

- Flutter（基线 3.47.5）/ JDK 17 / Android SDK（minSdk 24）。
- 国内构建建议配置镜像源，避免网络问题误判为代码问题。
- 本仓库的 `app/assets/framework_prompt.md` 是**单真源**（与社区版不同，无 docs 副本
  与同步脚本）；上游框架 v1.1.2 的血泪注释大量保留在文档里，改动前先读一遍版本记录。

### 行为准则

保持友善与就事论事。本版用传统典籍做解析依据，欢迎考据与指正（给具体书目与条目）；
不欢迎装神弄鬼与人身攻击。

---

<a id="english"></a>

## English

Issues and PRs are welcome in 中文 / English / 繁體中文.

### Filing issues

- For bug reports, please include: device and OS version, steps to reproduce,
  expected vs actual behavior, and (for UI issues) screenshots.
- For interpretation-quality issues, please attach the **full dictated transcript and
  the interpretation output** (you may redact private content, but keep the JSON
  structure and quotation marks intact).

### Before opening a PR

```bash
cd app
flutter analyze    # zero warnings
flutter test       # full suite must pass
```

Hard lines (reviewers will enforce them):

1. **Never skip or delete assertions in the Zhou Gong edition contract tests.**
   `app/test/prompt_builder_test.dart` inherits every community-edition engineering
   guard and additionally pins this edition's school guards (no fatalism, multiple
   readings, sleep paralysis is not an omen). Any change to
   `app/assets/framework_prompt.md` must re-run this suite; changing a guard sentence
   requires updating the pinned assertion and explaining why in the PR.
2. **Classical citations must stay within the closed list (Z1–Z4).** Adding a source to
   the list changes the interpretation contract — open an issue first, with edition
   evidence (title, received-text information).
3. **Persistence keys (SharedPreferences / database field names) must never change.**
   Changing them destroys user data.
4. **No telemetry of any kind.** This project has no backend and no analytics — that is
   a product promise.

### Development environment

- Flutter (baseline 3.47.5) / JDK 17 / Android SDK (minSdk 24).
- If you build from mainland China, consider mirror settings so network issues are not
  mistaken for code issues.
- This repo's `app/assets/framework_prompt.md` is a **single source of truth**
  (unlike the community edition, there is no docs copy or sync script); many
  hard-won annotations from upstream framework v1.1.2 are preserved in the document —
  read the version history before editing.

### Code of conduct

Be kind and stay on topic. This edition grounds interpretation in classical sources:
scholarly corrections are welcome (cite the specific book and entry); mysticism-making
and personal attacks are not.

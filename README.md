# Dream Reader · 周公解梦版

**梦境记录 + 古传周公解梦 AI 解析 · 吉凶不定命，古断直引**

<p align="center">
<b><a href="#简体中文">简体中文</a></b> ·
<b><a href="#english">English</a></b>
</p>

---

<a id="简体中文"></a>

## 简体中文

### 简介

本版是 [Dream Reader 社区版](https://github.com/nonetail22/dream-reader) 的**周公解梦版**：
记录、离线识别、时间线、配色、多语言等全部功能与社区版一致，唯一的区别是**解析流派**——
由精神分析框架换成**古传周公解梦体系**（仍由 AI 完成，BYOK 配置方式不变）。

解析依据封闭典籍清单：

| # | 典籍体系 | 用途 |
|---|---|---|
| Z1 | 《周公解梦》（民间流传本） | 单梦取义主框架（按象分类的传统释义条目） |
| Z2 | 《梦林玄解》（明代类书） | 意象取义 + 分歧并陈参考（直解与反解并存） |
| Z3 | 《敦煌本梦书》等古传梦书残卷 | 旁证补充（须标注"残卷"） |
| Z4 | 传统五行时辰语境 | 仅限 C 级（权且一说）补充视角 |

每条结论标注**典籍出处**（如 `Z1-财帛类`）与置信度：
**A · 文本可见 / B · 典籍明载 / C · 权且一说**。

### 本版的流派护栏

传统解梦容易滑向的坑，本版用硬规则钉住：

- **吉凶不定命**：禁止「此梦必应」「今年必发」式定命断言与占卜承诺；吉凶表述一律
  归属典籍（如「古断：屎尿污身主得财」），不做预知宣称。
- **断语直给，有分歧才并陈**：典籍诸本一致的梦象直接按一致断语取义，并**逐字引用
  条目原文**（如「屎尿污身主得财」「厕中屎溢，大吉利」）；典籍间确有分歧（如直解
  与反解）时并列两说并说明取舍理由，不为凑「多解」硬造分歧。
- **睡瘫不是凶兆**：「鬼压床」、跑不动喊不出等是已知睡眠生理现象（快速眼动期肌张力
  抑制），明确禁止按凶兆/灵异条目解读，防止制造恐惧。
- 清单外体系（塔罗、星座、灵异学说）一律禁止引用。

**全部工程护栏与社区版完全一致**：结论必须挂在口述原文里连续、逐字、可搜索的片段上；
「无法判定」转成追问而非结论；白话结论禁术语；置信度诚实分级。JSON 输出契约与社区版
逐字相同——存储、渲染、指纹机制对流派无感知。

### 隐私

与社区版相同：录音、文字、解析结果**只存在本机**；解析文本只发往你自己配置的 API
供应商；应用无服务器、无遥测、无账号。

### 免责声明

- 所有解析结果均由 AI 依古传解梦体系生成，**仅供娱乐参考**，不构成任何预言、占卜、
  医学或心理学建议，不能替代专业心理帮助。若梦境长期困扰你，请寻求专业人士支持。
- 典籍释义是**传统文化语境下的思维工具**，不是对现实的断言；请勿依据解析结果做出
  医疗、财务或其他重大决策。

### 下载

从 [Releases](https://github.com/nonetail22/dream-reader-zhougong/releases) 下载 APK
（arm64-v8a）。当前版本 **0.7.5**（基线），包名
`com.dreamreader.dream_reader_zhougong`，应用名「周公解梦」——
与社区版（`com.dreamreader.dream_reader`）**可在同一部手机上并存安装**。

### 从源码构建

```bash
git clone https://github.com/nonetail22/dream-reader-zhougong.git
cd dream-reader-zhougong/app
flutter pub get
flutter build apk --release --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

环境要求：Flutter（基线 3.47.5）/ JDK 17 / Android SDK（minSdk 24）。

```bash
flutter analyze   # 静态检查
flutter test      # 全量测试（含周公版解析框架契约测试）
```

### 解析引擎

单一真源：[`app/assets/framework_prompt.md`](app/assets/framework_prompt.md)（vZ1.1，
自社区版框架 v1.1.2 派生）。配套契约测试
[`app/test/prompt_builder_test.dart`](app/test/prompt_builder_test.dart)
在继承社区版全部护栏钉点的基础上，另钉本版流派护栏（吉凶不定命、断语直引、
有分歧才并陈、睡瘫禁按凶兆解）。

### 与社区版的差异一览

| | [社区版](https://github.com/nonetail22/dream-reader) | 本版（周公解梦版） |
|---|---|---|
| 解析流派 | 精神分析（弗洛伊德/荣格/HVdC） | 古传周公解梦（Z1-Z4 典籍体系） |
| 置信度语义 | A 文本可见 / B 理论推演 / C 开放假设 | A 文本可见 / B 典籍明载 / C 权且一说 |
| 包名 / 应用名 | `com.dreamreader.dream_reader` / Dream Reader | `com.dreamreader.dream_reader_zhougong` / 周公解梦 |
| 其余功能 | — | 完全一致 |

### 贡献

欢迎 Issue 与 PR，见 [CONTRIBUTING.md](CONTRIBUTING.md)。特别欢迎考据型指正——
给典籍释义提意见时请附具体书目与条目。

### 维护说明

- 本项目由个人**业余时间维护**，**无法承诺 Issue 的回复时间**。遇到问题欢迎先翻
  历史 Issue，也欢迎社区互相解答。
- 标题带 `[critical]`（数据丢失 / 隐私 / 崩溃）的 Issue 会优先处理。
- PR 不会无人问津，但合并节奏可能较慢，请耐心。
- 本版是 AGPL 开源：需要确定性支持或想按自己的节奏演进，欢迎直接 fork 自行维护。

### 许可证

本项目以 [**GNU AGPL-3.0-or-later**](LICENSE) 开源。关键开源组件：
[Flutter](https://flutter.dev)、[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
（Apache-2.0）、FunASR Paraformer 模型（按需下载，遵循其自身许可证）。

---

<a id="english"></a>

## English

**Dream journaling + classical Zhou Gong AI interpretation — no fatalistic verdicts, classical verdicts quoted verbatim**

### About

This is the **Zhou Gong edition** of
[Dream Reader (community edition)](https://github.com/nonetail22/dream-reader):
recording, offline recognition, timeline, theming and i18n are all identical to the
community edition. The only difference is the **interpretation school** — swapped from
psychoanalysis to the **classical Chinese Zhou Gong dream tradition** (still AI-powered,
still BYOK).

The engine is anchored to a closed list of classical sources:

| # | Source | Role |
|---|---|---|
| Z1 | *Zhou Gong Jie Meng* (folk transmission) | Primary framework for single-dream reading (object-classified traditional entries) |
| Z2 | *Meng Lin Xuan Jie* (Ming dynasty compendium) | Imagery reading + multiple readings (direct and inverted interpretations coexist) |
| Z3 | *Dunhuang dream books* and other early fragments | Corroboration only (must be marked "fragment") |
| Z4 | Traditional five-element / hour context | Supplementary perspective, C-grade (tentative) only |

Every conclusion cites its **classical source** (e.g. `Z1-wealth`) and a confidence grade:
**A · visible in text / B · from classics / C · tentative**.

### School-specific guards

- **No fatalism**: verdicts like "this dream will surely come true" and divination promises
  are hard-banned; traditional readings are always attributed to the classical sources
  (e.g. "classical verdict: filth on the body presages wealth"), never asserted as predictions.
- **Verdicts quoted directly; alternatives only when sources disagree**: when classical
  dream books agree on an image, the reading follows the unanimous verdict with the
  original entry quoted verbatim (e.g. "filth on the body presages wealth"). When sources
  genuinely diverge (direct vs. inverted readings), both are presented with the reason for
  the choice — fabricating a second reading just to look "balanced" is a spec violation.
- **Sleep paralysis is not an omen**: "ghost pressing on the chest", inability to move or
  speak are known REM-related physiological phenomena. Interpreting them through
  ominous/supernatural entries is explicitly banned.
- Anything outside the list (tarot, astrology, occult systems) is prohibited.

**All engineering guards are identical to the community edition**: every conclusion must be
anchored to a contiguous, verbatim, searchable span of your own dictated text; "cannot
determine" becomes a follow-up question; plain-language conclusions ban jargon; confidence
is graded honestly. The JSON output contract is byte-identical to the community edition —
storage, rendering and fingerprinting are school-agnostic.

### Privacy

Same as the community edition: recordings, transcripts and interpretations **exist only on
your device**; dream text is sent only to the API provider you configured; no server, no
telemetry, no account.

### Disclaimer

- All interpretations are AI-generated from the classical Zhou Gong dream tradition,
  **for entertainment only**. They are not prophecy, divination, medical or psychological
  advice, and cannot replace professional help. If distressing dreams persist, please
  seek professional support.
- Classical readings are a **thinking tool within a cultural tradition**, not claims about
  reality — do not make medical, financial or other major decisions based on an
  interpretation.

### Download

Grab the APK (arm64-v8a) from the
[Releases](https://github.com/nonetail22/dream-reader-zhougong/releases) page.
Current baseline version: **0.7.5**. Package name
`com.dreamreader.dream_reader_zhougong`, app name 「周公解梦」 — it **installs side by
side** with the community edition (`com.dreamreader.dream_reader`).

### Building from source

```bash
git clone https://github.com/nonetail22/dream-reader-zhougong.git
cd dream-reader-zhougong/app
flutter pub get
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Requirements: Flutter (baseline 3.47.5) / JDK 17 / Android SDK (minSdk 24).

```bash
flutter analyze   # static analysis
flutter test      # full test suite, incl. Zhou Gong edition contract tests
```

### The interpretation engine

Single source of truth:
[`app/assets/framework_prompt.md`](app/assets/framework_prompt.md) (vZ1.1, derived from the
community edition's framework v1.1.2). Contract tests in
[`app/test/prompt_builder_test.dart`](app/test/prompt_builder_test.dart) inherit every
community-edition guard and additionally pin this edition's school guards (no fatalism,
multiple readings, sleep paralysis not an omen).

### Differences from the community edition

| | [Community edition](https://github.com/nonetail22/dream-reader) | This edition |
|---|---|---|
| Interpretation school | Psychoanalysis (Freud / Jung / Hall–Van de Castle) | Classical Zhou Gong tradition (Z1–Z4) |
| Confidence semantics | A visible / B theoretical / C open hypothesis | A visible / B from classics / C tentative |
| Package / app name | `com.dreamreader.dream_reader` / Dream Reader | `com.dreamreader.dream_reader_zhougong` / 周公解梦 |
| Everything else | — | Identical |

### Contributing

Issues and PRs are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Scholarly
corrections are especially appreciated; when commenting on a classical reading, please
cite the specific book and entry.

### Maintenance expectations

- This project is maintained **in spare time by one person**. There is **no SLA for
  issue replies**. Please check existing issues first; community answers are welcome.
- Issues titled with `[critical]` (data loss / privacy / crashes) are prioritized.
- PRs will never be ignored, but merging can be slow — please be patient.
- This is an AGPL project: forking and maintaining your own branch is a perfectly
  legitimate option if you need guaranteed support.

### License

Released under the [**GNU AGPL-3.0-or-later**](LICENSE). Key open-source components:
[Flutter](https://flutter.dev),
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache-2.0),
FunASR Paraformer models (downloaded on demand; subject to their own licenses).

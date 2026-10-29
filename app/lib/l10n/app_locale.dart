// Dream Reader · 周公解梦版 — 梦境记录与古传周公解梦 AI 解析
// Dream Reader · Zhou Gong edition — dream journaling with classical Chinese dream interpretation
//
// 版权所有 (C) 2026 wild nicolas
// Copyright (C) 2026 wild nicolas
//
// 本程序为自由软件：你可根据自由软件基金会发布的 GNU Affero 通用公共许可证
// （第 3 版，或你选择的任何更高版本）重新分发或修改它。
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// 本程序按「现状」分发，不附带任何担保；不含适销性或特定用途适用性的默示担保。
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// Affero General Public License for more details.
//
// 你应当已随本程序收到一份 GNU Affero 通用公共许可证的副本；如果没有，
// 请访问 <https://www.gnu.org/licenses/>。
// You should have received a copy of the GNU Affero General Public
// License along with this program. If not, see
// <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// 应用支持的界面语言。
///
/// 三套：简体中文 / 繁體中文 / English。这是**落盘键**（persistence id），
/// 改枚举名会丢用户已选语言，所以命名要保持稳定。
///
/// ★ 本文件**刻意不 import 任何 Flutter 包**（连 `dart:ui` 也不引）：
/// 这样它、以及依赖它的 `messages.dart`，都能被纯 Dart 的 `dart test` 直接跑到
/// （沙箱里没有 flutter_tester）。与 `Locale` 互转的那部分（`flutterLocale` /
/// `fromFlutter`）放在 Flutter 侧的 `app_localizations.dart` 里。
library app_locale;

enum AppLocale {
  zhCN,
  zhTW,
  en,
}

extension AppLocaleX on AppLocale {
  /// 落盘用的稳定 id（== 枚举名，不会变）。
  String get id => name;

  /// 选择器里显示给用户的语言名。
  String get label {
    switch (this) {
      case AppLocale.zhCN:
        return '简体中文';
      case AppLocale.zhTW:
        return '繁體中文';
      case AppLocale.en:
        return 'English';
    }
  }

  /// 给「解析内容跟随界面语言」用的输出语言指令；**追加在 user prompt 的最末尾**
  /// （位置由 `PromptBuilder.buildUserPrompt` 保证，见那里的实测表格）。
  ///
  /// 返回 null 表示**不需要加指令**：简体中文是框架文档的默认语言，加一句
  /// "请使用简体中文回答"纯属冗余；更关键的是——它会改变 prompt，从而让所有历史记录的
  /// `analyzedFingerprint` 都变成"输入变了"，用户点重解析会被误报。所以 zhCN 回落 null。
  ///
  /// ★ 措辞是**实测出来的**，不是写得越客气越好（2026-09-24，`validation/preview/
  /// check_language_directive.mjs`，deepseek-v4-pro、同一场景、只改措辞与位置）：
  ///
  /// | 措辞 | 位置 | 结果（要求英文） |
  /// |---|---|---|
  /// | `Please respond entirely in English.`（短） | system 末尾 | 拉丁 0 / 汉字 283 → 完全无视 |
  /// | 同上一句 | **user 末尾** | 拉丁 77 / 汉字 200 → **只换了 headline，point 还是中文** |
  /// | 「最高优先级…所有字段一律只使用…」 | **user 末尾** | **拉丁 679 / 汉字 0 → 全部字段生效** |
  ///
  /// 所以有两个必要条件，缺一不可：**位置在 user 末尾**，且**措辞要把"所有字段"写明**。
  /// 只满足位置时会出现"headline 英文、正文中文"这种**半生效**状态——比完全失败更阴险，
  /// 因为界面上看起来像是成功了。
  ///
  /// ★ 但"所有字段"这四个字**本身也有代价**（2026-09-24 第二轮实测才发现）：
  /// 它把 `evidence` / `imagery[].token` / `emotions_explicit[]` 这些**引用原文**的字段
  /// 也一并翻了过去。要求英文时模型只是"语言不通"、这几项反而老老实实留了中文；
  /// **要求繁體時最危险**——原文是简体，模型把引用**顺手转成了繁体**，
  /// 于是 `evidence` 不再逐字、用户拿回原文里**搜不到**（本产品的立身之本），
  /// `imagery[].token` 同样被转形，而 `emotions_explicit` 干脆被清空成 `[]`。
  /// 这类失败**不报错、界面完全正常**（`check_guardrails.py` 原先只查 evidence，
  /// 所以 imagery 那一处是**空过**的）。
  /// 所以指令现在必须**显式列出豁免字段**：论述性字段跟随界面语言，
  /// 引用型字段**逐字保留原文原样**（连简繁与标点都不许动）。
  /// 这条豁免与框架第 12 条「禁止伪造或拼接原文引用」同源——
  /// 框架里早已写明「不许改用全角引号绕过，换了字符就搜不到了」，
  /// 是这条新指令把它盖掉了。措辞改动后**必须重跑**
  /// `check_language_directive.mjs` 与 `check_guardrails.py` 复核。
  ///
  /// 能力边界：还取决于模型。glm-5.3 在 system 位置、用短措辞就已服从；
  /// deepseek-v4-pro 需要"user 末尾 + 强措辞"两个条件同时满足。所以界面文案不应把
  /// "解析跟随界面语言"写成对**所有模型**的无条件保证。
  String? get analysisLanguageDirective {
    switch (this) {
      case AppLocale.zhCN:
        return null;
      case AppLocale.zhTW:
        return '【輸出語言｜最高優先級】無論上面的口述原文用的是什麼語言，'
            '本次回答的**論述性欄位一律只使用繁體中文（臺灣用字）**'
            '（包括所有解讀、說明、建議、提問與術語解釋）。'
            '★ 唯一例外：**引用原文的欄位必須逐字保留原文原樣**——'
            '`evidence`、`imagery[].token`、`emotions_explicit[]` 這幾個欄位'
            '要讓使用者能拿回原文裡搜到，**連簡繁、標點與字元都不許改**'
            '（原文是簡體就保持簡體，不要轉成繁體）。';
      case AppLocale.en:
        return '【输出语言｜最高优先级】无论上面的口述原文用的是什么语言，'
            '本次回答的**论述性字段一律只使用 English（美式英语）**'
            '（包括所有解读、说明、建议、提问与术语解释）。'
            '★ 唯一例外：**引用原文的字段必须逐字保留原文原样**——'
            '`evidence`、`imagery[].token`、`emotions_explicit[]` 这几个字段'
            '要让使用者能拿回原文里搜到，**连简繁、标点与字符都不许改**'
            '（原文是简体就保持简体）。';
    }
  }

  /// 从落盘 id 还原；未知值回落简体中文，绝不抛异常（落盘键错了也不该让界面崩）。
  static AppLocale fromId(String? id) =>
      AppLocale.values.firstWhere((e) => e.name == id, orElse: () => AppLocale.zhCN);
}

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

import 'dream_tags.dart';

/// Prompt 装配器的**纯逻辑**部分：不依赖 Flutter（不 import package:flutter/*），
/// 因此可以在纯 Dart VM 上直接用 `dart test` 验证契约，无需 flutter_tester / 浏览器。
///
/// 单一真源原则：输入是「框架文档」全文（assets/framework_prompt.md，由
/// tools/sync_prompt.mjs 从 docs/解析理论框架_Prompt_v1.md 生成），此处只做提取与
/// 拼接，不做任何内容改写。
class PromptBuilder {
  /// 框架文档在资源包中的路径（pubspec.yaml 的 assets 必须声明它）
  static const assetPath = 'assets/framework_prompt.md';

  final String frameworkDoc;
  PromptBuilder(this.frameworkDoc);

  /// 第三节的 System Prompt 正文（```text 块，以「你是一名基于精神分析…」开头）
  String get systemPromptBody {
    final m = RegExp(r'```text\n([\s\S]*?)```').firstMatch(frameworkDoc);
    if (m == null) {
      throw StateError('无法从框架文档提取 System Prompt（```text 块缺失）');
    }
    return m.group(1)!.trim();
  }

  /// 第四节的 JSON Schema（```json 块）
  String get jsonSchema {
    final sectionIdx = frameworkDoc.indexOf('## 四、输出结构');
    if (sectionIdx < 0) throw StateError('无法定位框架文档第四节');
    final m = RegExp(r'```json\n([\s\S]*?)```')
        .firstMatch(frameworkDoc.substring(sectionIdx));
    if (m == null) throw StateError('无法从框架文档提取 JSON Schema（```json 块缺失）');
    return m.group(1)!.trim();
  }

  /// 生产形态 system message = System Prompt 全文 + Schema 原文
  /// （第五部分「输出格式」已含在 System Prompt 正文内）
  ///
  /// ★ **不要把「输出语言」指令加到这条上**——它在这里会被忽略，见 [buildUserPrompt]
  /// 里 `languageDirective` 的说明（这是 2026-09-24 真机外实测的结论，不是推测）。
  String buildSystemPrompt() {
    return '$systemPromptBody\n\n$jsonSchema';
  }

  /// User Prompt 模板（与框架文档一致，变量由 App 注入）
  ///
  /// v1.1.0 起「近期状态」这一栏同时承载**上次解析所提问题的回答**（`open_questions`
  /// 的答案由用户写进 `recentContext`），所以标签里必须把这件事说明白——
  /// 否则模型会把它当成一段与提问无关的背景资料，白拿一份材料不用。
  /// 另：这一栏的内容全部参与解析输入指纹，改写它会正确地让重解析被判定为"输入变了"。
  ///
  /// v1.1.3 起多一段**结构化的「本次记录的标签」**（由 [DreamTags.promptLine] 生成）。
  /// ★ 关键性质：**没有标签时它一个字都不输出**，于是整份 user prompt 与加标签之前
  /// **逐字节相同**。这不是顺手，是必须——已经落盘的 `analyzedFingerprint` 是按旧形态
  /// 算的，只要空标签会多出一个换行，所有历史记录都会在用户点「重新解析」时被误报成
  /// "输入变了"，而那正是 0.3.5 修掉的那个谎。有单测钉住这一条。
  /// ★ v1.1.4 起多一段**可选的「输出语言」指令**，追加在**整条消息的最末尾**（口述原文之后）。
  ///
  /// 为什么必须放这里、而不是 system prompt（2026-09-24 实测，`validation/preview/
  /// check_language_directive.mjs`，同一模型同一场景，**只改位置不改措辞**）：
  ///
  /// | 位置 | 措辞 | 结果（要求英文时） |
  /// |---|---|---|
  /// | system prompt 末尾 | `Please respond entirely in English.` | 拉丁 0 / 汉字 251 → **被忽略** |
  /// | system prompt 末尾 | 写明「此条优先于第 6 条」 | 拉丁 0 / 汉字 228 → **仍被忽略** |
  /// | **用户消息末尾** | 同一句（中文版） | **拉丁 679 / 汉字 0 → 生效** |
  ///
  /// 根因：框架第 6 条「输出语言与用户语言一致」**本身是歧义的**——模型把它读成
  /// 「跟随口述原文的语言」（原文是中文，于是它认为自己已经在遵守），再加上 8.8K 字符的
  /// 中文框架 + 中文原文都在 system prompt 里，末尾一句追加根本压不过去。
  /// → 结论：**这不是强度问题，是位置问题。** 改回 system prompt 会静默失效；
  ///   而"静默"二字是关键——护栏脚本拿英文词表去查中文文本会**空过**，测试全绿。
  ///
  /// 能力边界（同批实测）：**指令生效与否还取决于模型**。glm-5.3 在 system 位置就已服从；
  /// deepseek-v4-pro 只在用户消息位置才服从。所以"解析内容跟随界面语言"是**模型相关**的
  /// 承诺，界面文案不应把它写成无条件保证。
  ///
  /// 没有 directive 时**一个字符都不输出**（与 [tags] 同理）：保证 zhCN 的 user prompt 与
  /// 加此功能之前**逐字节相同**——否则所有已落盘记录的 `analyzedFingerprint` 都会在用户点
  /// 「重新解析」时被误报成"输入变了"。有单测钉住这一条。
  String buildUserPrompt({
    required String date,
    required String wakeTime,
    required String recentContext,
    required String dreamHistoryDigest,
    required String transcript,
    String? mood,
    List<String> flags = const [],
    String? languageDirective,
  }) {
    final ctx = recentContext.trim().isEmpty ? '（未填写）' : recentContext.trim();
    final history =
        dreamHistoryDigest.trim().isEmpty ? '（无）' : dreamHistoryDigest.trim();
    final tags = DreamTags.promptLine(mood: mood, flags: flags);
    final lang = (languageDirective == null || languageDirective.trim().isEmpty)
        ? ''
        : '\n\n$languageDirective';
    return '【日期】$date　【醒来时间】$wakeTime（推测 REM 窗口，仅供备注）\n'
        '【近期状态与补充说明（用户可选填写；也可能是对上次解析所提问题的回答）】$ctx\n'
        '【历史梦境摘要（系统自动附最近 14 天，无则省略）】$history\n'
        // 紧挨着原文放：它是"这条记录自己的事实"，与它描述的内容物理相邻，
        // 模型读到原文之前刚看过它。没标签时这一段整个不出现。
        '${tags.isEmpty ? '' : '$tags\n'}'
        '【梦境口述原文】\n$transcript'
        // ★ 语言指令必须在**最末尾**：它是模型生成前读到的最后一句。
        '$lang';
  }

  /// 模型首次输出不是合法 JSON 时的追加指令（配合 JsonRepair 使用）
  static const jsonRetryInstruction =
      '你上一次的输出不是合法 JSON，无法解析。请重新输出：只输出一个合法的 JSON 对象，'
      '不得包含任何解释文字、注释或 markdown 代码围栏。字符串内部不得出现未转义的换行符，'
      '字符串必须用双引号闭合。'
      // 这条来自第四轮多轮闭环实测：用户在「补充说明」里打了半角双引号（极常见），
      // 模型"引用用户原话"时把它原样搬进 JSON 值 → 整份输出不可解析。见 README 规则 48。
      '**如果你要在字符串里引用用户的原文、而那段原文本身带半角双引号，必须把它们写成 \\" 转义**'
      '（不要改成全角引号——evidence 要求逐字复制原文，换了字符就搜不到了）。';
}

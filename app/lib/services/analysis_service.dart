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

import '../models/dream_entry.dart';
import 'fingerprint.dart';
import 'json_repair.dart';
import 'llm_client.dart';

// 刻意 import **纯逻辑**的 prompt_core，而不是带 Flutter 依赖的那层壳 prompt_builder：
// 本层只需要 PromptBuilder 这个纯类，但它要能被 `dart test` 直接跑到
// （沙箱里没有 flutter_tester）。这一点很要紧——下面"解析真的把温度传下去了"
// 和"界面算的指纹与解析内部算的完全一致"两条契约，都只有在纯 Dart 下才验得了。
import 'prompt_core.dart';

/// 一次解析**是"怎么"失败的**。它决定要不要重试、以及重试时要不要改 prompt。
///
/// 为什么值得单独列出来（2026-09-22 实测）：重试机制原本是给"模型手滑交了坏 JSON"
/// 设计的，但代码里写成了"只要第一次不 ok 就再试一次、并附上『只输出 JSON』的指令"。
/// 于是**超时也会被重试**——推理型模型的等待上限是 15 分钟，等于把最坏等待从
/// 15 分钟翻成 **30 分钟**，而同一模型再等一轮几乎必然还是超时；
/// 反过来"连接被掐断"这类**快失败**（实测 94 秒断）重试是**有实测价值的**。
/// 三类失败的性价比差着量级，用一个 `if (!ok)` 兜住必然有一边是错的。
enum AnalysisFailure {
  /// 正文拿到了，但不是能用的 JSON（`JsonRepair` 也救不回来）
  unparsableJson,
  timeout,
  transport,
  rateLimited,
  server,
  /// 4xx（除 429）：Key / 模型名 / 参数被拒
  clientError,
  unknown,
}

/// 一次解析的结果（含工程观测字段：修复动作、是否重试、原始输出、输入指纹）
class AnalysisOutcome {
  final Map<String, dynamic>? analysis;
  final String? error;
  final String rawOutput;
  final List<String> repairFixes;
  final bool retried;

  /// 失败的性质（成功时为 null）。见 [AnalysisFailure]。
  final AnalysisFailure? failure;

  /// 本次解析输入的指纹（见 [AnalysisService.fingerprintFor]）。
  /// 成功时由调用方随结论一起落盘，用于判断"下次重解析是不是白花钱"。
  final String? fingerprint;

  const AnalysisOutcome({
    this.analysis,
    this.error,
    this.rawOutput = '',
    this.repairFixes = const [],
    this.retried = false,
    this.failure,
    this.fingerprint,
  });

  bool get ok => analysis != null;
}

/// 重试策略的判据（纯数据，便于单测直接钉住）。
class RetryDecision {
  final bool retry;

  /// 重试时是否附上「必须只输出 JSON」的指令。
  final bool withJsonInstruction;

  /// 不重试时，给用户的一句原因。**必须写进最终错误里**——
  /// 用户看到"没有重试"却不知道为什么，只会觉得程序在偷懒。
  final String? noRetryWhy;

  const RetryDecision({required this.retry, this.withJsonInstruction = false, this.noRetryWhy});
}

/// 解析引擎装配层：PromptBuilder（框架装配） + LlmClient（BYOK 调用） + JsonRepair（修复/重试）
///
/// 该层不决定「解析内容是什么」——内容完全由框架文档约束；本层的职责是**保证契约被满足**：
/// 1) system message 必须包含输出格式要求与 Schema（第 0 步验证：缺契约会退化为散文）；
/// 2) 输出必须是合法 JSON，否则修复，再否则**按失败类型**决定怎么重试（见 [retryPlanFor]）；
/// 3) **同一份输入应得到同一份结论**：温度固定（默认 0），并给出输入指纹供界面判断
///    一次重解析是否只是重复花钱。
class AnalysisService {
  final LlmClient llm;
  final PromptBuilder promptBuilder;
  final Map<String, dynamic> Function()? clock; // 可注入时钟，便于测试

  /// 采样温度。默认 0——解析结论要能对着原文核对，不能每次换一套说法。
  /// 留成可注入字段是为了将来"换个角度再解读一遍"这类**显式要求多样性**的功能
  /// 可以单独传一个高温度，而不是把默认行为改回随机。
  final double temperature;

  AnalysisService({
    required this.llm,
    required this.promptBuilder,
    this.clock,
    this.temperature = 0,
  });

  Future<AnalysisOutcome> analyze({
    required LlmConfig config,
    required DreamEntry entry,
    String dreamHistoryDigest = '',
    String? languageDirective,
  }) async {
    // ★ 语言指令进的是 **user prompt 的末尾**，不是 system prompt——位置决定它生不生效，
    //   见 PromptBuilder.buildUserPrompt 的实测表格。放错位置会**静默失效**（护栏还全绿）。
    final system = promptBuilder.buildSystemPrompt();
    final user = _userPrompt(entry, dreamHistoryDigest, languageDirective: languageDirective);
    final fingerprint =
        fingerprintFor(config: config, entry: entry, dreamHistoryDigest: dreamHistoryDigest);

    // 第一次调用
    var outcome = await _callAndParse(config, system, user,
        attempt: 1, appendInstruction: false);
    if (outcome.ok) {
      return AnalysisOutcome(
        analysis: outcome.analysis,
        error: outcome.error,
        rawOutput: outcome.rawOutput,
        repairFixes: outcome.repairFixes,
        fingerprint: fingerprint,
      );
    }

    // ★ 第二次调用**不是无条件发生的**——先看第一次是怎么失败的（见 retryPlanFor）。
    final plan = retryPlanFor(outcome.failure);
    if (!plan.retry) {
      return AnalysisOutcome(
        analysis: null,
        error: '${outcome.error}（${plan.noRetryWhy}）',
        rawOutput: outcome.rawOutput,
        repairFixes: outcome.repairFixes,
        failure: outcome.failure,
        fingerprint: fingerprint,
      );
    }

    final retry = await _callAndParse(config, system, user,
        attempt: 2, appendInstruction: plan.withJsonInstruction);
    if (retry.ok) {
      return AnalysisOutcome(
        analysis: retry.analysis,
        error: outcome.error,
        rawOutput: retry.rawOutput,
        repairFixes: [...outcome.repairFixes, ...retry.repairFixes],
        retried: true,
        fingerprint: fingerprint,
      );
    }
    return AnalysisOutcome(
      analysis: null,
      error: '解析失败（已重试一次）：${retry.error ?? outcome.error}',
      rawOutput: retry.rawOutput,
      repairFixes: [...outcome.repairFixes, ...retry.repairFixes],
      retried: true,
      failure: retry.failure ?? outcome.failure,
      fingerprint: fingerprint,
    );
  }

  /// 第一次失败之后：要不要再试一次？重试时要不要改 prompt？
  ///
  /// 四类失败的性价比**差着量级**，所以这里逐个判，不用一个 `if` 兜住：
  ///
  /// | 失败 | 重试？ | 带「只输出 JSON」指令？ | 为什么 |
  /// |---|---|---|---|
  /// | 拿到正文但不是 JSON | ✅ | ✅ | 这正是重试机制最初要解决的事（模型手滑），指令对症 |
  /// | 连接被掐断 / 429 / 5xx | ✅ | ❌ | 请求根本没走到模型，"叮嘱它只输出 JSON"毫无作用；而这类是**快失败**（实测 94 秒断，对比 15 分钟预算），重试便宜且实测有用 |
  /// | 超时 | ❌ | — | 同一模型再等一轮几乎必然还是超时；重试等于把最坏等待从 15 分钟翻到 **30 分钟** |
  /// | 4xx（Key/模型名/参数） | ❌ | — | 请求本身有问题，原样重发不可能成功 |
  /// | 认不出来的 | ❌ | — | 不知道原因就别赌，把原文交给用户 |
  static RetryDecision retryPlanFor(AnalysisFailure? failure) {
    switch (failure) {
      case AnalysisFailure.unparsableJson:
        return const RetryDecision(retry: true, withJsonInstruction: true);
      case AnalysisFailure.transport:
      case AnalysisFailure.rateLimited:
      case AnalysisFailure.server:
        return const RetryDecision(retry: true, withJsonInstruction: false);
      case AnalysisFailure.timeout:
        return const RetryDecision(
          retry: false,
          noRetryWhy: '没有再自动重试：同一个模型再等一轮几乎必然还是超时，换一个更快的模型更省时间',
        );
      case AnalysisFailure.clientError:
        return const RetryDecision(
          retry: false,
          noRetryWhy: '没有再自动重试：这次是请求或配置本身被服务端拒了（Key / 模型名 / 参数），原样重发不会成功',
        );
      case AnalysisFailure.unknown:
      case null:
        return const RetryDecision(
          retry: false,
          noRetryWhy: '没有再自动重试：没认出这次失败的原因，重发同样的请求多半也一样',
        );
    }
  }

  static AnalysisFailure _fromLlm(LlmFailure k) => switch (k) {
        LlmFailure.timeout => AnalysisFailure.timeout,
        LlmFailure.transport => AnalysisFailure.transport,
        LlmFailure.rateLimited => AnalysisFailure.rateLimited,
        LlmFailure.server => AnalysisFailure.server,
        LlmFailure.clientError => AnalysisFailure.clientError,
        LlmFailure.unknown => AnalysisFailure.unknown,
      };

  /// 这次解析会用到的那份输入，指纹是多少。
  ///
  /// 界面在用户点「重新解析」时要用同一口径再算一次，与记录里存下的
  /// `analyzedFingerprint` 比对。**必须是同一个函数**——两边各拼一次 prompt
  /// 一旦有细微差别（比如漏了近期摘要），界面就会永远认为"输入变了"。
  ///
  /// 覆盖的范围：system prompt（含框架文档 + JSON Schema）、user prompt
  /// （原文 + 近期状态 + **结构化标签** + 日期时间 + 近期梦境摘要）、模型名。
  /// 没覆盖的只有采样参数本身——那正是温度已经钉死的东西。
  String fingerprintFor({
    required LlmConfig config,
    required DreamEntry entry,
    String dreamHistoryDigest = '',
    String? languageDirective,
  }) =>
      joinFingerprint([
        promptBuilder.buildSystemPrompt(),
        // 语言指令进 user prompt → 自动进指纹：切换界面语言确实会改变"解析输入"，
        // 于是旧结论会被正确判定为"输入变了"（而不是拿中文结论配英文界面）。
        _userPrompt(entry, dreamHistoryDigest, languageDirective: languageDirective),
        config.model,
      ]);

  String _userPrompt(
    DreamEntry entry,
    String dreamHistoryDigest, {
    String? languageDirective,
  }) =>
      promptBuilder.buildUserPrompt(
        date: _date(entry.recordedAt),
        wakeTime: _hm(entry.recordedAt),
        recentContext: entry.recentContext,
        dreamHistoryDigest: dreamHistoryDigest,
        transcript: entry.transcript,
        // 标签进 user prompt → 自动进 [fingerprintFor]（它哈希的就是这一整份 prompt）。
        // 所以用户改了标签，点重解析会被正确判定为"输入变了"，不会被 0.3.5 那道
        // 「输入没变」的闸门拦下来；反过来，没打标签的记录指纹与旧版完全一致
        // （空标签一个字都不输出，见 buildUserPrompt 的说明）。
        mood: entry.mood,
        flags: entry.flags,
        // 同理：zhCN 传 null → 一个字符都不加 → 与加此功能之前逐字节相同。
        languageDirective: languageDirective,
      );

  Future<AnalysisOutcome> _callAndParse(
    LlmConfig config,
    String system,
    String user, {
    required int attempt,
    required bool appendInstruction,
  }) async {
    try {
      final raw = await llm.complete(
        config: config,
        systemPrompt: system,
        userPrompt:
            appendInstruction ? '$user\n\n${PromptBuilder.jsonRetryInstruction}' : user,
        temperature: temperature,
      );
      final (obj, fixes) = JsonRepair.parseLoose(raw);
      if (obj == null) {
        return AnalysisOutcome(
          error: '第 $attempt 次输出无法解析为 JSON',
          rawOutput: raw,
          repairFixes: fixes,
          failure: AnalysisFailure.unparsableJson,
        );
      }
      return AnalysisOutcome(analysis: obj, rawOutput: raw, repairFixes: fixes);
    } on LlmException catch (e) {
      // 用 e.toString()：超时/传输类的 message 本身就是人话（statusCode 为 null，不加前缀），
      // 而状态类错误会带上 "HTTP 401: " —— 那串数字不是给用户看的，但排障时有用，留着。
      return AnalysisOutcome(error: e.toString(), failure: _fromLlm(e.kind));
    } catch (e) {
      // 走到这里的异常**我们已经不认识**了（LlmClient 认得出来的都会包成 LlmException）。
      // 不猜原因，原样带上：给一个错的原因比给一句难懂的话更害人。
      return AnalysisOutcome(error: '调用异常：$e', failure: AnalysisFailure.unknown);
    }
  }

  static String _date(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

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

import 'dart:convert';
import 'dart:io';

import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// **重试策略**的契约。
///
/// 背景（2026-09-22 上真机前的诊断）：重试机制原本是给"模型手滑交了坏 JSON"设计的，
/// 但实现写成了"只要第一次不 ok，就再试一次、并附上『只输出 JSON』的指令"。
/// 三类失败的性价比其实差着量级，用一个 `if` 兜住必然有一边是错的：
///
/// - **超时**（推理型模型的上限是 15 分钟）被无条件重试 ⇒ 最坏等待从 15 分钟**翻到 30 分钟**，
///   而同一模型再等一轮几乎必然还是超时。这是"用户刚醒过来在等结果"场景里最坏的一种失败。
/// - **连接被掐断**（真实发生过，实测 94 秒断）本该重试，而且**不该**带那条 JSON 指令
///   ——请求根本没走到模型，叮嘱它"只输出 JSON"毫无作用。
/// - **坏 JSON** 才真正需要那条指令。
///
/// 纯 Dart（analysis_service 刻意 import 纯逻辑的 prompt_core），`dart test` 可直接跑。
void main() {
  late PromptBuilder builder;
  late String frameworkDoc;

  setUpAll(() {
    frameworkDoc = File(PromptBuilder.assetPath).readAsStringSync();
    builder = PromptBuilder(frameworkDoc);
  });

  const cfg = LlmConfig(
    baseUrl: 'https://api.example.com/v1',
    apiKey: 'sk-test',
    model: 'test-model',
  );

  DreamEntry entry() => DreamEntry(
        id: '20260922-0640',
        recordedAt: DateTime(2026, 9, 22, 6, 40),
        transcript: '我梦见在一条很长的走廊里跑，后面有人跟着。',
      );

  /// 一次成功响应：200 + choices[0].message.content = [content]
  http.Response ok(String content) => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content}
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  /// 模型交了一段"看起来在说话、但不是 JSON"的正文（真实里最常见的那种手滑）
  http.Response notJson() => ok('好的，我来解析这个梦：\n\n1. 主要意象是老房子…');

  const goodJson = '{"analysis_layer":[],"advice_layer":[],"limitations_note":"x"}';

  /// 假服务端：按 [script] 逐个返回；`script` 用完后一直重复最后一项。
  /// 每一项要么是 [http.Response]（返回它），要么是异常（抛它）。
  ({AnalysisService service, List<String> bodies}) harness(
    List<Object> script, {
    Duration? timeout,
  }) {
    final bodies = <String>[];
    var i = 0;
    final llm = LlmClient(
      timeout: timeout,
      httpClient: MockClient((req) async {
        bodies.add(req.body);
        final step = script[i < script.length ? i : script.length - 1];
        i++;
        if (step is Exception) throw step;
        return step as http.Response;
      }),
    );
    return (
      service: AnalysisService(llm: llm, promptBuilder: builder),
      bodies: bodies,
    );
  }

  /// 重试时是否附带了那条 JSON 指令（用指令里独有的开头判定，避免误命中别的文案）
  bool carriesJsonInstruction(String body) =>
      body.contains('你上一次的输出不是合法 JSON');

  group('坏 JSON：带指令重试（重试机制最初要解决的就是这件事）', () {
    test('第一次坏 → 重试，且**重试那次**才带 JSON 指令', () async {
      final h = harness([notJson(), notJson()]);
      final out = await h.service.analyze(config: cfg, entry: entry());

      expect(h.bodies, hasLength(2), reason: '坏 JSON 应当重试一次');
      expect(carriesJsonInstruction(h.bodies[0]), isFalse,
          reason: '第一次是正常调用，不该预先塞重试指令');
      expect(carriesJsonInstruction(h.bodies[1]), isTrue,
          reason: '重试必须附上「只输出合法 JSON」的指令，否则这一趟白花');
      expect(out.ok, isFalse);
      expect(out.retried, isTrue);
      expect(out.error, contains('已重试一次'));
      expect(out.failure, AnalysisFailure.unparsableJson);
    });

    test('重试成功 → 结论可用，且 retried 明确记下"这份结论是第二次才成的"', () async {
      final h = harness([notJson(), ok(goodJson)]);
      final out = await h.service.analyze(config: cfg, entry: entry());

      expect(h.bodies, hasLength(2));
      expect(out.ok, isTrue);
      expect(out.retried, isTrue);
      expect(out.failure, isNull);
    });
  });

  group('连接被掐断：重试，但**不带**那条指令', () {
    test('传输类失败 → 重试一次，请求体里没有 JSON 指令', () async {
      final h = harness([
        http.ClientException('Connection closed while receiving data', Uri.parse('https://api.example.com/v1/chat/completions')),
        http.ClientException('Connection closed while receiving data', Uri.parse('https://api.example.com/v1/chat/completions')),
      ]);
      final out = await h.service.analyze(config: cfg, entry: entry());

      expect(h.bodies, hasLength(2), reason: '传输类快失败值得再试一次（实测第三次就成功了）');
      expect(carriesJsonInstruction(h.bodies[1]), isFalse,
          reason: '请求根本没走到模型，叮嘱它"只输出 JSON"毫无作用，只会让请求体变长');
      expect(out.ok, isFalse);
      expect(out.retried, isTrue);
      expect(out.error, contains('连接被中断'));
      expect(out.failure, AnalysisFailure.transport);
    });

    test('429 / 5xx 也走"重试但不带指令"这一支', () async {
      for (final code in [429, 500, 503]) {
        final h = harness([http.Response('{"error":"busy"}', code)]);
        final out = await h.service.analyze(config: cfg, entry: entry());

        expect(h.bodies, hasLength(2), reason: 'HTTP $code 应当重试');
        expect(carriesJsonInstruction(h.bodies[1]), isFalse, reason: 'HTTP $code');
        expect(out.retried, isTrue, reason: 'HTTP $code');
      }
    });
  });

  group('不该重试的那几类：一次就够，且必须告诉用户"为什么不再试"', () {
    test('超时 → **只调用一次**（重试等于把最坏等待从 15 分钟翻到 30 分钟）', () async {
      // 假服务端故意慢：40ms 的等待上限 vs 400ms 的响应
      final bodies = <String>[];
      final llm = LlmClient(
        timeout: const Duration(milliseconds: 40),
        httpClient: MockClient((req) async {
          bodies.add(req.body);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return ok(goodJson);
        }),
      );
      final service = AnalysisService(llm: llm, promptBuilder: builder);

      final out = await service.analyze(config: cfg, entry: entry());

      expect(bodies, hasLength(1), reason: '超时**不许**重试——同一模型再等一轮几乎必然还是超时');
      expect(out.retried, isFalse);
      expect(out.failure, AnalysisFailure.timeout);
      // "没有重试"这件事必须解释，否则用户只会觉得程序偷懒
      expect(out.error, contains('没有再自动重试'));
      expect(out.error, contains('换一个更快的模型'));
      expect(out.error, contains('已放弃'));
    });

    test('4xx（Key / 模型名 / 参数） → 只调用一次', () async {
      final h = harness([http.Response('{"error":"invalid api key"}', 401)]);
      final out = await h.service.analyze(config: cfg, entry: entry());

      expect(h.bodies, hasLength(1), reason: '请求本身有问题，原样重发不可能成功');
      expect(out.retried, isFalse);
      expect(out.failure, AnalysisFailure.clientError);
      expect(out.error, contains('没有再自动重试'));
      expect(out.error, contains('Key'));
      // 状态码要留着——排障时有用，而且它不会把用户搞糊涂
      expect(out.error, contains('401'));
    });
  });

  group('retryPlanFor：策略表本身（纯函数，逐个钉死）', () {
    test('坏 JSON → 重试 + 带指令', () {
      final d = AnalysisService.retryPlanFor(AnalysisFailure.unparsableJson);
      expect(d.retry, isTrue);
      expect(d.withJsonInstruction, isTrue);
    });

    test('传输 / 429 / 5xx → 重试，不带指令', () {
      for (final f in [
        AnalysisFailure.transport,
        AnalysisFailure.rateLimited,
        AnalysisFailure.server,
      ]) {
        final d = AnalysisService.retryPlanFor(f);
        expect(d.retry, isTrue, reason: '$f');
        expect(d.withJsonInstruction, isFalse, reason: '$f');
      }
    });

    test('超时 / 4xx / 认不出来 → 不重试，且每条都带"为什么不重试"', () {
      for (final f in [
        AnalysisFailure.timeout,
        AnalysisFailure.clientError,
        AnalysisFailure.unknown,
        null,
      ]) {
        final d = AnalysisService.retryPlanFor(f);
        expect(d.retry, isFalse, reason: '$f');
        expect((d.noRetryWhy ?? '').isNotEmpty, isTrue,
            reason: '$f：用户看到"没有重试"却不知道原因，只会觉得程序在偷懒');
      }
    });
  });
}

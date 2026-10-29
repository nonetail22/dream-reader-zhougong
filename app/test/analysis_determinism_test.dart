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

import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 解析服务的契约：**同一份输入得到同一份结论**，且"输入是否变过"判得准。
///
/// 背景（真实故障）：点详情页右上角的刷新，同一条梦的结论换了一套说法。
/// 两层原因——请求体没带温度（每次随机采样），以及重解析直接覆盖旧结论。
/// 前者在这里钉住，后者靠 `analyzedFingerprint` 与界面那条闸门。
///
/// 本文件只依赖纯 Dart（analysis_service 刻意 import 纯逻辑的 prompt_core，
/// 不是带 Flutter 依赖的那层壳），所以 `dart test` 能直接跑到。
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

  DreamEntry entry({
    String transcript = '我梦见在一条很长的走廊里跑，后面有人跟着。',
    String recentContext = '',
  }) =>
      DreamEntry(
        id: '20260920-0712',
        recordedAt: DateTime(2026, 9, 20, 7, 12),
        transcript: transcript,
        recentContext: recentContext,
      );

  /// 假服务端：记下每个请求体原文，回一份结构合法的最小解析结果。
  ({AnalysisService service, List<String> bodies}) harness({
    PromptBuilder? promptBuilder,
    String reply = '{"analysis_layer":[],"advice_layer":[],"limitations_note":"x"}',
  }) {
    final bodies = <String>[];
    final llm = LlmClient(
      httpClient: MockClient((req) async {
        bodies.add(req.body);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': reply}
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (
      service: AnalysisService(llm: llm, promptBuilder: promptBuilder ?? builder),
      bodies: bodies,
    );
  }

  group('解析调用本身', () {
    test('把温度 0 传到了请求体（这才是"结论不再自己变"的根因修复）', () async {
      final h = harness();
      final out = await h.service.analyze(config: cfg, entry: entry());

      expect(out.ok, isTrue, reason: out.error);
      final body = jsonDecode(h.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('temperature', 0));
    });

    test('system message 是完整框架（含 Schema），不是退化散文', () async {
      final h = harness();
      await h.service.analyze(config: cfg, entry: entry());

      final body = jsonDecode(h.bodies.single) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
      expect((messages.first as Map)['role'], 'system');
      expect((messages.first as Map)['content'] as String, contains('limitations_note'));
    });

    test('近期梦境摘要真的进了 user message（指纹说"覆盖了它"才名副其实）', () async {
      final h = harness();
      await h.service.analyze(
        config: cfg,
        entry: entry(),
        dreamHistoryDigest: '- 2026-09-19：梦见在考场找不到座位',
      );

      final body = jsonDecode(h.bodies.single) as Map<String, dynamic>;
      final userMsg = ((body['messages'] as List).last as Map)['content'] as String;
      expect(userMsg, contains('梦见在考场找不到座位'));
    });

    test('同一份输入解析两次：请求体逐字节一致，指纹也一致', () async {
      final h = harness();
      final first = await h.service.analyze(config: cfg, entry: entry());
      final second = await h.service.analyze(config: cfg, entry: entry());

      expect(h.bodies, hasLength(2));
      expect(h.bodies[0], h.bodies[1]);
      expect(first.fingerprint, second.fingerprint);
    });
  });

  group('指纹：界面与解析内部必须同口径', () {
    // 这是本文件最重要的一条。界面在用户点「重新解析」时会自己算一次指纹，
    // 拿去和记录里存的比。它和解析内部用的是同一个函数、由 AnalysisService
    // 同时提供——但只要有人把 fingerprintFor 里的输入拆开重写（比如忘了带上
    // 近期摘要），两边就会永远对不上，界面会一直误报"输入变了"。
    test('analyze 返回的指纹 == fingerprintFor 算的指纹', () async {
      final h = harness();
      const digest = '- 2026-09-19：梦见在考场找不到座位';
      final e = entry(recentContext: '最近工作压力大。');

      final out = await h.service.analyze(
        config: cfg,
        entry: e,
        dreamHistoryDigest: digest,
      );

      expect(out.fingerprint, isNotNull);
      expect(
        out.fingerprint,
        h.service.fingerprintFor(
          config: cfg,
          entry: e,
          dreamHistoryDigest: digest,
        ),
      );
    });
  });

  group('指纹：任何一份输入变了都必须被发现', () {
    late AnalysisService svc;
    setUp(() => svc = harness().service);

    String fp({
      DreamEntry? e,
      LlmConfig config = cfg,
      String digest = '',
      AnalysisService? service,
    }) =>
        (service ?? svc).fingerprintFor(
          config: config,
          entry: e ?? entry(),
          dreamHistoryDigest: digest,
        );

    test('输入没动 → 指纹一致', () {
      expect(fp(), fp());
    });

    test('原文变了 → 变', () {
      expect(fp(), isNot(fp(e: entry(transcript: '换了一段完全不同的梦。'))));
    });

    test('只改一个标点也算变了 → 变', () {
      expect(fp(), isNot(fp(e: entry(transcript: '我梦见在一条很长的走廊里跑，后面有人跟着'))));
    });

    test('近期状态变了 → 变', () {
      expect(fp(), isNot(fp(e: entry(recentContext: '最近工作压力大。'))));
    });

    test('模型换了 → 变', () {
      const other = LlmConfig(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        model: 'another-model',
      );
      expect(fp(), isNot(fp(config: other)));
    });

    test('近期梦境摘要变了 → 变', () {
      expect(fp(), isNot(fp(digest: '- 2026-09-19：梦见在考场找不到座位')));
    });

    test('解析框架文档改了 → 变（所以升框架之后重解析才有意义）', () {
      final patched = PromptBuilder(
        frameworkDoc.replaceFirst(
          '你是一名以古传周公解梦体系为依据',
          '你是一名以古传周公解梦体系与历代梦书为依据',
        ),
      );
      // 锚点若消失，replaceFirst 会原样返回 → 指纹相同 → 这条断言失败，
      // 正好提醒"框架文档的结构变了，测试要跟着改"。
      expect(fp(), isNot(fp(service: harness(promptBuilder: patched).service)));
    });
  });

  group('记录层：把"不知道"和"没变过"分开', () {
    test('老记录没有指纹 → 不认为是"输入没变"（不能凭未知拦住重解析）', () {
      expect(entry().analyzedFingerprint, isNull);
      expect(entry().analysisInputUnchanged('whatever'), isFalse);
    });

    test('指纹一致才算"输入没变"', () {
      final e = entry().copyWith(analyzedFingerprint: 'abc123');
      expect(e.analysisInputUnchanged('abc123'), isTrue);
      expect(e.analysisInputUnchanged('abc124'), isFalse);
    });

    test('指纹随 JSON 一起落盘、读回来还在', () {
      final e = entry().copyWith(analyzedFingerprint: 'abc123');
      expect(DreamEntry.fromJsonString(e.toJsonString()).analyzedFingerprint, 'abc123');
    });

    test('老 JSON 缺 analyzed_fingerprint 时读成 null，不炸', () {
      final j = entry().toJson()..remove('analyzed_fingerprint');
      expect(DreamEntry.fromJson(j).analyzedFingerprint, isNull);
    });

    test('clearAnalysisError 能把上一次的失败原因清掉', () {
      final e = entry().copyWith(analysisError: 'HTTP 500');
      expect(e.analysisError, 'HTTP 500');
      expect(e.copyWith(clearAnalysisError: true).analysisError, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // v1.1.4：输出语言指令必须走 **user message**，不能走 system message。
  //
  // 判据刻意定在"**真发出去的请求体**"这一层，而不是拼字符串那一层：
  // 0.5.0 的缺陷恰恰是"指令拼出来了、但拼错了地方"——放在 system prompt 末尾时
  // deepseek-v4-pro 会**静默忽略**（要求英文却交简体中文），而拼装层与护栏脚本
  // 全都照样全绿。只有按真实请求体判，才能钉住"它到底在哪条消息里"。
  // ---------------------------------------------------------------------------
  group('v1.1.4 输出语言指令的去向（按真实请求体判）', () {
    test('★ 语言指令在 user message 末尾，且 system message 里没有', () async {
      final h = harness();
      final d = AppLocale.en.analysisLanguageDirective!;
      await h.service.analyze(
        config: cfg,
        entry: entry(),
        languageDirective: d,
      );

      final body = jsonDecode(h.bodies.single) as Map<String, dynamic>;
      final msgs = body['messages'] as List;
      final sys = (msgs.first as Map)['content'] as String;
      final usr = (msgs.last as Map)['content'] as String;

      expect(usr, contains(d), reason: '指令必须随 user message 发出去');
      expect(usr.trimRight().endsWith(d), isTrue, reason: '必须排在整条消息最末尾');
      expect(sys, isNot(contains(d)), reason: '放 system prompt 末尾会被模型静默忽略');
    });

    test('zhCN 不带指令：user message 以原文收尾，不多一个换行', () async {
      final h = harness();
      await h.service.analyze(config: cfg, entry: entry(), languageDirective: null);

      final body = jsonDecode(h.bodies.single) as Map<String, dynamic>;
      final usr = ((body['messages'] as List).last as Map)['content'] as String;
      for (final l in AppLocale.values) {
        final d = l.analysisLanguageDirective;
        if (d != null) expect(usr, isNot(contains(d)));
      }
      // 逐字节性质：末尾就是原文本身（多一个 '\n' 就会让全部历史指纹失效）
      expect(usr.endsWith(entry().transcript), isTrue);
    });

    test('★ 换界面语言 → 真实请求体确实变了', () async {
      final h = harness();
      await h.service.analyze(config: cfg, entry: entry(), languageDirective: null);
      await h.service.analyze(
        config: cfg,
        entry: entry(),
        languageDirective: AppLocale.zhTW.analysisLanguageDirective,
      );

      expect(h.bodies, hasLength(2));
      expect(h.bodies[0], isNot(h.bodies[1]),
          reason: '否则会出现"界面是繁体、结论是简体，而程序认为输入没变"的静默错配');
    });

    test('★ 指纹覆盖了界面语言（否则重解析闸门会放行一份语言不对的旧结论）', () {
      final svc = AnalysisService(
        llm: LlmClient(
          httpClient: MockClient((_) async =>
              http.Response('{}', 200, headers: {'content-type': 'application/json'})),
        ),
        promptBuilder: builder,
      );
      final zh = svc.fingerprintFor(config: cfg, entry: entry());
      final en = svc.fingerprintFor(
        config: cfg,
        entry: entry(),
        languageDirective: AppLocale.en.analysisLanguageDirective,
      );
      expect(zh, isNot(en));
      expect(zh, svc.fingerprintFor(config: cfg, entry: entry())); // 同语言须稳定
    });
  });
}

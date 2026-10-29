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

import 'package:dream_reader/services/llm_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 请求体契约测试。
///
/// 背景（真实故障）：点「重新解析」，同一条梦的结论每次都换一套说法。
/// 根因不在模型，在这一层——请求体里**没有 temperature**，于是走服务商默认温度
/// （普遍 0.7~1.0），每次调用都重新随机采样。解析结论要挂在原文片段上供用户核对
/// 是本产品的立身之本，结论却在同一份输入上自己变，可查证性就没有立足点了。
///
/// 这里从"线上那一侧"把契约钉住：温度必须**显式**写进请求体、且默认是 0。
/// 纯 Dart（http 不依赖 Flutter），`dart test` 即可运行。
void main() {
  /// 假服务端：收下每个请求体原文，回一句合法 JSON。
  LlmClient clientCapturing(List<String> bodies) => LlmClient(
        httpClient: MockClient((req) async {
          bodies.add(req.body);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"analysis_layer": []}'}
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  const cfg = LlmConfig(
    baseUrl: 'https://api.example.com/v1',
    apiKey: 'sk-test',
    model: 'some-model',
  );

  test('请求体必须显式带 temperature，默认 0', () async {
    final bodies = <String>[];
    await clientCapturing(bodies).complete(
      config: cfg,
      systemPrompt: 'S',
      userPrompt: 'U',
    );

    final body = jsonDecode(bodies.single) as Map<String, dynamic>;
    // 用 containsPair 而不是 contains：既要值对，也要**键存在**。
    // 键不存在时值是 null，而 null != 0，所以这一条同时挡住了"漏写"这种改法。
    expect(body, containsPair('temperature', 0));
  });

  test('同一份输入调两次，请求体逐字节一致', () async {
    final bodies = <String>[];
    final client = clientCapturing(bodies);
    for (var i = 0; i < 2; i++) {
      await client.complete(config: cfg, systemPrompt: 'S', userPrompt: 'U');
    }
    expect(bodies, hasLength(2));
    expect(bodies[0], bodies[1]);
  });

  test('temperature 可以显式覆盖（给"明确要求换个说法"的功能留的口子）', () async {
    final bodies = <String>[];
    await clientCapturing(bodies).complete(
      config: cfg,
      systemPrompt: 'S',
      userPrompt: 'U',
      temperature: 0.8,
    );
    final body = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(body, containsPair('temperature', 0.8));
  });

  test('超时按模型区分：推理型给足时间，非推理型 3 分钟', () {
    // 真实实测（2026-09-22）：同一 Prompt、同一场梦，deepseek-v4-pro 每轮 38~48 秒，
    // glm-5.3 每轮 343~725 秒。一个写死的 3 分钟等于"选了推理型模型就必然失败"。
    expect(LlmClient.timeoutForModel('deepseek-v4-pro'), LlmClient.fastModelTimeout);
    expect(LlmClient.timeoutForModel('DeepSeek-V3'), LlmClient.fastModelTimeout);
    expect(LlmClient.timeoutForModel('glm-5.3'), LlmClient.reasoningModelTimeout);
    expect(LlmClient.timeoutForModel('qwq-32b'), LlmClient.reasoningModelTimeout);
    expect(LlmClient.timeoutForModel('o3-mini'), LlmClient.reasoningModelTimeout);
    expect(LlmClient.reasoningModelTimeout, greaterThan(LlmClient.fastModelTimeout));
  });

  test('超时抛的是人话 LlmException（不是裸的 TimeoutException）', () async {
    final client = LlmClient(
      // 假服务端故意慢，触发超时
      httpClient: MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return http.Response('{}', 200);
      }),
      timeout: const Duration(milliseconds: 40),
    );

    await expectLater(
      client.complete(config: cfg, systemPrompt: 'S', userPrompt: 'U'),
      throwsA(
        isA<LlmException>().having(
          (e) => e.message,
          'message',
          allOf(contains('已放弃'), contains('换一个更快的模型')),
        ),
      ),
    );
  });

  test('jsonMode 打开时带 response_format，关掉时不带', () async {
    final on = <String>[];
    await clientCapturing(on)
        .complete(config: cfg, systemPrompt: 'S', userPrompt: 'U', jsonMode: true);
    expect(
      jsonDecode(on.single) as Map<String, dynamic>,
      containsPair('response_format', {'type': 'json_object'}),
    );

    final off = <String>[];
    await clientCapturing(off)
        .complete(config: cfg, systemPrompt: 'S', userPrompt: 'U', jsonMode: false);
    expect(
      (jsonDecode(off.single) as Map<String, dynamic>).containsKey('response_format'),
      isFalse,
    );
  });

  group('失败必须说人话，并且要能分辨"是哪种失败"', () {
    // 背景（真实事故 2026-09-22）：服务端把长流掐断，用户看到的是
    // `调用异常：ClientException: Connection closed while receiving data`——
    // 英文、没有主语、没有下一步。用户会去怀疑自己的 Key 和网络设置，而这两样都不是原因。
    // 比这更糟的是：光有一句话还不够，**上层要靠这个分类决定"该不该重试"**。

    test('连接被掐断 → 人话 LlmException，且归类为 transport', () async {
      final client = LlmClient(
        httpClient: MockClient((req) async {
          // package:http 的 IOClient 就是这样把底层断流包出来的（见 io_client.dart）
          throw http.ClientException('Connection closed while receiving data', req.url);
        }),
      );

      await expectLater(
        client.complete(config: cfg, systemPrompt: 'S', userPrompt: 'U'),
        throwsA(
          isA<LlmException>()
              .having((e) => e.kind, 'kind', LlmFailure.transport)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('连接被中断'),
                  contains('不是 Key 或配置的问题'),
                  contains('重试'),
                  // 最要紧的一条：**不许把英文异常原文糊到用户脸上**
                  isNot(contains('ClientException')),
                ),
              ),
        ),
      );
    });

    test('服务端断流的那种原始异常（未经 package:http 包装）也能认出来', () async {
      // 响应体读到一半被掐时，IOClient 会把原始错误直接 addError，不经包装。
      // 本工程不许 import dart:io（有 web 目标），所以只能按类型名/文本兜 —— 这条钉住那个兜底。
      final client = LlmClient(
        httpClient: MockClient((req) async {
          throw _FakeSocketException('Connection terminated');
        }),
      );

      await expectLater(
        client.complete(config: cfg, systemPrompt: 'S', userPrompt: 'U'),
        throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmFailure.transport)),
      );
    });

    test('认不出来的异常**不许**伪装成"连接中断"', () async {
      final client = LlmClient(
        httpClient: MockClient((req) async => throw StateError('我自己的 bug')),
      );

      await expectLater(
        client.complete(config: cfg, systemPrompt: 'S', userPrompt: 'U'),
        throwsA(
          isA<LlmException>().having((e) => e.kind, 'kind', LlmFailure.unknown).having(
                (e) => e.message,
                'message',
                allOf(contains('调用模型服务时出错'), contains('我自己的 bug')),
              ),
        ),
      );
    });

    test('HTTP 状态码分档：429 / 5xx / 4xx 各归一类（重试策略靠它）', () async {
      Future<LlmFailure> kindOf(int code) async {
        final client = LlmClient(
          httpClient: MockClient((req) async => http.Response('{"error":"x"}', code)),
        );
        try {
          await client.complete(config: cfg, systemPrompt: 'S', userPrompt: 'U');
          fail('应当抛异常');
        } on LlmException catch (e) {
          return e.kind;
        }
      }

      expect(await kindOf(429), LlmFailure.rateLimited);
      expect(await kindOf(500), LlmFailure.server);
      expect(await kindOf(503), LlmFailure.server);
      expect(await kindOf(401), LlmFailure.clientError);
      expect(await kindOf(404), LlmFailure.clientError);
    });
  });
}

/// 假造一个"名字长得像 dart:io 的 SocketException"的异常。
///
/// 为什么不直接 import dart:io 造真的：本工程有 web 目标，而 `dart:io` 在 web 上不可用
/// ——测试文件虽然只在 VM 上跑，但把这条依赖带进测试会让人误以为产品代码也能这么写。
class _FakeSocketException implements Exception {
  final String message;
  _FakeSocketException(this.message);
  @override
  String toString() => 'SocketException: $message';
}

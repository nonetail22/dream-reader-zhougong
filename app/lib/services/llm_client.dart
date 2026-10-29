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

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/messages.dart';

/// BYOK（用户自带 Key）配置。默认走 OpenAI 兼容协议，用户可填任意兼容服务商。
class LlmConfig {
  final String baseUrl; // 如 https://api.deepseek.com/v1
  final String apiKey;
  final String model; // 如 deepseek-chat
  final bool stream; // 部分云端通道仅支持流式

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.stream = false,
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty &&
      (apiKey.trim().isNotEmpty || _isLocal(baseUrl));

  bool _isLocal(String url) =>
      url.contains('localhost') || url.contains('127.0.0.1') || url.contains('ollama');

  Map<String, dynamic> toJson() =>
      {'base_url': baseUrl, 'api_key': apiKey, 'model': model, 'stream': stream};

  static LlmConfig fromJson(Map<String, dynamic> j) => LlmConfig(
        baseUrl: (j['base_url'] ?? '').toString(),
        apiKey: (j['api_key'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        stream: j['stream'] == true,
      );

  LlmConfig copyWith({String? baseUrl, String? apiKey, String? model, bool? stream}) =>
      LlmConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        stream: stream ?? this.stream,
      );
}

/// 这次调用**是"怎么"失败的**。
///
/// 为什么要把它当成一等公民：三类失败的性价比完全不同，而重试策略必须依赖它
/// （见 `AnalysisService._retryPlan`）。2026-09-22 实测逼出了这个需求——
/// 同一天里 glm 因长流被服务端掐断**零产出**，而把它塞进同一个 `catch (e)` 里
/// 只能得到一句 `调用异常：ClientException: Connection closed…`，
/// 用户既看不懂，我也无从判断"该不该重试"。
enum LlmFailure {
  /// 等到上限还没回（模型还在想，或干脆卡住）
  timeout,

  /// 连接建不起来 / 中途被掐断（含**服务端主动切断长流**）
  transport,

  /// 429：被限流，等一下再试多半能成
  rateLimited,

  /// 5xx：服务端自己出问题了，值得再试一次
  server,

  /// 4xx（除 429）：Key 不对 / 模型名不对 / 参数不对 —— 原样重发不可能成功
  clientError,

  /// 认不出来的失败。**刻意保留这一档，而不是硬塞进上面任何一类**：
  /// 给一个错误的原因，比给一个错的应对方式更害人。
  unknown,
}

class LlmException implements Exception {
  final String message;
  final int? statusCode;
  final LlmFailure kind;

  LlmException(this.message, {this.statusCode, this.kind = LlmFailure.unknown});

  @override
  String toString() => statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// OpenAI 兼容协议的轻量客户端：支持非流式与 SSE 流式两种模式。
/// 客户端只与「用户自己配置的服务商」通信；本 App 不上传任何用户数据到自有服务器。
class LlmClient {
  final http.Client _http;

  /// 显式覆盖超时；**留 null 表示按模型自动判定**（见 [timeoutForModel]）。
  final Duration? timeoutOverride;

  LlmClient({http.Client? httpClient, Duration? timeout})
      : _http = httpClient ?? http.Client(),
        timeoutOverride = timeout;

  /// 非推理型模型的等待上限。
  static const Duration fastModelTimeout = Duration(minutes: 3);

  /// 推理型模型的等待上限。
  ///
  /// 真实实测（2026-09-22 四轮多轮闭环，同一个 Prompt、同一场梦）：
  /// deepseek-v4-pro 每轮 **38~48 秒**，而 glm-5.3 每轮 **343~725 秒**，
  /// 还有一次 **900 秒（15 分钟整）零产出**（流被掐断，用户什么都拿不到）。
  /// 把两者塞进同一个 3 分钟里，等价的后果是"用户一选推理型模型，就必然超时"——
  /// 那不是模型的问题，是这一行的默认值的问题。
  static const Duration reasoningModelTimeout = Duration(minutes: 15);

  /// 按模型名判定该等多久。
  static Duration timeoutForModel(String model) =>
      looksLikeReasoningModel(model) ? reasoningModelTimeout : fastModelTimeout;

  /// 模型名里带这些特征的多半会先输出大段推理再给正文。
  ///
  /// 这只是**按名字**的启发式：真正决定快慢的是"它会不会输出 reasoning"，
  /// 而 BYOK 场景下客户端拿不到这个元数据（用户填的是任意 OpenAI 兼容模型名）。
  /// 所以阈值取得宽一些，并在超时文案里把原因说清，让用户有下一步可做。
  static bool looksLikeReasoningModel(String model) {
    final m = model.toLowerCase();
    const hints = ['reason', 'thinking', 'think-', '-r1', 'qwq', 'o1', 'o3', 'glm-5', 'glm-4.5'];
    return hints.any(m.contains);
  }

  Uri _endpoint(String baseUrl) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    // 兼容用户填写不带 /v1 的场景（openai 兼容服务通常需要 /v1）
    if (!b.endsWith('/v1') && !b.contains('/v1/') && !b.endsWith('/chat/completions')) {
      b = '$b/v1';
    }
    return Uri.parse('$b/chat/completions');
  }

  Map<String, String> _headers(LlmConfig c) => {
        'Content-Type': 'application/json',
        if (c.apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${c.apiKey.trim()}',
      };

  List<Map<String, String>> _messages(String system, String user) => [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ];

  /// 单次补全，返回完整文本。stream=true 时解析 SSE 分片拼接。
  ///
  /// **[temperature] 默认 0，且必须写在请求体里**。
  ///
  /// 不传这个字段时用的是服务商默认温度（普遍 0.7~1.0），也就是每次调用都重新
  /// 随机采样：同一条梦、同一份框架文档，两次解析会得到两套不同的结论。
  /// 对本产品这是**产品级缺陷**而不是风格问题——解析结论要挂在原文片段上供用户
  /// 核对（可查证性），结论却在同一份输入上自己变来变去，那"可查证"就没了立足点；
  /// 用户点一下「重新解析」就换一套说法，还会误以为是模型在修正自己。
  ///
  /// 传 0 走贪心解码，把「输入相同 → 输出相同」变成默认行为。
  /// 注意它**不是数学保证**：部分服务商（MoE 架构、连续批处理）即使温度 0 也可能
  /// 因浮点累加顺序不同而给出不同分句。所以界面层另有一道"输入没变就别重来"的
  /// 闸门（见 DreamDetailPage）——那才是真正兜住"结论不被无谓覆盖"的一层。
  Future<String> complete({
    required LlmConfig config,
    required String systemPrompt,
    required String userPrompt,
    bool jsonMode = true,
    double temperature = 0,
  }) async {
    final body = jsonEncode({
      'model': config.model,
      'messages': _messages(systemPrompt, userPrompt),
      'stream': config.stream,
      'temperature': temperature,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    });

    final effectiveTimeout = timeoutOverride ?? timeoutForModel(config.model);

    http.Response resp;
    try {
      resp = await _http
          .post(_endpoint(config.baseUrl), headers: _headers(config), body: body)
          .timeout(effectiveTimeout);
    } on TimeoutException {
      // 超时必须是**用户看得懂、且有下一步**的一句话。
      // 这一层以前只会被外层 catch 成"调用异常：TimeoutException after 0:03:00"——
      // 用户看不懂，也不知道该改什么。
      final hint = looksLikeReasoningModel(config.model)
          ? AppL10n.current.tr('err_llm_timeout_hint_reasoning')
          : AppL10n.current.tr('err_llm_timeout_hint_fast');
      throw LlmException(
        AppL10n.current.tr('err_llm_timeout', {
          'minutes': '${effectiveTimeout.inMinutes}',
          'hint': hint,
        }),
        kind: LlmFailure.timeout,
      );
    } catch (e) {
      // ★ 传输层失败也要变成人话。真实事故（2026-09-22）：服务端把长流掐断，
      // 用户看到的是 `调用异常：ClientException: Connection closed while receiving data`
      // ——英文、没有主语、也没有下一步。用户会去怀疑自己的 Key 和网络设置，
      // 而这两样恰恰都不是原因。
      if (_looksLikeTransportError(e)) {
        throw LlmException(
          AppL10n.current.tr('err_llm_transport'),
          kind: LlmFailure.transport,
        );
      }
      // 认不出来的异常**不伪装成"连接中断"**——只标明"这是调用阶段出的"，
      // 并把原文带上。宁可让用户看到一句难懂的细节，也不要给一个错的原因。
      throw LlmException(
        AppL10n.current.tr('err_llm_invoke', {'e': '$e'}),
        kind: LlmFailure.unknown,
      );
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LlmException(
        _short(resp.body),
        statusCode: resp.statusCode,
        kind: _kindForStatus(resp.statusCode),
      );
    }
    if (!config.stream) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return _extractContent(data);
    }
    return _parseSse(resp.body);
  }

  static LlmFailure _kindForStatus(int code) {
    if (code == 429) return LlmFailure.rateLimited;
    if (code >= 500) return LlmFailure.server;
    if (code >= 400) return LlmFailure.clientError;
    return LlmFailure.unknown;
  }

  /// 判断一个底层异常是不是"传输类"。
  ///
  /// **刻意不 `import 'dart:io'`**：本工程有 web 目标，而 `SocketException` /
  /// `HttpException` 只存在于 `dart:io`，import 进来 web 就编不过。
  /// 好在 `package:http` 的 IOClient 会把底层错误尽量包一层
  /// （`SocketException → _ClientSocketException extends ClientException`，
  /// `HttpException → ClientException`），所以**类型判断能覆盖主要情形**；
  /// 剩下漏网的（例如响应体读到一半连接被掐，IOClient 会把原始错误直接 addError，
  /// 不经包装）按**类型名 / 文本**兜一层。
  ///
  /// 这段里的字符串匹配看着不优雅，但它只在 `try { http.post }` 这一个请求内生效，
  /// 误判的代价是"把一次调用失败说成连接中断 + 多试一次"，可以接受。
  static bool _looksLikeTransportError(Object e) {
    if (e is http.ClientException) return true;

    final type = e.runtimeType.toString();
    for (final n in const [
      'SocketException',
      'HttpException',
      'HandshakeException',
      'TlsException',
      'OSError',
    ]) {
      if (type.contains(n)) return true;
    }

    final text = e.toString();
    for (final s in const [
      'Connection closed',
      'Connection reset',
      'Connection terminated',
      'terminated',
      'Broken pipe',
      'Connection refused',
      'Network is unreachable',
      'Software caused connection abort',
    ]) {
      if (text.contains(s)) return true;
    }
    return false;
  }

  String _extractContent(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map && msg['content'] != null) return msg['content'].toString();
      final text = (choices.first as Map)['text'];
      if (text != null) return text.toString();
    }
    throw LlmException(
      AppL10n.current.tr('err_llm_no_content'),
      // 服务端 200 但给的响应我们读不出东西 —— 这是**服务端侧**的问题，值得再试一次
      kind: LlmFailure.server,
    );
  }

  /// 解析 SSE：把各 data: 分片的 delta.content 拼起来；兼容整段 JSON 返回。
  String _parseSse(String raw) {
    final trimmed = raw.trimLeft();
    if (trimmed.startsWith('{')) {
      // 少数服务商忽略 stream 参数直接返回完整 JSON
      return _extractContent(jsonDecode(raw) as Map<String, dynamic>);
    }
    final sb = StringBuffer();
    for (final line in const LineSplitter().convert(raw)) {
      final l = line.trim();
      if (!l.startsWith('data:')) continue;
      final payload = l.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        final chunk = jsonDecode(payload);
        if (chunk is! Map) continue;
        final choices = chunk['choices'];
        if (choices is List && choices.isNotEmpty) {
          final delta = (choices.first as Map)['delta'];
          if (delta is Map && delta['content'] != null) {
            sb.write(delta['content'].toString());
          }
        }
      } catch (_) {
        // 忽略无法解析的单片，避免整次调用失败
      }
    }
    if (sb.isEmpty) {
      // 200 + 流里一个字都没有：同样是**服务端侧**的问题（流开起来了却没内容），
      // 与"连接被掐断"（transport）不同——那个连响应头都没读完。两者都值得再试。
      throw LlmException(
        AppL10n.current.tr('err_llm_empty_stream'),
        kind: LlmFailure.server,
      );
    }
    return sb.toString();
  }

  String _short(String s) => s.length > 300 ? s.substring(0, 300) : s;

  void close() => _http.close();
}

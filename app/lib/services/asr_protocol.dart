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

// 云端转写的「协议层」：纯逻辑，**不依赖 Flutter、不依赖 http**。
//
// 单独拆出来是因为这里三个函数都是"错了只会得到一句看不懂的报错"的地方：
// 地址拼错的后果是无信息量的 404、MIME 给错的后果是 "unsupported format"、
// 响应解析错的后果是空文本。它们必须能被 `dart test` 直接钉住，
// 而 cloud_transcriber.dart 依赖 http/Flutter，跑不了 dart test。
//
// 借鉴自 speech_errors.dart 的同一套做法。

import 'dart:convert';

import '../l10n/messages.dart';

/// 云端转写的 BYOK 配置。
///
/// 刻意**和解析用的模型配置分开**：解析（DeepSeek/GLM）和转写
/// （Whisper / SenseVoice 之类）几乎不可能是同一家的同一个模型——
/// DeepSeek 就没有转写接口。硬把两者揉成一份配置，用户一定会踩到
/// "解析能用、转写 404"这种莫名其妙的坑。
class CloudAsrConfig {
  const CloudAsrConfig({this.baseUrl = '', this.apiKey = '', this.model = ''});

  final String baseUrl;

  /// 只存本机安全存储，且**只发给 baseUrl 这一家**——App 不做任何中转。
  final String apiKey;

  /// 服务商那边的转写模型名，如 `FunAudioLLM/SenseVoiceSmall`、`whisper-1`
  final String model;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  /// 归一后的转写接口地址（空配置时为空串）
  String get endpoint => asrEndpoint(baseUrl);

  CloudAsrConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      CloudAsrConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );

  Map<String, dynamic> toJson() => {
        'base_url': baseUrl,
        'model': model,
        // apiKey 不进这里：它单独存安全存储
      };

  static CloudAsrConfig fromJson(Map<String, dynamic> j, {String apiKey = ''}) =>
      CloudAsrConfig(
        baseUrl: j['base_url']?.toString() ?? '',
        model: j['model']?.toString() ?? '',
        apiKey: apiKey,
      );
}

/// 把用户填的 Base URL 归一成转写接口地址。
///
/// 用户会填成各种样子（带 /v1、不带 /v1、甚至直接填整个接口地址），
/// 而拼错了的后果是 404——一句毫无信息量的报错。所以这里做归一，
/// 并且把归一结果回显在设置页上，让用户能自己对一眼。
String asrEndpoint(String baseUrl) {
  var u = baseUrl.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.isEmpty) return '';
  if (u.endsWith('/audio/transcriptions')) return u;
  if (u.endsWith('/v1')) return '$u/audio/transcriptions';
  return '$u/v1/audio/transcriptions';
}

/// 按扩展名给音频一个 MIME 类型。
///
/// 不少服务商是**按 MIME 或扩展名**决定怎么解码的，给错会得到
/// "unsupported format" 之类的报错，而不是明确说"你应该传 wav"。
String mimeForPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.wav')) return 'audio/wav';
  if (p.endsWith('.m4a') || p.endsWith('.mp4')) return 'audio/mp4';
  if (p.endsWith('.mp3')) return 'audio/mpeg';
  if (p.endsWith('.ogg') || p.endsWith('.opus')) return 'audio/ogg';
  if (p.endsWith('.flac')) return 'audio/flac';
  if (p.endsWith('.webm')) return 'audio/webm';
  return 'application/octet-stream';
}

/// 把 HTTP 状态码翻译成「用户能据此行动」的话。
///
/// 只回一句"请求失败(401)"等于什么都没说。
String describeHttpFailure(int status, String body) {
  final tr = AppL10n.current.tr;
  final snippet = shortBody(body);
  // 「服务商原话：…」这一段的换行与前缀也跟着语言走；没有原话时不追加任何东西。
  final detail = snippet.isEmpty
      ? ''
      : tr('err_asr_server_quote', {'snippet': snippet});
  switch (status) {
    case 400:
      return tr('err_asr_400', {'detail': detail});
    case 401:
      return tr('err_asr_401');
    case 402:
      return tr('err_asr_402');
    case 403:
      return tr('err_asr_403');
    case 404:
      return tr('err_asr_404');
    case 413:
      return tr('err_asr_413');
    case 429:
      return tr('err_asr_429');
    case 500:
    case 502:
    case 503:
    case 504:
      return tr('err_asr_5xx', {'status': '$status'});
    default:
      return tr('err_asr_default', {'status': '$status', 'detail': detail});
  }
}

/// 把响应体截短，避免把一整页 HTML 错误页糊到界面上。
String shortBody(String s) {
  var t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length > 200) t = '${t.substring(0, 200)}…';
  return t;
}

/// 从响应里取文本。
///
/// 兼容两种常见形状：
/// 1. OpenAI / 硅基流动的 `{"text": "…"}`
/// 2. 聊天补全那种 `{"choices":[{"message":{"content":"…"}}]}`——
///    有些兼容层会把转写塞进这个形状。
///
/// 返回 `null` 表示"这个响应里根本没有文字字段"，与"文字是空串"是两回事：
/// 前者说明接口不兼容（要换服务商），后者说明这回真的没听到声音。
String? extractTranscriptText(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final t = j['text'];
      if (t is String) return t;
      final choices = j['choices'];
      if (choices is List && choices.isNotEmpty) {
        final m = choices.first;
        if (m is Map) {
          final msg = m['message'];
          if (msg is Map && msg['content'] is String) {
            return msg['content'] as String;
          }
          if (m['text'] is String) return m['text'] as String;
        }
      }
    }
  } catch (_) {
    // 不是 JSON —— 交给调用方报"读不出文字"
  }
  return null;
}

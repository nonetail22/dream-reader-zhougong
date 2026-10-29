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
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'asr_protocol.dart';
import 'transcriber.dart';

// 协议层（地址归一 / MIME / 报错翻译 / 响应解析）放在纯逻辑文件里，
// 好让 `dart test` 能覆盖到——本文件依赖 http 与 Flutter，跑不动。
export 'asr_protocol.dart' show CloudAsrConfig, asrEndpoint, mimeForPath;

/// 云端转写：把整段录音 POST 给用户自己配置的服务商（OpenAI 兼容的
/// `/audio/transcriptions` 接口），拿回文字。
///
/// **这是唯一一条音频会离开设备的路径。** 界面上必须明说，不能只写在
/// 隐私政策里——用户选它的时候就应该知道自己换来了什么、付出了什么。
///
/// App 不做任何中转：音频直接发往 baseUrl 指向的那一家，App 不落档、不留存。
class CloudTranscriber implements FileTranscriber {
  CloudTranscriber({CloudAsrConfig? config, this.onStatus})
      : _config = config ?? const CloudAsrConfig();

  CloudAsrConfig _config;

  StatusSink? onStatus;

  void Function(String message)? _onError;

  @override
  set onError(void Function(String message) callback) => _onError = callback;

  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  String get label => '云端转写';

  set config(CloudAsrConfig next) => _config = next;

  /// 单次上传 + 识别的超时。3 分钟的录音在移动网络下也要给足时间，
  /// 所以取 180 秒；但必须有上限，否则没网时会一直转圈到用户杀进程。
  static const Duration timeout = Duration(seconds: 180);

  @override
  Future<bool> init() async => (await readyIssue()) == null;

  @override
  Future<String?> readyIssue() async {
    if (_config.baseUrl.trim().isEmpty) {
      return '还没填服务商的 Base URL。没有它，录音不知道该发到哪儿。';
    }
    if (_config.apiKey.trim().isEmpty) {
      return '还没填 API Key。云端转写要用你自己的账号额度，所以必须自己填。';
    }
    if (_config.model.trim().isEmpty) {
      return '还没填转写模型名（例如 whisper-1 / FunAudioLLM/SenseVoiceSmall）。';
    }
    return null;
  }

  @override
  Future<String> transcribe(String audioPath) async {
    try {
      final issue = await readyIssue();
      if (issue != null) {
        throw TranscriberException('云端转写还没配置好。', hint: issue);
      }
      final endpoint = _config.endpoint;
      final uri = Uri.tryParse(endpoint);
      if (uri == null || !uri.hasScheme) {
        throw TranscriberException(
          'Base URL 不是一个有效网址。',
          hint: '当前值：`${_config.baseUrl}`\n'
              '应该形如 `https://api.siliconflow.cn/v1`（不要带后面的 /audio/transcriptions）。',
        );
      }

      final file = File(audioPath);
      if (!await file.exists()) {
        throw TranscriberException(
          '找不到录音文件，没法上传。',
          hint: '路径：$audioPath\n可以再说一次。',
        );
      }
      final size = await file.length();

      onStatus?.call('正在上传录音（${(size / 1024).toStringAsFixed(0)}KB）…');
      final sw = Stopwatch()..start();
      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${_config.apiKey.trim()}'
        ..fields['model'] = _config.model.trim()
        ..fields['response_format'] = 'json'
        // 固定中文：本应用只用来记录中文口述，让服务商省掉语言探测
        ..fields['language'] = 'zh'
        ..files.add(await http.MultipartFile.fromPath(
          'file',
          audioPath,
          contentType: MediaType.parse(mimeForPath(audioPath)),
        ));

      onStatus?.call('正在上传并识别…');
      final streamed = await req.send().timeout(timeout);
      final body = await streamed.stream.bytesToString().timeout(timeout);
      debugPrint('[DreamReader] 云端转写 HTTP ${streamed.statusCode}，'
          '${sw.elapsedMilliseconds}ms，${body.length} 字节响应');

      if (streamed.statusCode != 200) {
        throw TranscriberException(
          describeHttpFailure(streamed.statusCode, body),
          hint: '接口地址：$endpoint\n模型：${_config.model.trim()}',
        );
      }

      final text = extractTranscriptText(body);
      if (text == null) {
        throw TranscriberException(
          '服务商返回的内容读不出文字。',
          hint: '它没有按 OpenAI 的格式返回 `{"text": "…"}`。\n'
              '原始响应前 200 字：${shortBody(body)}\n'
              '如果这家服务商不是 OpenAI 兼容接口，请换一家。',
        );
      }
      if (text.trim().isEmpty) {
        throw const TranscriberException(
          '服务商没听出任何内容（返回了空文本）。',
          hint: '可能是录音太轻、太短，或者刚才没在说话。可以再说一次。',
        );
      }
      _lastError = null;
      return text.trim();
    } on TranscriberException catch (e) {
      _lastError = e.message;
      _onError?.call(e.message);
      rethrow;
    } on TimeoutException {
      final msg = '上传/识别超时（超过 ${timeout.inSeconds} 秒）。';
      _lastError = msg;
      _onError?.call(msg);
      throw TranscriberException(
        msg,
        hint: '云端转写必须联网。检查一下网络是否通，'
            '或者到「设置 → 语音识别方式」换成「离线识别」——那条不需要联网。',
      );
    } catch (e, st) {
      debugPrint('[DreamReader] 云端转写异常: $e\n$st');
      final msg = '云端转写失败：$e';
      _lastError = msg;
      _onError?.call(msg);
      throw TranscriberException(
        msg,
        hint: '如果这台设备根本连不上外网，请改用「离线识别」。',
      );
    } finally {
      onStatus?.call(null);
    }
  }

  @override
  void dispose() {
    onStatus = null;
  }
}

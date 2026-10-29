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

// 云端转写协议层的测试。
//
// 这三件事错了都只会得到一句看不懂的报错（404 / unsupported format / 空文本），
// 而它们恰恰是用户自己填参数时最容易踩的。所以用测试把行为钉死。
import 'dart:convert';

import 'package:dream_reader/services/asr_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('asrEndpoint：把用户填的各种样子归一到真实接口地址', () {
    test('带 /v1 的最常见写法', () {
      expect(asrEndpoint('https://api.siliconflow.cn/v1'),
          'https://api.siliconflow.cn/v1/audio/transcriptions');
      expect(asrEndpoint('https://api.openai.com/v1'),
          'https://api.openai.com/v1/audio/transcriptions');
    });

    test('末尾斜杠要被吃掉，不能拼出 //', () {
      expect(asrEndpoint('https://api.openai.com/v1/'),
          'https://api.openai.com/v1/audio/transcriptions');
      expect(asrEndpoint('https://api.openai.com/v1///'),
          'https://api.openai.com/v1/audio/transcriptions');
    });

    test('不带 /v1 的自己补上', () {
      expect(asrEndpoint('https://api.openai.com'),
          'https://api.openai.com/v1/audio/transcriptions');
    });

    test('已经填成完整接口地址时原样使用（不能拼成 …/audio/transcriptions/audio/transcriptions）', () {
      expect(asrEndpoint('https://api.openai.com/v1/audio/transcriptions'),
          'https://api.openai.com/v1/audio/transcriptions');
    });

    test('自定义路径（如兼容层的 /compatible-mode/v1）保留', () {
      expect(asrEndpoint('https://dashscope.aliyuncs.com/compatible-mode/v1'),
          'https://dashscope.aliyuncs.com/compatible-mode/v1/audio/transcriptions');
    });

    test('空输入返回空，而不是拼出一个假地址', () {
      expect(asrEndpoint(''), '');
      expect(asrEndpoint('   '), '');
    });

    test('前后空格会被修掉（从别处复制粘贴几乎一定带空格）', () {
      expect(asrEndpoint('  https://api.openai.com/v1  '),
          'https://api.openai.com/v1/audio/transcriptions');
    });
  });

  group('mimeForPath：给错 MIME 会得到含糊的 unsupported format', () {
    test('识别用 WAV', () {
      expect(mimeForPath('/a/b.wav'), 'audio/wav');
      expect(mimeForPath('/a/b.WAV'), 'audio/wav');
    });

    test('留档用的 m4a / mp3 / ogg / flac', () {
      expect(mimeForPath('x.m4a'), 'audio/mp4');
      expect(mimeForPath('x.mp3'), 'audio/mpeg');
      expect(mimeForPath('x.opus'), 'audio/ogg');
      expect(mimeForPath('x.flac'), 'audio/flac');
    });

    test('认不出来时给通用类型，而不是瞎猜一个 audio/*', () {
      expect(mimeForPath('x.dat'), 'application/octet-stream');
      expect(mimeForPath('x'), 'application/octet-stream');
    });
  });

  group('describeHttpFailure：把状态码翻译成能行动的话', () {
    test('401 要指向"去哪儿重填"', () {
      final s = describeHttpFailure(401, '');
      expect(s, contains('401'));
      expect(s, contains('设置'), reason: '光说"鉴权失败"用户不知道该干嘛');
    });

    test('404 要指向 Base URL 写错这个真实原因', () {
      final s = describeHttpFailure(404, '');
      expect(s, contains('Base URL'));
    });

    test('400 要带上服务商原话，否则无法自查', () {
      final s = describeHttpFailure(400, '  {"error":"model not found"}  ');
      expect(s, contains('model not found'));
    });

    test('5xx 要说明"不是你的配置问题"', () {
      for (final code in [500, 502, 503, 504]) {
        expect(describeHttpFailure(code, ''), contains('不是你的配置问题'));
      }
    });

    test('未知状态码也要把码和原话带出来', () {
      final s = describeHttpFailure(418, 'I am a teapot');
      expect(s, contains('418'));
      expect(s, contains('I am a teapot'));
    });

    test('超长响应体会被截短，避免糊满界面', () {
      final s = describeHttpFailure(400, 'x' * 5000);
      expect(s.length, lessThan(600));
      expect(s, contains('…'));
    });

    test('每个状态码都给出一句非空的话', () {
      for (final code in [400, 401, 402, 403, 404, 413, 429, 500, 502, 599]) {
        expect(describeHttpFailure(code, '').trim().length, greaterThan(8));
      }
    });
  });

  group('extractTranscriptText：OpenAI 兼容的两种形状', () {
    test('标准形状 {"text": …}', () {
      expect(extractTranscriptText('{"text":"我梦见在飞"}'), '我梦见在飞');
    });

    test('聊天补全形状也能取到', () {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': '我梦见考试'}
          }
        ]
      });
      expect(extractTranscriptText(body), '我梦见考试');
    });

    test('空文本返回空串，不等于"没有字段"', () {
      // 这两种情况要分开：空串 = 真没听到声音；null = 接口不兼容（该换服务商）
      expect(extractTranscriptText('{"text":""}'), '');
      expect(extractTranscriptText('{"text":""}'), isNotNull);
    });

    test('没有文字字段时返回 null', () {
      expect(extractTranscriptText('{"error":"bad model"}'), isNull);
      expect(extractTranscriptText('{"choices":[]}'), isNull);
    });

    test('不是 JSON（比如一页 HTML 错误页）返回 null 而不是崩', () {
      expect(extractTranscriptText('<html><body>502 Bad Gateway</body></html>'),
          isNull);
      expect(extractTranscriptText(''), isNull);
    });

    test('中文标点与 emoji 原样保留（有些服务商会回 emoji）', () {
      expect(extractTranscriptText('{"text":"梦见下雨了…😊"}'), '梦见下雨了…😊');
    });
  });

  group('CloudAsrConfig：配置与落盘', () {
    test('三项齐全才算配置好', () {
      const full = CloudAsrConfig(
          baseUrl: 'https://a/v1', apiKey: 'sk-x', model: 'whisper-1');
      expect(full.isConfigured, isTrue);
      expect(full.endpoint, 'https://a/v1/audio/transcriptions');

      expect(full.copyWith(baseUrl: '  ').isConfigured, isFalse);
      expect(full.copyWith(apiKey: '').isConfigured, isFalse);
      expect(full.copyWith(model: '').isConfigured, isFalse);
    });

    test('序列化里不含 API Key（它单独进安全存储）', () {
      const cfg = CloudAsrConfig(
          baseUrl: 'https://a/v1', apiKey: 'sk-secret', model: 'whisper-1');
      final j = cfg.toJson();
      expect(j.containsKey('apiKey'), isFalse);
      expect(jsonEncode(j), isNot(contains('sk-secret')));
    });

    test('反序列化能还原，Key 由调用方补进来', () {
      const cfg = CloudAsrConfig(
          baseUrl: 'https://a/v1', apiKey: 'sk-secret', model: 'whisper-1');
      final back = CloudAsrConfig.fromJson(
        jsonDecode(jsonEncode(cfg.toJson())) as Map<String, dynamic>,
        apiKey: 'sk-secret',
      );
      expect(back.baseUrl, cfg.baseUrl);
      expect(back.model, cfg.model);
      expect(back.apiKey, 'sk-secret');
    });
  });
}

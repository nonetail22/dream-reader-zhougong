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

import 'package:test/test.dart';

import 'package:dream_reader/services/speech_errors.dart';

/// 语音识别错误码映射的契约测试。
///
/// 这段逻辑之所以值得单独测：识别失败在 Android 上**多数时候不抛异常**，
/// 只走 onError 回调或干脆静默返回空结果。映射错了 = 用户拿不到任何线索，
/// 而这正是本次「按住说话识别不出内容」排查困难的根源。
void main() {
  group('mapSpeechError 错误码映射', () {
    test('权限问题', () {
      expect(mapSpeechError('error_permission'), contains('权限'));
    });

    test('麦克风被占用 —— 本次线上问题的直接对应项', () {
      expect(mapSpeechError('error_busy'), contains('占用'));
    });

    test('采集失败', () {
      expect(mapSpeechError('error_audio_error'), contains('采集失败'));
    });

    test('网络不可用', () {
      expect(mapSpeechError('error_network'), contains('联网'));
      expect(mapSpeechError('error_network_timeout'), contains('联网'));
    });

    test('语言包缺失', () {
      expect(mapSpeechError('error_language_not_supported'), contains('中文'));
      expect(mapSpeechError('error_language_unavailable'), contains('中文'));
    });

    test('没听到声音 vs 听到了但识别不出来，要能区分', () {
      final timeout = mapSpeechError('error_speech_timeout');
      final noMatch = mapSpeechError('error_no_match');
      expect(timeout, contains('没有听到声音'));
      expect(noMatch, contains('听到了声音'));
      expect(timeout, isNot(equals(noMatch)));
    });

    test('识别服务被关闭', () {
      expect(mapSpeechError('error_speech_recognizer_disabled'), contains('关闭'));
    });

    test('服务端异常保留原始错误码，便于排查', () {
      expect(mapSpeechError('error_server'), contains('error_server'));
      expect(mapSpeechError('error_client'), contains('error_client'));
    });

    test('未知错误也要保留原文，不能退化成「识别失败」四个字', () {
      final msg = mapSpeechError('error_unknown (99)');
      expect(msg, contains('error_unknown (99)'));
    });

    test('大小写不敏感（不同设备上报的大小写不一致）', () {
      expect(mapSpeechError('ERROR_PERMISSION'), contains('权限'));
      expect(mapSpeechError('Error_Busy'), contains('占用'));
    });

    test('每个分支都必须给出非空且有信息量的提示', () {
      const codes = [
        'error_permission',
        'error_busy',
        'error_audio_error',
        'error_network',
        'error_language_not_supported',
        'error_speech_timeout',
        'error_no_match',
        'error_speech_recognizer_disabled',
        'error_server',
        'error_client',
        'error_server_disconnected',
        'error_too_many_requests',
        'error_retry',
        'error_unknown (7)',
      ];
      for (final c in codes) {
        final msg = mapSpeechError(c);
        expect(msg.length, greaterThan(8), reason: '$c 的提示太短，等于没说');
      }
    });
  });
}

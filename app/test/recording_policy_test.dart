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

import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/recording_policy.dart';
import 'package:test/test.dart';

/// 录音留存的两个开关「取值规则」，以及记录上的 `audioPath` 能不能真的清掉。
///
/// 为什么这两件事一起测：它们是同一个功能的两个半场 —— 规则决定"录音留不留"，
/// `audioPath` 决定"记录还认不认这条录音"。任一半错了，界面上都会出现
/// 「设置了保留 / 显示了录音」但实际拿不到文件的假象。
void main() {
  group('resolveKeepRecording（识别完保留录音）', () {
    test('什么都没存过 → 默认**保留**', () {
      // 0.3.3 的默认值翻转点。默认转写方式是离线，音频本来就要录，
      // 留着只是留存策略，而它是转录文字唯一的原始证据。
      expect(resolveKeepRecording(), isTrue);
    });

    test('新键有值时以新键为准', () {
      expect(resolveKeepRecording(current: true), isTrue);
      expect(resolveKeepRecording(current: false), isFalse);
    });

    test('新键优先于旧键 —— 用户改过之后不该被旧值拉回去', () {
      expect(resolveKeepRecording(current: false, legacy: true), isFalse);
      expect(resolveKeepRecording(current: true, legacy: false), isTrue);
    });

    test('迁移：只有旧的 save_audio 时按它走，不替老用户改主意', () {
      expect(resolveKeepRecording(legacy: true), isTrue);
      expect(resolveKeepRecording(legacy: false), isFalse);
    });
  });

  group('resolveAlsoRecordDuringSystemAsr（系统识别时同时录一份）', () {
    test('什么都没存过 → 默认**不录**（有代价的默认值）', () {
      // 打开它会让本应用占住麦克风，把系统识别静音且不报错。
      // 识别是主功能、音频是附加品，所以默认让识别独占麦克风。
      expect(resolveAlsoRecordDuringSystemAsr(), isFalse);
    });

    test('迁移：旧的 save_audio=true 在系统识别下本就等于"开着额外录音"', () {
      expect(resolveAlsoRecordDuringSystemAsr(legacy: true), isTrue);
      expect(resolveAlsoRecordDuringSystemAsr(legacy: false), isFalse);
    });

    test('新键优先于旧键', () {
      expect(resolveAlsoRecordDuringSystemAsr(current: false, legacy: true), isFalse);
      expect(resolveAlsoRecordDuringSystemAsr(current: true, legacy: false), isTrue);
    });
  });

  test('★ 拆开关的全部意义：全新用户是「保留录音=开」+「同时录一份=关」', () {
    // 合成一个开关时这两个默认值只能二选一：想默认保留（用户要的），就会连带
    // 把"抢麦克风"也默认打开，一切到系统识别就静默失灵（华为那次就是这么来的）。
    // 这条断言守的就是"这两个默认值可以各自合理"这件事本身。
    expect(resolveKeepRecording(), isTrue);
    expect(resolveAlsoRecordDuringSystemAsr(), isFalse);
  });

  group('DreamEntry.copyWith 能真的清掉 audioPath', () {
    final base = DreamEntry(
      id: '20260921-1400',
      recordedAt: DateTime(2026, 9, 21, 14, 0),
      transcript: '我梦见在一条很长的走廊里走，走廊尽头有扇门',
      audioPath: '/tmp/a.wav',
      rawTranscript: '我梦见在一条很长的走廊里走，走廊尽头有扇门',
    );

    test('clearAudioPath: true 把 audioPath 置空', () {
      // 这是「删录音、留文字」唯一可行的写法：`copyWith(audioPath: null)` 会被
      // `?? this.audioPath` 吃掉，记录会继续声称自己有音频（界面照旧显示能回听），
      // 而文件其实已经删了。
      final cleared = base.copyWith(clearAudioPath: true);
      expect(cleared.audioPath, isNull);
      expect(cleared.transcript, base.transcript, reason: '文字必须原样保留');
      expect(cleared.id, base.id);
      expect(cleared.recordedAt, base.recordedAt);
    });

    test('不传 clearAudioPath 时 audioPath 保持不动', () {
      expect(base.copyWith(transcript: '改过的原文').audioPath, '/tmp/a.wav');
    });

    test('可以换成新路径', () {
      expect(base.copyWith(audioPath: '/tmp/b.wav').audioPath, '/tmp/b.wav');
    });

    test('清空与赋值同时给时，以清空为准', () {
      expect(
        base.copyWith(audioPath: '/tmp/b.wav', clearAudioPath: true).audioPath,
        isNull,
      );
    });

    test('本来就带 null 的 audioPath 清空后还是 null，不出错', () {
      final noAudio = base.copyWith(clearAudioPath: true).copyWith(clearAudioPath: true);
      expect(noAudio.audioPath, isNull);
    });
  });
}

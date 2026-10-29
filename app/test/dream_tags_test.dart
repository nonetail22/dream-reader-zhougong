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
import 'package:dream_reader/services/dream_tags.dart';
import 'package:test/test.dart';

/// 结构化标签的单测。
///
/// 为什么值得为"几个枚举值"写这么多测试：标签**会进 user prompt**，
/// 而 user prompt 是解析输入指纹的一部分。于是这里的每一个规范化动作都直接决定
/// 两件事——模型看到什么、以及"用户点重新解析有没有意义"判得对不对。
/// 一个没被挡住的脏 id 会让模型读到一段看不懂的东西，还不会报任何错。
void main() {
  group('取选项与文案', () {
    test('已知 id 能取到中文；未知 / 空 / null 一律返回 null', () {
      expect(DreamTags.moodLabel('calm'), '平静');
      expect(DreamTags.moodLabel('uneasy'), '不安');
      expect(DreamTags.moodLabel('nope'), isNull);
      expect(DreamTags.moodLabel(''), isNull);
      expect(DreamTags.moodLabel(null), isNull);
      // 空白也要当"没有"，否则 prompt 里会多出一个空的标签项
      expect(DreamTags.moodLabel('   '), isNull);
    });

    test('flagLabels 逐项翻译，未知 id 直接丢掉而不是原样显示', () {
      expect(
        DreamTags.flagLabels(['nightmare', 'recurring']),
        ['噩梦', '反复出现的梦'],
      );
      // 把 `zzz` 显示给用户毫无意义——它只可能来自手改过的配置文件
      expect(DreamTags.flagLabels(['nightmare', 'zzz']), ['噩梦']);
      expect(DreamTags.flagLabels(const []), isEmpty);
    });
  });

  group('规范化：把任意脏数据收敛成已知取值', () {
    test('normalizeMood 只放行已知 id', () {
      expect(DreamTags.normalizeMood('sad'), 'sad');
      expect(DreamTags.normalizeMood('sad '), 'sad', reason: '首尾空白不该让合法值失效');
      expect(DreamTags.normalizeMood('unknown'), isNull);
      expect(DreamTags.normalizeMood(''), isNull);
      expect(DreamTags.normalizeMood(null), isNull);
      // 手改 JSON 可能把数字/对象塞进来，绝不能让它变成 "123" 这种 id
      expect(DreamTags.normalizeMood(123), isNull);
      expect(DreamTags.normalizeMood({'a': 1}), isNull);
    });

    test('normalizeFlags 过滤未知、去重、并按声明顺序排序', () {
      expect(DreamTags.normalizeFlags(['recurring', 'nightmare']), [
        'nightmare',
        'recurring',
      ]);
      expect(
        DreamTags.normalizeFlags(['recurring', 'nightmare', 'nightmare']),
        ['nightmare', 'recurring'],
        reason: '同一组标签只有一种落盘形态，否则点选顺序会让 JSON 无谓地不同',
      );
      expect(DreamTags.normalizeFlags(['zzz', '', '  ']), isEmpty);
    });

    test('normalizeFlags 对"根本不是数组"的输入返回空，而不是抛异常', () {
      // 老版本 / 手改过的 JSON 里这个键可能是任何东西。
      // 这里一旦抛异常，整个记录列表都读不出来——而它只是少了个标签。
      expect(DreamTags.normalizeFlags(null), isEmpty);
      expect(DreamTags.normalizeFlags('nightmare'), isEmpty);
      expect(DreamTags.normalizeFlags(42), isEmpty);
      expect(DreamTags.normalizeFlags({'a': 'nightmare'}), isEmpty);
    });
  });

  group('isEmpty：决定界面显不显示标签、prompt 加不加那一行', () {
    test('什么都没打', () {
      expect(DreamTags.isEmpty(), isTrue);
      expect(DreamTags.isEmpty(mood: null), isTrue);
      expect(DreamTags.isEmpty(mood: ''), isTrue);
      expect(DreamTags.isEmpty(flags: const []), isTrue);
      // 未知 id 不算"打过标签"——它进不了 prompt，界面上也显示不出来
      expect(DreamTags.isEmpty(flags: const ['zzz']), isTrue);
    });

    test('打了任意一项就不算空', () {
      expect(DreamTags.isEmpty(mood: 'calm'), isFalse);
      expect(DreamTags.isEmpty(flags: const ['nightmare']), isFalse);
    });
  });

  group('promptLine：拼给模型的那一行', () {
    test('没有标签时返回空串（调用方据此整行不输出）', () {
      expect(DreamTags.promptLine(), '');
      expect(DreamTags.promptLine(mood: ''), '');
      expect(DreamTags.promptLine(mood: 'nope'), '');
      expect(DreamTags.promptLine(flags: const ['zzz']), '');
    });

    test('说的是中文标签，不是落盘用的 ASCII id', () {
      final line = DreamTags.promptLine(mood: 'uneasy', flags: const ['recurring']);
      // 模型读的是人话；把 `uneasy` 这种内部 id 喂给它等于让它猜
      expect(line, contains('不安'));
      expect(line, contains('反复出现的梦'));
      expect(line, isNot(contains('uneasy')));
      expect(line, isNot(contains('recurring')));
    });

    test('必须声明"这是用户说的事实"，并且不得被当成梦境原文引用', () {
      final line = DreamTags.promptLine(mood: 'calm');
      // 用户标的是事实（"我当时就是平静"），模型推的是假设——两者分量不同，
      // 不写清楚模型会拿它去顶替 evidence，而 evidence 必须逐字来自原文。
      expect(line, contains('事实而非推断'));
      expect(line, contains('不得当作梦境原文引用'));
    });

    test('标签之间的分隔与顺序稳定（同一组输入只有一种形态）', () {
      final a = DreamTags.promptLine(mood: 'calm', flags: const ['recurring', 'nightmare']);
      final b = DreamTags.promptLine(mood: 'calm', flags: const ['nightmare', 'recurring']);
      expect(a, b);
    });
  });

  group('DreamEntry 落盘 / 读盘', () {
    DreamEntry entry({String? mood, List<String> flags = const []}) => DreamEntry(
          id: '20260923-0700',
          recordedAt: DateTime(2026, 9, 23, 7),
          transcript: '我梦见自己在飞。',
          mood: mood,
          flags: flags,
        );

    test('JSON 往返保留 mood 与 flags', () {
      final e = entry(mood: 'joyful', flags: const ['recurring', 'nightmare']);
      final back = DreamEntry.fromJsonString(e.toJsonString());
      expect(back.mood, 'joyful');
      expect(back.flags, ['nightmare', 'recurring']);
      expect(back.moodLabel, '喜悦');
      expect(back.flagLabels, ['噩梦', '反复出现的梦']);
      expect(back.hasTags, isTrue);
    });

    test('★ 老版本 JSON（没有这两个键）读进来是"没打过标签"', () {
      // 这个断言钉的是 README 第九节第 25 条：新增字段必须对老数据宽容，
      // 且 null 的语义必须**等于老数据本该有的行为**——老记录没标签，
      // 就不该凭空显示任何标签、prompt 里也不该多出那一行。
      final legacy = <String, dynamic>{
        'id': '20260901-0700',
        'recorded_at': DateTime(2026, 9, 1, 7).toIso8601String(),
        'transcript': '我梦见自己在飞。',
        'status': 'analyzed',
        // 刻意不含 mood / flags
      };
      final back = DreamEntry.fromJson(legacy);
      expect(back.mood, isNull);
      expect(back.flags, isEmpty);
      expect(back.moodLabel, isNull);
      expect(back.flagLabels, isEmpty);
      expect(back.hasTags, isFalse);
      // 原文本身必须完好——不能因为缺新字段就把老记录弄坏
      expect(back.transcript, '我梦见自己在飞。');
    });

    test('脏 id 在读盘时就被挡掉，不会流到界面与 prompt', () {
      final dirty = <String, dynamic>{
        'id': '20260901-0700',
        'recorded_at': DateTime(2026, 9, 1, 7).toIso8601String(),
        'transcript': 'x',
        'mood': 'zzz_not_a_mood',
        'flags': ['nightmare', 'zzz'],
      };
      final back = DreamEntry.fromJson(dirty);
      expect(back.mood, isNull);
      expect(back.flags, ['nightmare']);
    });

    test('copyWith 不带参数时不动标签', () {
      final e = entry(mood: 'sad', flags: const ['nightmare']);
      final next = e.copyWith(transcript: '改了原文');
      expect(next.mood, 'sad');
      expect(next.flags, ['nightmare']);
    });

    test('★ clearMood 能真的把 mood 清成 null（`??` 语义清不掉）', () {
      // 不给这个开关时，`mood ?? this.mood` 遇到 null 只会保留旧值——
      // 用户会发现"标签点掉了却还在"，而且不报错。
      final e = entry(mood: 'sad', flags: const ['nightmare']);
      expect(e.copyWith(mood: null).mood, 'sad', reason: '不带开关时确实清不掉');
      expect(e.copyWith(clearMood: true).mood, isNull);
      // 清 mood 不该连带清 flags
      expect(e.copyWith(clearMood: true).flags, ['nightmare']);
    });

    test('flags 传空列表就能清空（不需要额外的 clear 开关）', () {
      final e = entry(mood: 'sad', flags: const ['nightmare', 'recurring']);
      expect(e.copyWith(flags: const []).flags, isEmpty);
      expect(e.copyWith(flags: const []).mood, 'sad', reason: '清标签不该连带清情绪');
    });
  });
}

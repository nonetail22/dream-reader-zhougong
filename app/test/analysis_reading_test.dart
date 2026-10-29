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
import 'package:test/test.dart';

/// v1.1.0「白话层 / 术语桥 / 提问层」的读取契约，以及**老记录的降级**。
///
/// 背景：用户反馈「我没看懂这里面解析写的是什么」。修法有两半——
/// 框架侧要求模型先给白话结论（见 prompt_builder_test 的 v1.1.0 契约），
/// 界面侧则必须把白话放在主路径、把机制与术语收进折叠区。
/// 本文件钉住后半段的**数据契约**。
///
/// 最要紧的一组是「老记录」：框架升级之后，历史记录里没有 reading、没有 point。
/// 界面**必须仍然读得出来**——降级要能读，不能变空白，也不能崩。
void main() {
  DreamEntry entry(Map<String, dynamic>? analysis) => DreamEntry(
        id: '20260922-0712',
        recordedAt: DateTime(2026, 9, 22, 7, 12),
        transcript: '我梦见在一条很长的走廊里跑，后面有人跟着。',
        analysis: analysis,
      );

  /// v1.1.0 之后的输出
  const readingV11 = <String, dynamic>{
    'reading': {
      'headline': '这个梦大概和"被推着往前走、又没法停"的感觉有关',
      'mood': '紧绷里带着一点不甘',
    },
    'analysis_layer': [
      {
        'point': '梦里的走廊像是"没得选、只能往前"的那种感觉。',
        'content': '多个隐意汇入单一显象，走廊同时承载了时间压力与不可逆。',
        'theory': 'T1-凝缩',
        'confidence': 'B',
        'evidence': '一条很长的走廊',
      },
      {
        'point': '追你的人更像一种压力，而不是某个具体的人。',
        'content': '情感重心从重要对象转移到次要对象。',
        'theory': 'T1-移置',
        'confidence': 'C',
        'evidence': '后面有人跟着',
      },
    ],
    'terms': [
      {'term': '凝缩', 'plain': '把好几件事压进同一个画面里。'},
      {'term': '移置', 'plain': '把情绪的分量从要紧的人和事上挪到旁边去。'},
    ],
    'open_questions': [
      {
        'question': '最近有没有被期限或进度追着走的感觉？',
        'why': '这决定了它是最近的事，还是长期的议题。',
      },
    ],
    'advice_layer': ['下次记录时补一句醒后最先想到什么。'],
    'limitations_note': '单梦信息有限，本结论为初步假设。',
    'safety_flag': 'none',
  };

  /// v1.0.x 的老记录：没有 reading / point / terms / open_questions
  const readingV10 = <String, dynamic>{
    'analysis_layer': [
      {
        'theory': 'T1-移置',
        'confidence': 'B',
        'content': '情感重心从重要对象转移到次要对象。',
        'evidence': '后面有人跟着',
      },
    ],
    'advice_layer': ['留意最近是否有悬而未决的决定。'],
    'limitations_note': '仅凭单次记录无法定论。',
    'safety_flag': 'none',
  };

  group('v1.1.0 记录：白话层可直接读', () {
    test('主结论与情绪基调都在', () {
      final e = entry(readingV11);
      expect(e.hasPlainReading, isTrue);
      expect(e.readingHeadline, contains('被推着往前走'));
      expect(e.readingMood, '紧绷里带着一点不甘');
    });

    test('每条结论都有一句人话，且与展开论述分开', () {
      final items = entry(readingV11).analysisItems;
      expect(items, hasLength(2));
      expect(items[0].hasPlainPoint, isTrue);
      expect(items[0].plain, '梦里的走廊像是"没得选、只能往前"的那种感觉。');
      // point 与 content 是两个字段：point 给人读，content 给想深究的人查
      expect(items[0].content, contains('隐意'));
      expect(items[0].plain, isNot(contains('隐意')));
    });

    test('机制名与置信度各自独立可取（界面把它们放在不同层）', () {
      final items = entry(readingV11).analysisItems;
      expect(items[0].theory, 'T1-凝缩');
      expect(items[0].normalizedConfidence, 'B');
      expect(items[1].normalizedConfidence, 'C');
    });

    test('术语与解释成对取出', () {
      final terms = entry(readingV11).terms;
      expect(terms, hasLength(2));
      expect(terms.first.term, '凝缩');
      expect(terms.first.plain, contains('压进同一个画面'));
    });

    test('提问带「补上它能判断什么」', () {
      final qs = entry(readingV11).openQuestions;
      expect(qs, hasLength(1));
      expect(qs.first.question, contains('期限'));
      expect(qs.first.why, contains('长期'));
    });
  });

  group('★ 老记录降级：能读，不能空白', () {
    test('没有白话层时不崩，只是没有主结论卡', () {
      final e = entry(readingV10);
      expect(e.hasPlainReading, isFalse);
      expect(e.readingHeadline, isEmpty);
      expect(e.readingMood, isEmpty);
    });

    test('没有 point 时回退到 content —— 术语味但读得下去', () {
      final item = entry(readingV10).analysisItems.single;
      expect(item.hasPlainPoint, isFalse);
      expect(item.plain, '情感重心从重要对象转移到次要对象。');
      expect(item.plain, item.content, reason: '回退到 content 而不是空串');
      // 折叠区不要再重复显示一遍同样的文字
      expect(item.theory, 'T1-移置');
    });

    test('老记录没有 terms / open_questions → 空列表，不是 null 崩溃', () {
      final e = entry(readingV10);
      expect(e.terms, isEmpty);
      expect(e.openQuestions, isEmpty);
    });

    test('完全没有解析记录时（analysis 为 null）全部安全降级', () {
      final e = entry(null);
      expect(e.hasPlainReading, isFalse);
      expect(e.analysisItems, isEmpty);
      expect(e.terms, isEmpty);
      expect(e.openQuestions, isEmpty);
      expect(e.advice, isEmpty);
      expect(e.limitationsNote, isEmpty);
      expect(e.safetyFlag, 'none');
    });
  });

  group('脏数据不能把界面弄崩', () {
    test('字段类型不对时当空处理，不抛异常', () {
      final e = entry(const {
        'reading': '这里本该是个对象',
        'analysis_layer': '这里本该是个数组',
        'terms': 42,
        'open_questions': {'question': '写成对象了'},
      });
      expect(e.readingHeadline, isEmpty);
      expect(e.analysisItems, isEmpty);
      expect(e.terms, isEmpty);
      expect(e.openQuestions, isEmpty);
    });

    test('point 是空白字符串 → 回退到 content（不能显示成一片空白）', () {
      final e = entry(const {
        'analysis_layer': [
          {'point': '   ', 'content': '有内容但没人话版。', 'theory': 'T1', 'confidence': 'A'},
        ],
      });
      final item = e.analysisItems.single;
      expect(item.hasPlainPoint, isFalse);
      expect(item.plain, '有内容但没人话版。');
    });

    test('缺少 term 或 plain 的术语条目被丢掉（半截数据只会做出点了没反应的折叠项）', () {
      final e = entry(const {
        'terms': [
          {'term': '凝缩', 'plain': '把好几件事压成一个画面。'},
          {'term': '移置'},
          {'plain': '只有解释没有术语'},
          {'term': '', 'plain': '术语是空的'},
        ],
      });
      expect(e.terms, hasLength(1));
      expect(e.terms.single.term, '凝缩');
    });

    test('open_questions 只要求问题非空，why 可缺失', () {
      final e = entry(const {
        'open_questions': [
          {'question': '最近睡得怎么样？'},
          {'why': '只有理由没有问题的要丢掉'},
          {'question': '', 'why': '问题空的也要丢掉'},
        ],
      });
      expect(e.openQuestions, hasLength(1));
      expect(e.openQuestions.single.question, '最近睡得怎么样？');
      expect(e.openQuestions.single.why, isEmpty);
    });

    test('置信度取值不在枚举内一律按 C 处理（不能显示成空白标签）', () {
      final e = entry(const {
        'analysis_layer': [
          {'point': 'a', 'confidence': 'X'},
          {'point': 'b', 'confidence': ''},
          {'point': 'c', 'confidence': 'a'},
        ],
      });
      final items = e.analysisItems;
      expect(items[0].normalizedConfidence, 'C');
      expect(items[1].normalizedConfidence, 'C');
      // 小写 a 也要认（模型偶发小写）
      expect(items[2].normalizedConfidence, 'A');
    });
  });

  test('新字段随 JSON 一起落盘、读回来还在', () {
    final e = entry(readingV11);
    final back = DreamEntry.fromJsonString(e.toJsonString());
    expect(back.readingHeadline, e.readingHeadline);
    expect(back.readingMood, e.readingMood);
    expect(back.analysisItems.first.plain, e.analysisItems.first.plain);
    expect(back.terms.first.plain, e.terms.first.plain);
    expect(back.openQuestions.first.question, e.openQuestions.first.question);
  });
}

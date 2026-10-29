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

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dream_reader/services/audio_chunker.dart';
import 'package:test/test.dart';

/// 「长录音分段解码」的规划层测试。
///
/// 根因回顾：Paraformer 整段解码超过 ~40s 中段崩坏（56s 实验复现，
/// 表现为"说了很多、识别出来很少"）。分段器负责把长录音在**停顿处**
/// 切成 ≤20s 的短段。这里钉住它的三条硬性质：
/// ① 每段都不超上限；② 各段无缝覆盖全部采样（不丢、不重）；
/// ③ 有停顿时切在停顿里，绝不把有声段劈开。
void main() {
  const int rate = 16000;

  /// 一段"有人说话"的替身：150Hz 方波（有基音、有能量）。
  Float32List speech(int n) {
    final out = Float32List(n);
    const period = 107; // ≈150Hz
    for (var i = 0; i < n; i++) {
      out[i] = (i % period) < (period ~/ 2) ? 0.28 : -0.28;
    }
    return out;
  }

  Float32List concat(List<Float32List> parts) {
    final total = parts.fold<int>(0, (a, b) => a + b.length);
    final out = Float32List(total);
    var at = 0;
    for (final p in parts) {
      out.setAll(at, p);
      at += p.length;
    }
    return out;
  }

  group('planChunks：基础性质', () {
    test('空输入 → 空列表', () {
      expect(planChunks(Float32List(0), rate), isEmpty);
    });

    test('短输入（≤20s）→ 单段，覆盖全部采样', () {
      const n = rate * 19; // 19s
      final ranges = planChunks(Float32List(n), rate);
      expect(ranges.length, 1);
      expect(ranges.first.start, 0);
      expect(ranges.first.end, n);
    });

    test('长输入：每段 ≤ 上限，且无缝覆盖、不重不漏', () {
      const n = rate * 90; // 90s 连续信号（最坏情况：没有停顿可挑）
      final ranges = planChunks(speech(n), rate);
      expect(ranges.length, greaterThanOrEqualTo(5));
      var covered = 0;
      var prevEnd = 0;
      for (final r in ranges) {
        expect(r.start, prevEnd, reason: '段与段必须首尾相接，不丢不重');
        expect(r.length, lessThanOrEqualTo(rate * kChunkMaxMs ~/ 1000));
        covered += r.length;
        prevEnd = r.end;
      }
      expect(covered, n);
      expect(prevEnd, n);
    });

    test('8kHz 历史录音同样适用（帧长按采样率折算）', () {
      const rate8 = 8000;
      final ranges = planChunks(speech(rate8 * 60), rate8); // 60s @8k
      expect(ranges.length, greaterThanOrEqualTo(3));
      for (final r in ranges) {
        expect(r.length, lessThanOrEqualTo(rate8 * kChunkMaxMs ~/ 1000));
      }
    });
  });

  group('planChunks：切点必须落在停顿里', () {
    test('「说话+停顿」交替的长录音，切点都落在静音区', () {
      // 6.5s 一个周期：5.5s 说话 + 1s 静音，共 45.5s（7 个周期）。
      // 目标切点 12s 附近的窗口 [10s,14s] 必然与 [12.0,13.0) 的静音相交。
      final parts = <Float32List>[];
      for (var c = 0; c < 7; c++) {
        parts.add(speech(rate * 55 ~/ 10));
        parts.add(Float32List(rate)); // 1s 纯静音
      }
      final samples = concat(parts);
      final ranges = planChunks(samples, rate);

      expect(ranges.length, greaterThanOrEqualTo(3));
      const frameLen = rate * 20 ~/ 1000;
      for (final r in ranges.sublist(0, ranges.length - 1)) {
        // 每个段末（=下一个切点）所在的帧必须是纯静音：
        // 切点选的是最低能量帧的起点，那一帧整体落在静音里。
        final at = r.end;
        for (var i = at; i < math.min(at + frameLen, samples.length); i++) {
          expect(samples[i], 0.0, reason: '切点 $at 落在了有声区里');
        }
      }
    });

    test('完全连续无停顿的输入也能切（回落到最低能量点，不死循环）', () {
      const n = rate * 60;
      final ranges = planChunks(speech(n), rate);
      expect(ranges.length, greaterThanOrEqualTo(3));
      expect(ranges.fold<int>(0, (a, r) => a + r.length), n);
    });
  });

  group('joinTranscripts：分段文字拼接', () {
    test('中文段直接相连，不插空格', () {
      expect(joinTranscripts(['今天梦见', '了一条河']), '今天梦见了一条河');
    });

    test('两侧都是英文字母/数字时补空格（切点可能落在英文句中间）', () {
      expect(joinTranscripts(['i had a night', 'mare about rain']),
          'i had a night mare about rain');
      expect(joinTranscripts(['score 12', '3 points']), 'score 12 3 points');
    });

    test('中英混排：只在字母贴字母的边界补空格', () {
      expect(joinTranscripts(['梦见 hello', 'world 逃跑']), '梦见 hello world 逃跑');
    });

    test('空段丢弃，全空返回空串', () {
      expect(joinTranscripts(['', '  ', '梦', '']), '梦');
      expect(joinTranscripts(['', ' ']), '');
    });

    test('单段就是它自己（trim 后）', () {
      expect(joinTranscripts(['  你好 ']), '你好');
    });
  });
}

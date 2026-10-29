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

import 'package:flutter_test/flutter_test.dart';

import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/dream_repository.dart';

/// 0.5.7 修复：同一天录了多段梦境，注入解析的「历史梦境摘要」必须按日历日分组，
/// 同日多条归到同一日期标题下，并显式声明「同日期＝同一天多段」，否则模型会把
/// 同一天的多段梦误判成「不同日期的梦」→ 解析结论错写成「连续多天的梦境」。
void main() {
  // 时钟必须注入：下面这些 2026-09-28 的记录，拿真实 DateTime.now() 过滤
  // 会在 14 天后全部落窗外、buildDigest 返回空串（0.5.7 的定时炸弹，
  // 2026-10-27 爆）。固定 now 让测试与日期无关。
  final fixedNow = DateTime(2026, 9, 28, 23, 59);

  group('buildDigest 同日分组', () {
    final sameDayA =
        DreamEntry(id: '20260928-0800', recordedAt: DateTime(2026, 9, 28, 8, 0), transcript: '梦到在河边走');
    final sameDayB =
        DreamEntry(id: '20260928-2300', recordedAt: DateTime(2026, 9, 28, 23, 0), transcript: '又梦到同一条河');
    final prevDay =
        DreamEntry(id: '20260927-2200', recordedAt: DateTime(2026, 9, 27, 22, 0), transcript: '梦到山');

    test('无记录时返回空串', () {
      expect(buildDigest([]), '');
    });

    test('同一天多条归到同一日期标题、并带说明', () {
      final out =
          buildDigest([sameDayA, sameDayB, prevDay], days: 14, now: fixedNow);
      // 开头的声明
      expect(out, contains('同一天记录的多段梦境'));
      expect(out, contains('请勿当作不同日期'));
      // 两个同一天标题 + 各自段数
      expect(out, contains('【2026-09-28】当日 2 段梦境：'));
      expect(out, contains('【2026-09-27】当日 1 段梦境：'));
      // 两条同日梦境都在 09-28 标题下、且在 09-27 标题之前
      final idx28 = out.indexOf('【2026-09-28】');
      final idxA = out.indexOf('梦到在河边走');
      final idxB = out.indexOf('又梦到同一条河');
      final idx27 = out.indexOf('【2026-09-27】');
      expect(idx28, lessThan(idxA));
      expect(idxA, lessThan(idxB));
      expect(idxB, lessThan(idx27));
      expect(out, contains('梦到山'));
    });

    test('excludeId 生效（解析自身不进摘要）', () {
      final out = buildDigest([sameDayA, sameDayB],
          excludeId: '20260928-0800', now: fixedNow);
      expect(out, isNot(contains('梦到在河边走')));
      expect(out, contains('又梦到同一条河'));
    });

    test('非 rich 模式保持最简格式（不受影响）', () {
      final out =
          buildDigest([sameDayA, sameDayB], rich: false, now: fixedNow);
      expect(out, contains('- 20260928-0800：梦到在河边走'));
      expect(out, contains('- 20260928-2300：又梦到同一条河'));
      expect(out, isNot(contains('当日')));
    });
  });
}

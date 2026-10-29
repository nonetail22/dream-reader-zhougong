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

// 用**真实模型输出**回归 App 侧 JsonRepair。
//
// 为什么必须有这个脚本（而不只是单测里内联一段坏字符串）：
//   json_repair_test.dart 里内联的坏样本是"我抄进去的"，抄的时候容易顺手修好；
//   而真正要防的故障是 validation/preview 里落盘的**原始**输出文件。这个脚本直接
//   吃那个文件，所以"复测通过"这句话是对着同一个字节序列说的，不是对着我的转述。
//
// 用法:
//   tool/f.sh dart tool/verify_repair.dart <raw-*.json>
//   退出码 0 = 修复成功（或本来就是合法 JSON）；1 = 修不好，App 会抛给用户。
//
// 期望：
//   - out-v1.1.1/raw-glm-5.3-answered3.json  → 修复成功，且 actions 含 escape_interior_quotes
//   - 任何合法 JSON                            → 修复成功，且 actions 为空（恒等变换）
import 'dart:io';

import 'package:dream_reader/services/json_repair.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: tool/f.sh dart tool/verify_repair.dart <raw-*.json>');
    exit(2);
  }
  var bad = 0;
  for (final p in args) {
    final f = File(p);
    if (!f.existsSync()) {
      stderr.writeln('✗ 文件不存在: $p');
      bad++;
      continue;
    }
    final raw = f.readAsStringSync();
    final (obj, fixes) = JsonRepair.parseLoose(raw);
    final name = p.split('/').last;
    if (obj == null) {
      stdout.writeln('✗ $name  修不好（App 会给用户报错）  actions=$fixes');
      bad++;
    } else {
      final keys = obj.keys.take(6).join(',');
      stdout.writeln('✓ $name  ${raw.length} 字符 → ${fixes.isEmpty ? "无需修复（本来就是合法 JSON）" : fixes.join(" → ")}');
      stdout.writeln('    顶层键: $keys');
    }
  }
  exit(bad == 0 ? 0 : 1);
}

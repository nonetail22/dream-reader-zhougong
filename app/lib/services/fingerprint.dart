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

import 'dart:convert';

/// 解析输入指纹：把「这次解析用到的全部输入」压成一个短字符串。
///
/// 用途只有一个——判断**重新解析到底会不会得到别的东西**：
/// 指纹一致，说明模型看到的输入一字未改，重解析只是再花一次钱；
/// 指纹不一致，说明原文 / 近期状态 / 模型 / 框架文档 / 最近梦境摘要里
/// 至少有一项变了，那次重解析才有意义。
///
/// 为什么不引 `crypto` 算 sha256：
/// 1. 这里判的是"输入是否相同"，不是安全用途，不需要抗碰撞攻击；
/// 2. 更要紧的是**跨编译目标的一致性**。本工程有 web 验证目标，而 dart2js 里
///    `<<` `>>` `^` 都按 **32 位有符号整数**执行、超过 2^53 的乘法会丢精度。
///    标准 FNV-1a 64 会在这条路上悄悄算错——而指纹是要**落盘**的：
///    同一份输入在 VM 上和 web 上算出不同值，落盘的指纹就会永远对不上，
///    表现为"明明什么都没改，界面却说输入变了"。
///    所以下面全部用 `%` 和 `~/` 做算术（不碰位运算的宽度陷阱），
///    把每一步都压在 2^53 以内。
///
/// 输出 16 位十六进制：两个不同初始基的 31 位哈希拼接，够日常用了。
String inputFingerprint(String s) {
  final a = _hash31(s, 0x811c9dc5);
  final b = _hash31(s, 0x01000193);
  return '${a.toRadixString(16).padLeft(8, '0')}'
      '${b.toRadixString(16).padLeft(8, '0')}';
}

/// 由若干个字段拼出一个指纹。
///
/// 用 `\u001f`（ASCII 单元分隔符）而不是 `\n` 或空格来连接：文本内容里可能
/// 出现换行和空格，用它们连接会让 `("a", "b c")` 与 `("a b", "c")` 撞成同一个
/// 指纹；而控制字符不会出现在口述转写里。
String joinFingerprint(Iterable<String> parts) =>
    inputFingerprint(parts.join('\u001f'));

const int _mod = 2147483648; // 2^31

/// 31 位乘法滚动哈希（FNV-1a 的结构，模数收到 2^31）。
///
/// 取 2^31 而不是 2^32 的原因：值始终 < 2^31，`^` 在 dart2js 下就不会落到
/// int32 的负数区间（负数会让后面 `%` 得到负值，整个哈希就废了）。
int _hash31(String s, int basis) {
  var h = basis % _mod;
  for (final byte in utf8.encode(s)) {
    h = h ^ byte;
    // h * 16777619 mod 2^31，把 h 拆成高低 16 位分别乘：
    //   lo * 16777619 ≤ 65535 * 16777619        ≈ 1.1e12  < 2^53 ✓
    //   hi * 16777619 ≤ 32767 * 16777619        ≈ 5.5e11  < 2^53 ✓
    //   ((hi * 16777619) % 32768) * 65536       ≈ 2.1e9   < 2^53 ✓
    // 直接写 h * 16777619 在 dart2js 上会溢出精度，所以必须这样拆开。
    final lo = h % 65536;
    final hi = h ~/ 65536;
    h = (lo * 16777619 + ((hi * 16777619) % 32768) * 65536) % _mod;
  }
  return h;
}

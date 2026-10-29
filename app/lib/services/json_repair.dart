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

/// JSON 修复/重试层（第 0 步验证暴露的工程点：轻量模型偶发 JSON 手滑）
///
/// 职责：把模型返回的文本尽量变成合法 JSON 对象。修复策略按「小到大」逐级尝试，
/// 每一步都记录修复动作，便于观测模型的坏习惯（回归数据）。
class JsonRepair {
  /// 返回 (parsedObject, appliedFixes)。全部失败时 parsedObject 为 null。
  static (Map<String, dynamic>?, List<String>) parseLoose(String raw) {
    final fixes = <String>[];

    // 1) 基础清洗：去代码围栏、去首尾空白
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*\n?'), '');
      text = text.replaceFirst(RegExp(r'\n?```\s*$'), '');
      fixes.add('strip_code_fence');
    }
    text = text.trim();

    // 2) 直接解析
    var obj = _try(text);
    if (obj != null) return (obj, fixes);

    // 3) 截取首个平衡的 {...} 块（模型可能在 JSON 前后夹带解释文字）
    final block = _firstJsonObject(text);
    if (block != null && block != text) {
      obj = _try(block);
      if (obj != null) {
        fixes.add('extract_first_object');
        return (obj, fixes);
      }
      text = block;
      fixes.add('extract_first_object');
    }

    // 4) 字符串内的**未转义双引号**（真实故障，见 json_repair_test 的夹具）：
    //    模型按框架要求"引用用户原话"时，会把用户输入里的半角引号**原样搬进 JSON 值**，
    //    整份输出因此不可解析——用户等了十几分钟却什么都拿不到。
    //    判定：字符串内遇到的 "，若其后第一个非空白字符不是 , : } ] 或已到末尾，
    //    说明它是**内容**而不是分隔符 → 转义为 \"。
    //    关键性质：这个变换对**合法 JSON 是恒等变换**（合法 JSON 里内容引号必然已转义），
    //    所以可以安全地"先试再说"——它只可能改进非法输入，不可能弄坏合法输入。
    //    顺带补一个"从首个 { 起截断"的兜底：夹带前言的坏输出常与串内引号同时出现。
    var braceBase = text;
    if (!braceBase.startsWith('{')) {
      final i = braceBase.indexOf('{');
      if (i >= 0) braceBase = braceBase.substring(i);
    }
    final quoteFixed = _escapeInteriorQuotes(braceBase);
    final quoteFixes = <String>[
      if (quoteFixed != braceBase) 'escape_interior_quotes',
      if (braceBase != text) 'truncate_to_first_brace',
    ];
    if (quoteFixes.isNotEmpty) {
      obj = _try(quoteFixed);
      if (obj != null) {
        fixes.addAll(quoteFixes);
        return (obj, fixes);
      }
      text = quoteFixed;
      fixes.addAll(quoteFixes);
    }

    // 5) 去尾随逗号
    // 注意：Dart 的 String.replaceAll 不解析替换串中的 $1（与 JS 不同），
    // 必须用 replaceAllMapped 取分组，否则会把 JSON 改坏（已被 json_repair_test 捕获）。
    final noTrailingComma = text
        .replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1) ?? '');
    if (noTrailingComma != text) {
      obj = _try(noTrailingComma);
      if (obj != null) {
        fixes.add('remove_trailing_comma');
        return (obj, fixes);
      }
      text = noTrailingComma;
      fixes.add('remove_trailing_comma');
    }

    // 6) 单引号手滑：字符串以 ' 收尾（应为 "），如 「验证。'」+ 换行
    final fixedQuote = text.replaceAllMapped(RegExp(r"'(\s*[,\}\]])"), (m) => '"${m.group(1)}');
    if (fixedQuote != text) {
      obj = _try(fixedQuote);
      if (obj != null) {
        fixes.add('fix_quote_slip');
        return (obj, fixes);
      }
      text = fixedQuote;
      fixes.add('fix_quote_slip');
    }

    // 7) 字符串内的裸换行/制表符（非法控制字符）转义
    final escaped = _escapeRawControlCharsInStrings(text);
    if (escaped != text) {
      obj = _try(escaped);
      if (obj != null) {
        fixes.add('escape_control_chars');
        return (obj, fixes);
      }
      fixes.add('escape_control_chars');
    }

    return (null, fixes);
  }

  static Map<String, dynamic>? _try(String s) {
    try {
      final v = jsonDecode(s);
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 从文本中提取第一个花括号平衡的片段（跳过字符串内的花括号）
  static String? _firstJsonObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
      } else {
        if (c == '"') {
          inString = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) return s.substring(start, i + 1);
        }
      }
    }
    return null; // 未闭合（截断）
  }

  /// 把字符串字面量内部**未转义**的双引号转义掉。
  ///
  /// 判定"这个 `"` 是分隔符还是内容"：看它后面第一个非空白字符。
  /// 是 `,` `:` `}` `]`（或已到字符串末尾）→ 正常收尾；否则 → 它是内容引号，转义它。
  ///
  /// **对合法 JSON 是恒等变换**：合法 JSON 里内容引号必然已经写成 `\"`，
  /// 而每个真正的收尾引号后面必然跟着 `,:}]` 之一或文本结束。所以这个函数
  /// 只可能改变非法输入，见 `json_repair_test.dart` 里那条"恒等变换"测试。
  static String _escapeInteriorQuotes(String s) {
    final sb = StringBuffer();
    var inString = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (!inString) {
        if (c == '"') inString = true;
        sb.write(c);
        continue;
      }
      // 已在字符串内
      if (c == r'\') {
        // 已转义序列原样带过，避免把 \" 误判成收尾
        sb.write(c);
        if (i + 1 < s.length) {
          sb.write(s[i + 1]);
          i++;
        }
        continue;
      }
      if (c == '"') {
        var j = i + 1;
        while (j < s.length) {
          final w = s[j];
          if (w == ' ' || w == '\n' || w == '\r' || w == '\t') {
            j++;
          } else {
            break;
          }
        }
        final atEnd = j >= s.length;
        final next = atEnd ? '' : s[j];
        final closes = atEnd || next == ',' || next == ':' || next == '}' || next == ']';
        if (closes) {
          inString = false;
          sb.write(c);
        } else {
          sb.write(r'\"');
        }
        continue;
      }
      sb.write(c);
    }
    return sb.toString();
  }

  /// 把字符串字面量内部的裸换行/制表符替换为转义序列
  static String _escapeRawControlCharsInStrings(String s) {
    final sb = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
          sb.write(c);
        } else if (c == r'\') {
          escaped = true;
          sb.write(c);
        } else if (c == '"') {
          inString = false;
          sb.write(c);
        } else if (c == '\n') {
          sb.write(r'\n');
        } else if (c == '\r') {
          sb.write(r'\r');
        } else if (c == '\t') {
          sb.write(r'\t');
        } else {
          sb.write(c);
        }
      } else {
        if (c == '"') inString = true;
        sb.write(c);
      }
    }
    return sb.toString();
  }
}

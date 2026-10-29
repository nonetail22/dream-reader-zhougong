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

import 'package:dream_reader/services/json_repair.dart';
import 'package:test/test.dart';

/// JSON 修复层测试。用例直接取自第 0 步真实模型输出的坏样本特征
/// （validation/outputs_step0/），保证修复能力对真实故障有效。
///
/// 纯 Dart 逻辑（json_repair.dart 只依赖 dart:convert），用 `dart test` 运行。
void main() {
  test('干净的 JSON 直接解析，无修复动作', () {
    final (obj, fixes) = JsonRepair.parseLoose('{"a": 1, "b": "x"}');
    expect(obj, isNotNull);
    expect(obj!['a'], 1);
    expect(fixes, isEmpty);
  });

  test('剥离 markdown 代码围栏', () {
    final (obj, fixes) =
        JsonRepair.parseLoose('```json\n{"dream_id": "20260920-0712"}\n```');
    expect(obj, isNotNull);
    expect(fixes, contains('strip_code_fence'));
  });

  test('截取夹带解释文字中的首个 JSON 对象', () {
    final (obj, fixes) =
        JsonRepair.parseLoose('好的，以下是解析结果：\n{"safety_flag": "none"}\n希望有帮助。');
    expect(obj, isNotNull);
    expect(obj!['safety_flag'], 'none');
    expect(fixes, contains('extract_first_object'));
  });

  test('去除尾随逗号', () {
    final (obj, fixes) = JsonRepair.parseLoose('{"a": [1, 2, ], }');
    expect(obj, isNotNull);
    expect(fixes, contains('remove_trailing_comma'));
  });

  test('修复引号手滑（真实故障：DeepSeek 用单引号闭合字符串）', () {
    // 复刻第 0 步 sample_D 的真实坏输出形态
    const bad = '{\n'
        '  "safety_flag": "none",\n'
        '  "limitations_note": "单梦信息有限，本结论为初步假设，需结合后续梦境进一步验证。\'\n'
        '}';
    final (obj, fixes) = JsonRepair.parseLoose(bad);
    expect(obj, isNotNull, reason: '引号手滑应可被修复');
    expect(obj!['safety_flag'], 'none');
    expect(obj['limitations_note'].toString(), contains('初步假设'));
    expect(fixes, contains('fix_quote_slip'));
  });

  test('转义字符串内的裸换行（非法控制字符）', () {
    const bad = '{"content": "第一行\n第二行"}';
    final (obj, fixes) = JsonRepair.parseLoose(bad);
    expect(obj, isNotNull);
    expect(obj!['content'], contains('第一行'));
    expect(fixes, contains('escape_control_chars'));
  });

  test('修复字符串内未转义的引号（真实故障：glm-5.3 引用用户原话时把半角引号搬进 JSON）', () {
    // 夹具逐字取自第四轮多轮闭环实测的 glm-5.3 answered3 输出
    // （validation/preview/out-v1.1.1/raw-glm-5.3-answered3.json 第 37~38 行）。
    // 触发条件极普通：用户在「补充说明」里打了**半角双引号**，框架又要求模型
    // 「引用用户原话」，模型便把这些引号原样带进了自己的 JSON 值 → 整份输出不可解析，
    // 而那一轮模型跑了 724 秒、20.78 credit，用户最终什么都拿不到。
    const bad = '{\n'
        '  "dream_id": "2026-09-22",\n'
        '  "day_residue": [\n'
        '    "上周卖掉住了十年的老房子、搬空全部物品（梦的地点是"小时候住的那个老房子"）",\n'
        '    "收拾旧物时翻出很多小时候的东西（用户联想：桌上"别人的东西"最先想到未拆封、说不清归属的纸箱）"\n'
        '  ]\n'
        '}';
    final (obj, fixes) = JsonRepair.parseLoose(bad);
    expect(obj, isNotNull, reason: '串内未转义引号应可被修复');
    expect(fixes, contains('escape_interior_quotes'));
    expect(obj!['dream_id'], '2026-09-22');
    final residue = (obj['day_residue'] as List).cast<String>();
    expect(residue, hasLength(2));
    expect(residue[0], contains('"小时候住的那个老房子"'),
        reason: '转义后引号仍应作为内容保留，而不是被吃掉');
    expect(residue[1], contains('"别人的东西"'));
  });

  test('串内引号修复对合法 JSON 是恒等变换（不得改动、不得报修复）', () {
    // 这条策略之所以能"先试再说"，全靠这个性质：合法 JSON 里内容引号必然已转义，
    // 且每个收尾引号后面必然是 , : } ] 之一或文本结束。用几种容易踩的合法写法钉住它。
    const cases = [
      '{"a": "b"}',
      '{"a":"b","c":"d"}',
      '{"content": "他说\\"你好\\"就走了"}',
      '{"t": "结尾是引号\\""}',
      '{"empty": ""}',
      r'{"s": "含 ] 和 } 和 , 的值"}',
      '{"a": [], "b": {}}',
    ];
    for (final c in cases) {
      final (obj, fixes) = JsonRepair.parseLoose(c);
      expect(obj, isNotNull, reason: '合法 JSON 必须能解析：$c');
      expect(fixes, isEmpty, reason: '合法 JSON 不该触发任何修复：$c');
    }
  });

  test('串内引号紧邻收尾引号时也能救（"他说"好""）', () {
    const bad = '{"point": "他说"好""}';
    final (obj, fixes) = JsonRepair.parseLoose(bad);
    expect(obj, isNotNull);
    expect(fixes, contains('escape_interior_quotes'));
    expect(obj!['point'], '他说"好"');
  });

  test('彻底损坏的输入返回 null 且不抛异常', () {
    final (obj, fixes) = JsonRepair.parseLoose('这不是 JSON，只是一段散文。');
    expect(obj, isNull);
    expect(fixes, isA<List<String>>());
  });

  test('未闭合的截断 JSON 返回 null（交由重试层处理，不臆造内容）', () {
    const truncated = '{"coding_layer": {"characters": [{"name": "梦者';
    final (obj, _) = JsonRepair.parseLoose(truncated);
    expect(obj, isNull);
  });
}

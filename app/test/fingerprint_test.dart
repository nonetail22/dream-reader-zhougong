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

import 'package:dream_reader/services/fingerprint.dart';
import 'package:test/test.dart';

/// 输入指纹的单测。
///
/// 为什么值得为一个小哈希写测试：它是**落盘**的。用户库里每条记录都存着一个
/// 指纹，将来拿它和新算的值比对——所以实现一旦悄悄变了，旧指纹就全部对不上，
/// 表现为"明明什么都没改，界面却说输入变了"。下面既有 golden 也有性质测试，
/// 后面那种改动会当场被抓住。
void main() {
  group('golden：钉住算法本身', () {
    // 空串 = 两个初始基各自模 2^31 的结果。
    // 这一条同时验证了"模数确实生效"：0x811c9dc5 落在 [2^31, 2^32) 内，
    // 若忘了取模，这里会输出 811c9dc5 而不是 011c9dc5。
    test('空串', () {
      expect(inputFingerprint(''), '011c9dc501000193');
    });

    // 非空串必须有自己的 golden：空串走不到循环体，而循环里的
    // "把乘法拆成高低 16 位"才是这段代码最容易写错的地方。
    test('短串', () {
      expect(inputFingerprint('a'), '640c292c05030ff6');
      expect(inputFingerprint('ab'), '4d2505ca77d185fc');
    });

    test('真实量级的长文本（约 17.6K 字符，贴近 system prompt）', () {
      final big = '你是一名基于精神分析理论体系的梦境解析助手。' * 800;
      expect(big.length, 17600);
      expect(inputFingerprint(big), '6ee8b7c546055593');
    });
  });

  group('性质：确定性', () {
    test('同一输入反复算都是同一个值', () {
      const s = '我梦见在一条很长的走廊里跑。';
      expect(inputFingerprint(s), '2ccf3fc610cb82cc');
      expect(inputFingerprint(s), inputFingerprint(s));
    });

    test('长文本重复算也稳定', () {
      final big = '你是一名基于精神分析理论体系的梦境解析助手。' * 800;
      expect(inputFingerprint(big), inputFingerprint(big));
    });
  });

  group('性质：一处变化必须被发现', () {
    test('改一个字符就变', () {
      expect(inputFingerprint('ab'), isNot(inputFingerprint('ac')));
    });

    test('末尾多一个字符就变', () {
      final big = '你是一名基于精神分析理论体系的梦境解析助手。' * 800;
      expect(inputFingerprint('${big}x'), isNot(inputFingerprint(big)));
    });

    test('顺序敏感：ab|ba 不同', () {
      expect(inputFingerprint('ab'), isNot(inputFingerprint('ba')));
    });
  });

  group('joinFingerprint：分隔符必须防歧义', () {
    // 用 \n 或空格连接的话，("ab","c") 与 ("a","bc") 会拼成同一个字符串，
    // 两个语义完全不同的输入就会撞成同一个指纹。
    test('分段方式不同则指纹不同', () {
      expect(joinFingerprint(['ab', 'c']), '4fa0af441d83e74e');
      expect(joinFingerprint(['a', 'bc']), '5ae696962607e4b8');
      expect(
        joinFingerprint(['ab', 'c']),
        isNot(joinFingerprint(['a', 'bc'])),
      );
    });

    test('含换行/空格的文本也不会与相邻字段边界混淆', () {
      expect(
        joinFingerprint(['a b', 'c']),
        isNot(joinFingerprint(['a', 'b c'])),
      );
    });

    test('字段个数不同则指纹不同', () {
      expect(joinFingerprint(['a', 'b']), isNot(joinFingerprint(['a', 'b', ''])));
    });
  });

  test('输出恒为 16 位小写十六进制', () {
    for (final s in ['', 'a', '梦境', '你是一名基于精神分析理论体系的助手' * 40]) {
      expect(inputFingerprint(s), matches(RegExp(r'^[0-9a-f]{16}$')));
    }
  });
}

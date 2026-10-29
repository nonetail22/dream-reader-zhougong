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

import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/l10n/messages.dart';
import 'package:test/test.dart';

/// 文案表的三语完整性契约。
///
/// 为什么值得单独钉住：`AppL10n.tr` 在缺 key 时会**回落到简体中文，再缺则原样
/// 返回 key** —— 这是个"不会崩"的兜底，但也意味着**漏翻不会报错**，只会让用户
/// 在某一种语言下看到中文、甚至看到 `nav_record` 这样的 key 名。编译器一个字都
/// 不会提醒。所以必须有测试把三张表的键集钉成完全相同。
///
/// 只依赖纯逻辑（`app_locale.dart` + `messages.dart`，均不 import Flutter），
/// 因此 `dart test` 直接可跑，不需要 flutter_tester。
void main() {
  const locales = AppLocale.values;

  test('三张文案表的键集完全相同（漏一条就会在界面上露出 key 名）', () {
    final base = l10nKeysOf(AppLocale.zhCN);
    expect(base, isNotEmpty);
    for (final l in locales) {
      final keys = l10nKeysOf(l);
      final missing = base.difference(keys);
      final extra = keys.difference(base);
      expect(missing, isEmpty, reason: '${l.id} 缺少这些 key：${missing.toList()..sort()}');
      expect(extra, isEmpty, reason: '${l.id} 多出这些 key（其它语言没有）：${extra.toList()..sort()}');
    }
  });

  test('每条文案都非空，且 tr() 不会把 key 原样吐出来', () {
    for (final l in locales) {
      final l10n = AppL10n(l);
      for (final key in l10nKeysOf(l)) {
        final v = l10n.tr(key);
        expect(v.trim(), isNotEmpty, reason: '${l.id} 的 $key 是空的');
        expect(v, isNot(key), reason: '${l.id} 的 $key 没有被翻译（原样返回了 key）');
      }
    }
  });

  test('缺失 key 原样返回 key（绝不抛异常）', () {
    const en = AppL10n(AppLocale.en);
    expect(en.tr('__不存在的_key__'), '__不存在的_key__');
  });

  test('占位符按名替换', () {
    const zh = AppL10n(AppLocale.zhCN);
    final s = zh.tr('ready_cloud', {'endpoint': 'https://x/v1'});
    expect(s, contains('https://x/v1'));
    expect(s, isNot(contains('{endpoint}')));

    const en = AppL10n(AppLocale.en);
    final e = en.tr('usage_files', {'total': '10 MB', 'count': '3'});
    expect(e, contains('10 MB'));
    expect(e, contains('3'));
    expect(e, isNot(contains('{')));
  });

  test('AppLocale 落盘键稳定：id == 枚举名（改了就丢用户已选语言）', () {
    expect(AppLocale.zhCN.id, 'zhCN');
    expect(AppLocale.zhTW.id, 'zhTW');
    expect(AppLocale.en.id, 'en');
  });

  test('未知落盘值回落简体中文，不抛异常', () {
    expect(AppLocaleX.fromId('klingon'), AppLocale.zhCN);
    expect(AppLocaleX.fromId(''), AppLocale.zhCN);
    expect(AppLocaleX.fromId(null), AppLocale.zhCN);
    expect(AppLocaleX.fromId('en'), AppLocale.en);
    expect(AppLocaleX.fromId('zhTW'), AppLocale.zhTW);
  });

  test('解析语言指令：简体不加指令（null，避免改动历史指纹），繁体/英文各有一句', () {
    expect(AppLocale.zhCN.analysisLanguageDirective, isNull);
    expect(AppLocale.zhTW.analysisLanguageDirective, isNotNull);
    expect(AppLocale.en.analysisLanguageDirective, isNotNull);
    expect(AppLocale.en.analysisLanguageDirective, contains('English'));
  });
}

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

// 「跟随系统」配色（0.7.5）回归。
//
// 钉四条性质：
// 1. 解析映射：跟随系统 + 系统深色 → 暖棕烛光；浅色 → 浅色。
// 2. 固定方案原样透传（不随系统亮度变）。
// 3. 落盘键 'system' 能被 fromId 读回来（新装老数据兼容口径）。
// 4. 设置页出现「跟随系统」选项卡，点选后立即生效并落盘。
// ignore_for_file: prefer_const_constructors
import 'package:dream_reader/app_state.dart';
import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/l10n/app_localizations.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/theme/palettes.dart';
import 'package:dream_reader/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('解析映射：跟随系统按系统亮度取案', () {
    expect(
      resolveDreamPalette(DreamPalette.systemFollow, Brightness.dark),
      DreamPalette.warmAmber,
    );
    expect(
      resolveDreamPalette(DreamPalette.systemFollow, Brightness.light),
      DreamPalette.dawn,
    );
  });

  test('固定方案原样透传，不受系统亮度影响', () {
    for (final p in DreamPalette.values) {
      if (p == DreamPalette.systemFollow) continue;
      expect(resolveDreamPalette(p, Brightness.dark), p);
      expect(resolveDreamPalette(p, Brightness.light), p);
    }
  });

  test('解析后喂给 buildDreamTheme 的一定是有真实颜色的方案', () {
    final dark = buildDreamTheme(
        resolveDreamPalette(DreamPalette.systemFollow, Brightness.dark));
    expect(dark.brightness, Brightness.dark);
    // 暖棕烛光的标志性底色
    expect(dark.scaffoldBackgroundColor, DreamPalette.warmAmber.background);

    final light = buildDreamTheme(
        resolveDreamPalette(DreamPalette.systemFollow, Brightness.light));
    expect(light.brightness, Brightness.light);
  });

  test("落盘键 'system' 能被 fromId 读回（未知 id 仍回落默认）", () {
    expect(DreamPalette.fromId('system'), DreamPalette.systemFollow);
    expect(DreamPalette.fromId('warm_amber'), DreamPalette.warmAmber);
    // 老版本存的固定 id 不受新枚举值影响
    expect(DreamPalette.fromId('dawn'), DreamPalette.dawn);
    expect(DreamPalette.fromId('no_such_palette'), DreamPalette.fallback);
  });

  testWidgets('设置页出现「跟随系统」选项卡，点选后生效并落盘', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = AppController(
      repository: InMemoryDreamRepository(),
      settings: SettingsService(),
      analysis: AnalysisService(
          llm: LlmClient(), promptBuilder: PromptBuilder('dummy')),
    );
    await tester.pumpWidget(AppScope(
      notifier: c,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppLocale.values.map((e) => e.flutterLocale).toList(),
        localizationsDelegates: const [
          AppL10nDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: SettingsPage()),
      ),
    ));
    await tester.pumpAndSettle();

    // 「配色」组默认折叠：先展开
    await tester.tap(find.text('夜间配色'));
    await tester.pumpAndSettle();

    expect(find.text('跟随系统'), findsOneWidget);
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();

    expect(c.palette, DreamPalette.systemFollow);
    final saved =
        (await SharedPreferences.getInstance()).getString('night_palette');
    expect(saved, 'system');
  });
}

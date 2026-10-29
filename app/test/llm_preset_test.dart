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

// 「模型 API · 解析用」的**供应商预设下拉**（0.7.4）回归。
//
// 覆盖三条性质：
// 1. 已配置的 Base URL+模型 与预设吻合时，下拉显示对应供应商；
// 2. 选预设 → Base URL/模型自动填充，**旧 API Key 被清空**（换供应商 =
//    换 Key 归属，留着旧 Key 会造成"以为用了新家"的困惑）；
// 3. 列表里有「自定义」；手改输入框后下拉自动回落到「自定义」。
// ignore_for_file: prefer_const_constructors
import 'package:dream_reader/app_state.dart';
import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/l10n/app_localizations.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppController> _controllerWithDeepSeek() async {
  final c = AppController(
    repository: InMemoryDreamRepository(),
    settings: SettingsService(),
    analysis: AnalysisService(llm: LlmClient(), promptBuilder: PromptBuilder('dummy')),
  );
  // 与预设表里的 DeepSeek 完全一致 → 下拉应显示 DeepSeek
  c.config = const LlmConfig(
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'sk-old-key',
    model: 'deepseek-chat',
  );
  return c;
}

/// 「模型 API · 解析用」组默认折叠（ExpansionTile collapsed，children 处于
/// offstage，find.text 默认跳过 offstage）——先展开再操作下拉。
Future<void> _expandModelGroup(WidgetTester tester) async {
  await tester.tap(find.text('模型 API · 解析用'));
  await tester.pumpAndSettle();
}

Future<void> _pumpSettings(WidgetTester tester, AppController c) async {
  await tester.pumpWidget(AppScope(
    notifier: c,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
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
}

TextField _fieldByLabel(WidgetTester tester, String label) {
  return tester
      .widgetList<TextField>(find.byType(TextField))
      .firstWhere((f) => f.decoration?.labelText == label);
}

Future<void> _fillField(
    WidgetTester tester, String label, String text) async {
  final field = _fieldByLabel(tester, label);
  await tester.enterText(find.byWidget(field), text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('与 DeepSeek 预设吻合 → 下拉显示 DeepSeek；列表含自定义', (tester) async {
    await _pumpSettings(tester, await _controllerWithDeepSeek());
    await _expandModelGroup(tester);

    // 当前值显示 DeepSeek（下拉收起状态出现一次）
    expect(find.text('DeepSeek'), findsOneWidget);
    // 列表里能选到「自定义」等项
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('通义千问（百炼）'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    // 关掉菜单
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('选预设 → URL/模型自动填充、旧 Key 清空、保存生效', (tester) async {
    final c = await _controllerWithDeepSeek();
    await _pumpSettings(tester, c);
    await _expandModelGroup(tester);

    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通义千问（百炼）').last);
    await tester.pumpAndSettle();


    // URL 与模型已按预设填充
    final baseUrl = _fieldByLabel(tester, 'Base URL');
    expect(baseUrl.controller!.text, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
    final model = _fieldByLabel(tester, '模型名');
    expect(model.controller!.text, 'qwen-plus');

    // 保存生效，且旧 Key 已被清空（换供应商不再沿用旧 Key）
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(c.config.baseUrl, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
    expect(c.config.model, 'qwen-plus');
    expect(c.config.apiKey, isEmpty);
  });

  testWidgets('手改输入框 → 下拉回落「自定义」', (tester) async {
    await _pumpSettings(tester, await _controllerWithDeepSeek());
    await _expandModelGroup(tester);

    await _fillField(tester, 'Base URL', 'https://my-proxy.example.com/v1');
    await tester.pumpAndSettle();

    // 不再匹配 DeepSeek → 显示「自定义」
    expect(find.text('DeepSeek'), findsNothing);
    expect(find.text('自定义'), findsOneWidget);
  });
}

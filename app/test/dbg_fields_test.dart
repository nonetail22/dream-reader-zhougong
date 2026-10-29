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

void main() {
  testWidgets('dump labels', (tester) async {
    final c = AppController(
      repository: InMemoryDreamRepository(),
      settings: SettingsService(),
      analysis: AnalysisService(llm: LlmClient(), promptBuilder: PromptBuilder('dummy')),
    );
    c.config = const LlmConfig(baseUrl: 'https://api.deepseek.com/v1', apiKey: 'sk-old-key', model: 'deepseek-chat');
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
    await tester.tap(find.text('模型 API · 解析用'));
    await tester.pumpAndSettle();
    for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
      debugPrint('label=${f.decoration?.labelText} hint=${f.decoration?.hintText}');
    }
  });
}

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

// 梦境时间线的**状态筛选**与**关键字搜索**（0.7.3）回归。
//
// 覆盖三条性质：
// 1. 五档筛选的口径互斥且符合直觉（失败/过期优先归入强特征档）；
// 2. 搜索只搜梦的内容（transcript/rawTranscript），大小写不敏感；
// 3. 筛选与搜索可叠加，滤空时给"没有符合条件的记录"而不是白屏。
// ignore_for_file: prefer_const_constructors
import 'package:dream_reader/app_state.dart';
import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/l10n/app_localizations.dart';
import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/ui/timeline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 种一批覆盖四种状态的记录：
/// A 未解析 / B 已解析 / C 结论过期（analyzedTranscript ≠ transcript）/
/// D 解析失败。
Future<AppController> _seed() async {
  final repo = InMemoryDreamRepository();
  await repo.save(DreamEntry(
    id: '20260901-0800',
    recordedAt: DateTime(2026, 9, 1, 8),
    transcript: '梦见会飞的鱼',
    status: 'recorded',
  ));
  await repo.save(DreamEntry(
    id: '20260902-0800',
    recordedAt: DateTime(2026, 9, 2, 8),
    transcript: '梦见考试迟到',
    status: 'analyzed',
    analysis: {'headline': '考试焦虑'},
    analyzedTranscript: '梦见考试迟到',
  ));
  await repo.save(DreamEntry(
    id: '20260903-0800',
    recordedAt: DateTime(2026, 9, 3, 8),
    transcript: '梦见掉牙了',
    status: 'analyzed',
    analysis: {'headline': '不安'},
    analyzedTranscript: '梦见掉牙齿了', // 原文后来改过 → 过期
  ));
  await repo.save(DreamEntry(
    id: '20260904-0800',
    recordedAt: DateTime(2026, 9, 4, 8),
    transcript: '梦见大海',
    status: 'failed',
  ));
  final c = AppController(
    repository: repo,
    settings: SettingsService(),
    analysis: AnalysisService(llm: LlmClient(), promptBuilder: PromptBuilder('dummy')),
  );
  await c.refresh();
  return c;
}

Future<void> _pumpTimeline(WidgetTester tester, AppController c) async {
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
      home: const Scaffold(body: TimelinePage()),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 期望列表里恰好有这些条目（transcript 原文逐一核对）。
void _expectExactly(List<String> transcripts) {
  for (final t in [
    '梦见会飞的鱼',
    '梦见考试迟到',
    '梦见掉牙了',
    '梦见大海',
  ]) {
    expect(find.text(t), transcripts.contains(t) ? findsOneWidget : findsNothing,
        reason: '期望只显示 $transcripts，但「$t」的可见性不对');
  }
}

void main() {
  testWidgets('默认「全部」：五种状态全部可见', (tester) async {
    await _pumpTimeline(tester, await _seed());
    _expectExactly([
      '梦见会飞的鱼',
      '梦见考试迟到',
      '梦见掉牙了',
      '梦见大海',
    ]);
  });

  testWidgets('五档筛选各自只显示对应口径的记录', (tester) async {
    await _pumpTimeline(tester, await _seed());

    await tester.tap(find.widgetWithText(ChoiceChip, '未解析'));
    await tester.pumpAndSettle();
    _expectExactly(['梦见会飞的鱼']);

    await tester.tap(find.widgetWithText(ChoiceChip, '已解析'));
    await tester.pumpAndSettle();
    _expectExactly(['梦见考试迟到']);

    await tester.tap(find.widgetWithText(ChoiceChip, '结论过期'));
    await tester.pumpAndSettle();
    _expectExactly(['梦见掉牙了']);

    await tester.tap(find.widgetWithText(ChoiceChip, '解析失败'));
    await tester.pumpAndSettle();
    _expectExactly(['梦见大海']);
  });

  testWidgets('关键字搜索只搜梦的内容，大小写不敏感', (tester) async {
    await _pumpTimeline(tester, await _seed());

    await tester.enterText(find.byType(TextField), '会飞');
    await tester.pumpAndSettle();
    _expectExactly(['梦见会飞的鱼']);

    // 识别原始输出也能搜到（rawTranscript）
    await tester.enterText(find.byType(TextField), '大海');
    await tester.pumpAndSettle();
    _expectExactly(['梦见大海']);

    // 清空恢复全部
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    _expectExactly([
      '梦见会飞的鱼',
      '梦见考试迟到',
      '梦见掉牙了',
      '梦见大海',
    ]);
  });

  testWidgets('筛选与搜索叠加；滤空时给明确提示而不是白屏', (tester) async {
    await _pumpTimeline(tester, await _seed());

    await tester.tap(find.widgetWithText(ChoiceChip, '解析失败'));
    await tester.enterText(find.byType(TextField), '考试');
    await tester.pumpAndSettle();

    // 失败的记录里没有"考试" → 滤空提示
    expect(find.textContaining('没有符合条件的记录'), findsOneWidget);

    // 换成"大海"（正是那条失败记录）→ 恢复显示
    await tester.enterText(find.byType(TextField), '大海');
    await tester.pumpAndSettle();
    _expectExactly(['梦见大海']);
  });
}

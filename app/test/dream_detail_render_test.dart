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
import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/theme/palettes.dart';
import 'package:dream_reader/ui/dream_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一份最小可渲染的解析结果。
Map<String, dynamic> _analysis() => {
      'reading': {'headline': '这个梦可能在说：你在找一扇通向外面的窗', 'mood': '平静中带着一点不安'},
      'analysis_layer': [
        {
          'point': '走廊与关着的门像一种被围住的感觉',
          'content': '展开论述……',
          'theory': '凝缩',
          'confidence': 'A',
          'evidence': '走廊尽头有一扇窗',
        },
      ],
      'terms': [],
      'open_questions': [],
      'advice_layer': [],
      'limitations_note': '',
      'safety_flag': 'none',
      'no_more_questions': true,
    };

DreamEntry _entry({required String id, String status = 'recorded', Map<String, dynamic>? analysis, String? analysisError}) =>
    DreamEntry(
      id: id,
      recordedAt: DateTime(2026, 9, 21, 18, 44),
      transcript: '我梦见自己站在一条很长的走廊里，两侧的门都是关着的。',
      status: status,
      analysis: analysis,
      analysisError: analysisError,
    );

Widget _app(AppController c, String entryId) => AppScope(
      notifier: c,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: c.locale.flutterLocale,
          supportedLocales: AppLocale.values.map((e) => e.flutterLocale).toList(),
          localizationsDelegates: const [
            AppL10nDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildDreamTheme(c.palette),
          home: DreamDetailPage(entryId: entryId),
        ),
      ),
    );

Future<AppController> _controllerWith(DreamEntry e) async {
  final repo = InMemoryDreamRepository();
  await repo.save(e);
  final c = AppController(
    repository: repo,
    settings: SettingsService(),
    analysis: AnalysisService(llm: LlmClient(), promptBuilder: PromptBuilder('dummy')),
  );
  await c.refresh();
  return c;
}

void main() {
  testWidgets('status=parsing：显示"正在解析"卡与说明，而不是裸转圈或 CTA', (tester) async {
    final e = _entry(id: 'p1', status: 'parsing');
    final c = await _controllerWith(e);
    await tester.pumpWidget(_app(c, e.id));
    await tester.pump();

    expect(find.text('正在解析…'), findsOneWidget);
    expect(find.textContaining('1 到 15 分钟'), findsOneWidget);
    // 解析中不该出现"开始解析"按钮，也不该出现结果区
    expect(find.text('开始解析'), findsNothing);
    expect(find.widgetWithText(FilledButton, '开始解析'), findsNothing);
  });

  testWidgets('status=failed 且已有旧结论：显示失败横幅，同时保留旧结论', (tester) async {
    final e = _entry(id: 'f1', status: 'failed', analysis: _analysis(), analysisError: '调用异常：链接被掐断');
    final c = await _controllerWith(e);
    await tester.pumpWidget(_app(c, e.id));
    await tester.pump();

    // 横幅在、且带上了失败原因
    expect(find.textContaining('本次重新解析失败'), findsOneWidget);
    expect(find.textContaining('链接被掐断'), findsOneWidget);
    // 旧结论仍在（白话主结论 headline）
    expect(find.textContaining('你在找一扇通向外面的窗'), findsOneWidget);
    // 不该退回 CTA
    expect(find.text('开始解析'), findsNothing);
  });

  testWidgets('status=analyzed：显示结果，既不显示解析卡也不显示失败横幅', (tester) async {
    final e = _entry(id: 'a1', status: 'analyzed', analysis: _analysis());
    final c = await _controllerWith(e);
    await tester.pumpWidget(_app(c, e.id));
    await tester.pump();

    expect(find.text('正在解析…'), findsNothing);
    expect(find.textContaining('本次重新解析失败'), findsNothing);
    expect(find.textContaining('你在找一扇通向外面的窗'), findsOneWidget);
  });

  testWidgets('status=failed 且无旧结论：显示 CTA + 失败原因', (tester) async {
    final e = _entry(id: 'f2', status: 'failed', analysisError: '第 1 次输出无法解析为 JSON');
    final c = await _controllerWith(e);
    await tester.pumpWidget(_app(c, e.id));
    await tester.pump();

    expect(find.text('开始解析'), findsOneWidget);
    expect(find.textContaining('无法解析为 JSON'), findsOneWidget);
    expect(find.textContaining('本次重新解析失败'), findsNothing);
    expect(find.text('正在解析…'), findsNothing);
  });
}

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

// 本文件验证 0.5.8 的录音→解析流程改动：
// 保存后不再自动解析，而是弹"是否解析"确认框；选"否"跳列表并标亮，
// 选"是"才真正触发解析。
// 0.5.9 起额外验证：录到"没人说话"的音频（静音闸）不应被当成一条梦境存下来。
// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'dart:typed_data';

import 'package:dream_reader/app_state.dart';
import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/l10n/app_localizations.dart';
import 'package:dream_reader/models/dream_entry.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/recorder_service.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/theme/palettes.dart';
import 'package:dream_reader/ui/record_page.dart';
import 'package:dream_reader/ui/timeline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录是否真的被调去解析了（用来证明"保存≠自动解析"）。
class _SpyAnalysis extends AnalysisService {
  _SpyAnalysis(this.outcome)
      : super(llm: LlmClient(), promptBuilder: PromptBuilder('dummy'));
  final AnalysisOutcome outcome;
  int calls = 0;
  @override
  Future<AnalysisOutcome> analyze({
    required LlmConfig config,
    required DreamEntry entry,
    String dreamHistoryDigest = '',
    String? languageDirective,
  }) async {
    calls++;
    return outcome;
  }
}

AppController _controller(InMemoryDreamRepository repo, _SpyAnalysis spy,
    {bool configured = true}) {
  final c = AppController(
    repository: repo,
    settings: SettingsService(),
    analysis: spy,
  );
  if (configured) {
    // localhost 被当作本地模型，isConfigured 无需 apiKey
    c.config = const LlmConfig(
        baseUrl: 'http://localhost:11434', apiKey: '', model: 'local');
  }
  return c;
}

Widget _recordApp(AppController c, void Function(String) onDefer) => AppScope(
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
          home: Scaffold(body: RecordPage(onDeferToTimeline: onDefer)),
        ),
      ),
    );

Widget _timelineApp(AppController c, String? highlightId) => AppScope(
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
          home: Scaffold(body: TimelinePage(highlightId: highlightId)),
        ),
      ),
    );

Future<DreamEntry> _seed(InMemoryDreamRepository repo,
    {String id = '20260928-0800', String transcript = '梦见在飞'}) async {
  final e = DreamEntry(
    id: id,
    recordedAt: DateTime(2026, 9, 28, 8, 0),
    transcript: transcript,
  );
  await repo.save(e);
  return e;
}

void main() {
  group('录音保存后不再自动解析', () {
    testWidgets('手动输入保存后弹出"是否解析"确认框，且未自动解析', (tester) async {
      final repo = InMemoryDreamRepository();
      final spy = _SpyAnalysis(AnalysisOutcome(
          analysis: {'analysis_layer': []}, fingerprint: 'fp'));
      final c = _controller(repo, spy);
      String? deferredId;
      await tester.pumpWidget(_recordApp(c, (id) => deferredId = id));
      await tester.pumpAndSettle();

      // 点「手动输入」
      await tester.tap(find.text('手动输入'));
      await tester.pumpAndSettle();
      // 在弹出的对话框里输入并保存
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '我梦见一片大海');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 关键：确认框出现（不再静默自动解析）
      expect(find.text('是否解析这段梦境？'), findsOneWidget);
      // 解析服务一次都没被调过
      expect(spy.calls, 0);
      // 记录已落盘，但状态仍是 recorded（未解析）
      expect(c.entries.length, 1);
      expect(c.entries.first.status, 'recorded');
      // 还没触发"去列表"回调
      expect(deferredId, isNull);
    });

    testWidgets('选"否，去梦境列表"：不解析，且回调带上这条记录的 id', (tester) async {
      final repo = InMemoryDreamRepository();
      final spy = _SpyAnalysis(
          AnalysisOutcome(analysis: {'analysis_layer': []}, fingerprint: 'fp'));
      final c = _controller(repo, spy);
      String? deferredId;
      await tester.pumpWidget(_recordApp(c, (id) => deferredId = id));
      await tester.pumpAndSettle();

      await tester.tap(find.text('手动输入'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '我梦见一片大海');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 选"否"
      await tester.tap(find.text('否，去梦境列表'));
      await tester.pumpAndSettle();

      // 没解析
      expect(spy.calls, 0);
      // 回调被触发，且传的是刚存的那条的 id
      expect(deferredId, isNotNull);
      expect(deferredId, c.entries.first.id);
    });

    testWidgets('选"是，立即解析"：才真正触发解析', (tester) async {
      final repo = InMemoryDreamRepository();
      final spy = _SpyAnalysis(
          AnalysisOutcome(analysis: {'analysis_layer': []}, fingerprint: 'fp'));
      final c = _controller(repo, spy);
      String? deferredId;
      await tester.pumpWidget(_recordApp(c, (id) => deferredId = id));
      await tester.pumpAndSettle();

      await tester.tap(find.text('手动输入'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '我梦见一片大海');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 选"是"
      await tester.tap(find.text('是，立即解析'));
      await tester.pumpAndSettle();

      // 解析被触发一次
      expect(spy.calls, 1);
      // 状态变为 analyzed
      expect(c.entries.first.status, 'analyzed');
      // 没走"去列表"回调
      expect(deferredId, isNull);
    });

    testWidgets('点空白处关掉确认框：留在记录页、不解析、不跳列表', (tester) async {
      final repo = InMemoryDreamRepository();
      final spy = _SpyAnalysis(
          AnalysisOutcome(analysis: {'analysis_layer': []}, fingerprint: 'fp'));
      final c = _controller(repo, spy);
      String? deferredId;
      await tester.pumpWidget(_recordApp(c, (id) => deferredId = id));
      await tester.pumpAndSettle();

      await tester.tap(find.text('手动输入'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          '我梦见一片大海');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 点遮罩空白处关掉（barrierDismissible）
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(spy.calls, 0);
      expect(deferredId, isNull);
      // 仍可继续编辑：原文框里能看到刚写的内容
      expect(find.text('我梦见一片大海'), findsWidgets);
    });
  });

  group('时间线标亮', () {
    testWidgets('highlightId 对应的那条被标亮（出现引导小圆点）', (tester) async {
      final repo = InMemoryDreamRepository();
      final a = await _seed(repo, id: 'a', transcript: '第一条梦');
      await _seed(repo, id: 'b', transcript: '第二条梦');
      final c = AppController(
        repository: repo,
        settings: SettingsService(),
        analysis: _SpyAnalysis(AnalysisOutcome(analysis: {}, fingerprint: 'fp')),
      );
      await c.refresh();

      await tester.pumpWidget(_timelineApp(c, a.id));
      await tester.pumpAndSettle();

      // 两条原文都在
      expect(find.text('第一条梦'), findsOneWidget);
      expect(find.text('第二条梦'), findsOneWidget);
      // 只有被标亮的那条带引导小圆点
      expect(find.byIcon(Icons.circle), findsOneWidget);
    });

    testWidgets('不传 highlightId 时不做任何标亮', (tester) async {
      final repo = InMemoryDreamRepository();
      await _seed(repo, id: 'a', transcript: '第一条梦');
      await _seed(repo, id: 'b', transcript: '第二条梦');
      final c = AppController(
        repository: repo,
        settings: SettingsService(),
        analysis: _SpyAnalysis(AnalysisOutcome(analysis: {}, fingerprint: 'fp')),
      );
      await c.refresh();

      await tester.pumpWidget(_timelineApp(c, null));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.circle), findsNothing);
    });
  });

  group('0.5.9 静音闸：没说话的录音不能存成梦', () {
    List<int> encU16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
    List<int> encU32(int v) =>
        [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

    /// 一段合法的 16-bit PCM 单声道静音 WAV（全 0 采样）。
    Uint8List buildSilentWav({int seconds = 1, int sampleRate = 16000}) {
      final n = seconds * sampleRate;
      final data = <int>[];
      for (var i = 0; i < n; i++) {
        data.addAll(encU16(0));
      }
      final fmt = <int>[
        ...encU16(1), // PCM
        ...encU16(1), // mono
        ...encU32(sampleRate),
        ...encU32(sampleRate * 2),
        ...encU16(2),
        ...encU16(16),
      ];
      final body = <int>[
        ...'fmt '.codeUnits,
        ...encU32(fmt.length),
        ...fmt,
        ...'data'.codeUnits,
        ...encU32(data.length),
        ...data,
      ];
      return Uint8List.fromList([
        ...'RIFF'.codeUnits,
        ...encU32(36 + data.length),
        ...'WAVE'.codeUnits,
        ...body,
      ]);
    }

    testWidgets('离线路：录到静音不落盘、提示"没听到你说话"', (tester) async {
      final repo = InMemoryDreamRepository();
      final spy = _SpyAnalysis(
          AnalysisOutcome(analysis: {}, fingerprint: 'fp'));
      final c = _controller(repo, spy);

      final dir = Directory.systemTemp.createTempSync('dr_rec_gate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final wav = File('${dir.path}/silent.wav')
        ..writeAsBytesSync(buildSilentWav());
      final rec = FakeRecorderService()..fakePath = wav.path;

      await tester.pumpWidget(AppScope(
        notifier: c,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: c.locale.flutterLocale,
            supportedLocales:
                AppLocale.values.map((e) => e.flutterLocale).toList(),
            localizationsDelegates: const [
              AppL10nDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildDreamTheme(c.palette),
            home: Scaffold(body: RecordPage(recorder: rec)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 点开始（idle → recording）
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // ★ Stopwatch 走的是真实时钟，FakeAsync 的 pump 不动它；
      // 必须在真实时间里等够最短录音时长，否则会先被"太短"那道闸拦下，测不到静音闸。
      // 录音期间那支 1s 的周期计时器在 runAsync（真实时间）里不会触发，不影响。
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 900));
      });
      await tester.pump();

      // 再点结束（recording → 走 _transcribePending → 静音闸）
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ★ 核心：静音录音绝不能被当成一条梦境存下来
      expect(c.entries.length, 0);
      // 且要明确告诉用户"没听到你说话"，而不是静默放过拿去识别
      expect(find.textContaining('没听到你说话'), findsOneWidget);
      // 解析服务自然一次都没被调用
      expect(spy.calls, 0);
    });
  });
}

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

// 本文件是单元测试替身构造集中地，AnalysisOutcome 等字面量不便写成 const，
// 这里整体忽略 prefer_const_constructors（仅为性能建议，不影响正确性）。
// ignore_for_file: prefer_const_constructors
import 'package:dream_reader/app_state.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/models/dream_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个只返回固定结果的解析服务替身，用来隔离 [AppController.analyzeEntry]
/// 自身的状态机（parsing → analyzed / failed），不碰真实网络与框架文档。
class _FakeAnalysis extends AnalysisService {
  _FakeAnalysis(this.outcome)
      : super(llm: LlmClient(), promptBuilder: PromptBuilder('dummy'));

  final AnalysisOutcome outcome;

  @override
  Future<AnalysisOutcome> analyze({
    required LlmConfig config,
    required DreamEntry entry,
    String dreamHistoryDigest = '',
    String? languageDirective,
  }) async =>
      outcome;
}

Future<DreamEntry> _seed(InMemoryDreamRepository repo,
    {String id = '20260928-0800',
    String transcript = '梦见在飞',
    Map<String, dynamic>? analysis,
    String? status,
    String? analysisError}) async {
  final e = DreamEntry(
    id: id,
    recordedAt: DateTime(2026, 9, 28, 8, 0),
    transcript: transcript,
    status: status ?? 'recorded',
    analysis: analysis,
    analysisError: analysisError,
  );
  await repo.save(e); // 走公开 API，不碰私有成员
  return e;
}

AppController _controller(InMemoryDreamRepository repo, AnalysisOutcome outcome,
    {bool configured = true}) {
  final c = AppController(
    repository: repo,
    settings: SettingsService(),
    analysis: _FakeAnalysis(outcome),
  );
  if (configured) {
    // localhost 被当作本地模型，isConfigured 无需 apiKey
    c.config = const LlmConfig(baseUrl: 'http://localhost:11434', apiKey: '', model: 'local');
  }
  return c;
}

void main() {
  group('analyzeEntry 状态机', () {
    test('解析中把记录标记为 parsing（同步部分执行后立即生效）', () async {
      final repo = InMemoryDreamRepository();
      final entry = await _seed(repo);
      final c = _controller(repo,
          AnalysisOutcome(analysis: {'analysis_layer': []}, fingerprint: 'fp'));
      await c.refresh();

      // 调用后、await 前：async 函数已同步跑到第一个 await 之前，
      // _markParsing 已把这条记录设为 parsing。
      final fut = c.analyzeEntry(c.entryById(entry.id)!);
      expect(c.entryById(entry.id)!.status, 'parsing');
      await fut;
    });

    test('成功：status=analyzed，写入 analysis/transcript/fingerprint，清空旧错误', () async {
      final repo = InMemoryDreamRepository();
      final entry = await _seed(repo, analysisError: '上次失败过');
      final c = _controller(repo,
          AnalysisOutcome(analysis: {'analysis_layer': []}, fingerprint: 'fp'));
      await c.refresh();

      final ok = await c.analyzeEntry(c.entryById(entry.id)!);
      expect(ok, isTrue);

      final saved = c.entryById(entry.id)!;
      expect(saved.status, 'analyzed');
      expect(saved.analysis, isNotNull);
      expect(saved.analyzedTranscript, '梦见在飞');
      expect(saved.analyzedFingerprint, 'fp');
      expect(saved.analysisError, isNull);
      // 落地到仓储的也是 analyzed
      final fromDisk = await repo.getById(entry.id);
      expect(fromDisk!.status, 'analyzed');
      expect(fromDisk.analyzedTranscript, '梦见在飞');
    });

    test('失败：保留上一次已有结论，只把 status 翻成 failed 并记下原因', () async {
      final repo = InMemoryDreamRepository();
      final oldAnalysis = {'analysis_layer': [{'plain': '旧结论'}]};
      final entry = await _seed(repo, analysis: oldAnalysis, status: 'analyzed');
      final c = _controller(repo,
          AnalysisOutcome(error: '调用异常：boom', failure: AnalysisFailure.unknown));
      await c.refresh();

      final ok = await c.analyzeEntry(c.entryById(entry.id)!);
      expect(ok, isFalse);

      final saved = c.entryById(entry.id)!;
      expect(saved.status, 'failed');
      expect(saved.analysisError, '调用异常：boom');
      // ★ 旧结论必须还在：一次失败的重新解析不该覆盖掉用户已有的好结论
      expect(saved.analysis, oldAnalysis);
    });

    test('失败（首次解析、无旧结论）：status=failed 且 analysis 为空', () async {
      final repo = InMemoryDreamRepository();
      final entry = await _seed(repo);
      final c = _controller(repo,
          AnalysisOutcome(error: '超时', failure: AnalysisFailure.timeout));
      await c.refresh();

      final ok = await c.analyzeEntry(c.entryById(entry.id)!);
      expect(ok, isFalse);

      final saved = c.entryById(entry.id)!;
      expect(saved.status, 'failed');
      expect(saved.analysis, isNull);
      expect(saved.analysisError, '超时');
    });

    test('未配置模型时直接返回 false，且不改动任何状态', () async {
      final repo = InMemoryDreamRepository();
      final entry = await _seed(repo);
      final c = _controller(repo,
          AnalysisOutcome(analysis: {'analysis_layer': []}), configured: false);
      await c.refresh();

      final ok = await c.analyzeEntry(c.entryById(entry.id)!);
      expect(ok, isFalse);
      expect(c.entryById(entry.id)!.status, 'recorded');
      expect(c.lastError, isNotNull);
    });
  });
}

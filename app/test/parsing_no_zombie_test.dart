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

// 回归 0.5.6 的核心设计保证之一：解析是长耗时操作，且"正在解析"状态只写在内存
// （_markParsing，不落盘）。若解析中途进程被杀——即 repository.save 永远不被调用——
// 落盘记录绝不能残留 'parsing' 僵尸状态，否则用户下次打开会永远看到"解析中"。
//
// 这一不变量目前没有任何自动化测试锁死：analyze_entry_state_test 只断言"调用后内存态
// 立即变成 parsing"，却没断言"崩溃时落盘那份保持干净"。本文件补上这条。
//
// 做法：用一个"在 save 之前就抛异常"的解析替身模拟崩溃，断言
//   1) 崩溃后内存态是 'parsing'（人若还停在 App 里，界面显示"正在解析"卡，符合预期），
//      但仓储里该记录的 status 仍是最初落盘的值，绝不是 'parsing'；
//   2) 模拟 App 重开后从仓储 refresh，内存态也回到初始 status（界面不再卡 parsing）。
import 'package:dream_reader/app_state.dart';
import 'package:dream_reader/services/analysis_service.dart';
import 'package:dream_reader/services/dream_repository.dart';
import 'package:dream_reader/services/llm_client.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:dream_reader/services/settings_service.dart';
import 'package:dream_reader/models/dream_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在 save 之前就抛异常的解析替身，用来模拟"解析中途崩溃"。
class _CrashBeforeSaveAnalysis extends AnalysisService {
  _CrashBeforeSaveAnalysis()
      : super(llm: LlmClient(), promptBuilder: PromptBuilder('dummy'));

  @override
  Future<AnalysisOutcome> analyze({
    required LlmConfig config,
    required DreamEntry entry,
    String dreamHistoryDigest = '',
    String? languageDirective,
  }) async {
    throw StateError('模拟解析中途崩溃（repository.save 之前）');
  }
}

AppController _controller(InMemoryDreamRepository repo) {
  final c = AppController(
    repository: repo,
    settings: SettingsService(),
    analysis: _CrashBeforeSaveAnalysis(),
  );
  // localhost 被当作本地模型，isConfigured 无需 apiKey
  c.config = const LlmConfig(baseUrl: 'http://localhost:11434', apiKey: '', model: 'local');
  return c;
}

void main() {
  group('parsing 不落盘 · 防僵尸', () {
    test('已有结论的老记录：崩溃后落盘仍=analyzed，重开不再卡 parsing', () async {
      final repo = InMemoryDreamRepository();
      final entry = DreamEntry(
        id: '20260928-0900',
        recordedAt: DateTime(2026, 9, 28, 9, 0),
        transcript: '梦见在飞',
        status: 'analyzed',
        analysis: {'analysis_layer': []},
      );
      await repo.save(entry);

      final c = _controller(repo);
      await c.refresh();

      // 触发解析；模拟"在 repository.save 之前崩溃"——save 不会被调用。
      expect(
        () async => c.analyzeEntry(c.entryById(entry.id)!),
        throwsStateError,
      );
      // 内存态此刻是 'parsing'：人若还停在 App 里，界面会显示"正在解析"卡（符合预期）。
      expect(c.entryById(entry.id)!.status, 'parsing');

      // ★ 关键不变量：落盘的那份绝不能是 'parsing'。
      final persisted = await repo.getById(entry.id);
      expect(persisted!.status, isNot('parsing'));
      expect(persisted.status, 'analyzed');

      // 模拟 App 被杀后重开：从仓储重新载入，内存态回到落盘的干净值。
      await c.refresh();
      expect(c.entryById(entry.id)!.status, 'analyzed');
    });

    test('从未解析过的记录：崩溃后落盘仍=recorded，不会变 parsing/failed', () async {
      final repo = InMemoryDreamRepository();
      final entry = DreamEntry(
        id: '20260928-0910',
        recordedAt: DateTime(2026, 9, 28, 9, 10),
        transcript: '记一段梦',
        status: 'recorded',
      );
      await repo.save(entry);

      final c = _controller(repo);
      await c.refresh();

      expect(
        () async => c.analyzeEntry(c.entryById(entry.id)!),
        throwsStateError,
      );
      expect(c.entryById(entry.id)!.status, 'parsing'); // 内存态

      final persisted = await repo.getById(entry.id);
      expect(persisted!.status, isNot(anyOf('parsing', 'failed')));
      expect(persisted.status, 'recorded'); // 落盘干净

      await c.refresh();
      expect(c.entryById(entry.id)!.status, 'recorded');
    });
  });
}

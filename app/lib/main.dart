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

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'home_shell.dart';
import 'l10n/app_locale.dart';
import 'l10n/app_localizations.dart';
import 'services/analysis_service.dart';
import 'services/dream_repository.dart';
import 'services/llm_client.dart';
import 'services/prompt_builder.dart';
import 'services/settings_service.dart';
import 'theme/palettes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final builder = await loadPromptFromAsset();
    final controller = AppController(
      // 必须按平台选实现：web 上没有应用文档目录，文件实现会抛异常
      repository: defaultDreamRepository(),
      settings: SettingsService(),
      analysis: AnalysisService(llm: LlmClient(), promptBuilder: builder),
    );
    await controller.init();
    runApp(DreamReaderApp(controller: controller, promptBuilder: builder));
  } catch (e, st) {
    // 启动期异常若不接住，release 构建就是一片白屏、用户看不到任何信息。
    // 宁可看到一个能读懂的失败页。
    debugPrint('启动失败: $e\n$st');
    runApp(StartupFailureApp(error: '$e'));
  }
}

class DreamReaderApp extends StatelessWidget {
  const DreamReaderApp({super.key, required this.controller, required this.promptBuilder});

  final AppController controller;
  final PromptBuilder promptBuilder;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: controller,
      // 配色选择要即时生效，而 MaterialApp 在 AppScope 之上、拿不到它的通知，
      // 所以这里单独监听一次控制器。主题切换是低频操作，重建成本可忽略。
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MaterialApp(
          title: 'Dream Reader',
          debugShowCheckedModeBanner: false,
          // 界面语言：控制器持有当前 locale，切语言会触发这里重建。
          locale: controller.locale.flutterLocale,
          supportedLocales:
              AppLocale.values.map((e) => e.flutterLocale).toList(),
          localizationsDelegates: const [
            AppL10nDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // 「跟随系统」用 theme + darkTheme + ThemeMode.system 三件套：
          // MaterialApp 自己监听平台亮度，系统深浅切换无需我们手动重建。
          // 固定方案走 ThemeMode.light —— 只用 theme，行为与旧版完全一致。
          theme: buildDreamTheme(
            resolveDreamPalette(controller.palette, Brightness.light),
          ),
          darkTheme: controller.palette == DreamPalette.systemFollow
              ? buildDreamTheme(
                  resolveDreamPalette(controller.palette, Brightness.dark))
              : null,
          themeMode: controller.palette == DreamPalette.systemFollow
              ? ThemeMode.system
              : ThemeMode.light,
          home: const HomeShell(),
        ),
      ),
    );
  }
}

/// 启动阶段失败时的兜底页：把错误原文显示出来，而不是白屏。
///
/// 这一页**不依赖任何启动期状态**（连配色偏好都可能就是失败原因），
/// 所以固定用默认深色方案——本应用的主要场景是凌晨醒来时，错误页不该反过来晃眼。
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildDreamTheme(DreamPalette.fallback),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text('Dream Reader 启动失败',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  const Text(
                    '你的记录没有丢失——它们保存在本机。请把下面的信息反馈给开发者。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(error, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

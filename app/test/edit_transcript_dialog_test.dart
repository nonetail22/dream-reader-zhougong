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

// 编辑原文对话框（`edit_transcript_dialog.dart`）的布局回归。
//
// 0.7.1 用户截图报的 bug：识别文字很长时，输入框（旧实现 maxLines: 12 固定
// 行数）在键盘弹出、可用高度不足的情况下把 AlertDialog 内容区撑穿——文字
// 画出对话框边界、盖住 actions 按钮。修复＝输入框高度按屏高分比封顶 +
// `AlertDialog.scrollable`。本文件用**小视口 + 超长原文**复现当时的条件，
// 钉住两条性质：不溢出（无 RenderFlex 异常）、保存键完整落在屏幕内。
// ignore_for_file: prefer_const_constructors
import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/l10n/app_localizations.dart';
import 'package:dream_reader/ui/edit_transcript_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 打开对话框（await 完成），返回**对话框自己的 Future**（点保存/取消后才完成）。
Future<Future<String?>?> _openWith(WidgetTester tester, String text) async {
  Future<String?>? result;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppLocale.values.map((e) => e.flutterLocale).toList(),
      localizationsDelegates: const [
        AppL10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () {
                result = showEditTranscriptDialog(ctx, text: text);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  // 本地化 delegate 异步加载：首帧可能还没建出 home，先 settle 再 tap
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(result, isNotNull);
  return result;
}

void main() {
  testWidgets('超长原文 + 小视口：不溢出，保存键完整可见且可用', (tester) async {
    // 模拟键盘弹出后的紧张空间：视口只有 500×560。
    tester.view.physicalSize = const Size(500, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 800 个汉字 ≈ 几十条语音识别出来的长度（修复前固定 12 行装不下就溢出）。
    final long = List.filled(80, '梦里回到了小学教室黑板上的字全都看不清').join();

    final dialogFuture = await _openWith(tester, long);

    // 布局没有溢出异常（RenderFlex overflow 在测试里会变成失败）
    expect(tester.takeException(), isNull);

    // 保存键完整落在视口内（修复前它被文字盖住/推出屏外）
    final saveRect = tester.getRect(find.text('保存'));
    expect(saveRect.top, greaterThanOrEqualTo(0));
    expect(saveRect.bottom, lessThanOrEqualTo(560));
    expect(saveRect.left, greaterThanOrEqualTo(0));
    expect(saveRect.right, lessThanOrEqualTo(500));

    // 保存仍可用：点击后返回原文
    await tester.tap(find.text('保存'));
    final result = await dialogFuture;
    expect(result, long);
  });

  testWidgets('短文本行为不变：minLines 起步、保存返回裁剪后的文字', (tester) async {
    tester.view.physicalSize = const Size(500, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dialogFuture = await _openWith(tester, '  今天梦见会飞的鱼  ');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('保存'));
    expect(await dialogFuture, '今天梦见会飞的鱼');
  });
}

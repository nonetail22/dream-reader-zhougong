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

import 'l10n/app_localizations.dart';
import 'ui/record_page.dart';
import 'ui/settings_page.dart';
import 'ui/timeline_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 需要被标亮的记录 id（录音页「否，去梦境列表」时设置）。
  /// 进入时间线时传给它标亮；用户手动切走就清掉，避免过期标亮一直挂着。
  String? _highlightId;

  @override
  Widget build(BuildContext context) {
    final pages = [
      RecordPage(
        // 用户选择「不立即解析」时：切到梦境列表并把这条标亮。
        onDeferToTimeline: (id) => setState(() {
          _highlightId = id;
          _index = 1;
        }),
      ),
      TimelinePage(highlightId: _highlightId),
      const SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _highlightId = null; // 手动切走就清掉标亮
          _index = i;
        }),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.mic_none),
            label: context.l10n.tr('nav_record'),
          ),
          // 0.7.3 去掉了「梦境」角标：它显示的是记录**总量**（只增不减），
          // 与角标「有新东西」的通用语义错位，记录一多就成了永久视觉噪音。
          // 梦境数量在列表里天然可见，不再重复。
          NavigationDestination(
            icon: const Icon(Icons.nightlight_outlined),
            label: context.l10n.tr('nav_dreams'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tune),
            label: context.l10n.tr('nav_settings'),
          ),
        ],
      ),
    );
  }
}

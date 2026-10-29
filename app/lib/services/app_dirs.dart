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

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 本应用自己管的落盘目录 —— **只在这里拼路径**。
///
/// 为什么要收成一个地方：路径一旦散落在多个文件里，"删记录顺手删音频"这种
/// 联动就一定会有人漏掉。这个漏洞真实发生过：`deleteEntry` 只删了 JSON，
/// 音频文件永远留在盘上、再也找不到主人，而界面上看不出任何异常。
///
/// 本文件依赖 `path_provider`（Flutter 插件），所以**不要在这里放可测的逻辑**——
/// 纯逻辑（占用统计、无主识别）放 `audio_store.dart`，那里只 import `dart:io`，
/// 能用 `dart test` 直接跑。
Future<Directory> appAudioDir() => _ensureDir('audio');

/// 梦境记录（一条一个 JSON）。`FileDreamRepository` 默认用它。
Future<Directory> appDreamsDir() => _ensureDir('dreams');

Future<Directory> _ensureDir(String name) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/$name');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

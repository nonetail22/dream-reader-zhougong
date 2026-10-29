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

import 'package:flutter/services.dart' show rootBundle;

import 'prompt_core.dart';

export 'prompt_core.dart';

/// 平台相关的一层壳：从 Flutter 资源包读框架文档，交给纯逻辑的 [PromptBuilder]。
///
/// 之所以拆开：契约测试要能在任何环境（含没有 flutter_tester 的沙箱）跑起来，
/// 纯逻辑放 prompt_core.dart，用 `dart test` 即可验证；只有这一个函数依赖 Flutter。
Future<PromptBuilder> loadPromptFromAsset() async {
  final doc = await rootBundle.loadString(PromptBuilder.assetPath);
  return PromptBuilder(doc);
}

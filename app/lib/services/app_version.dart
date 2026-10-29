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

/// 应用版本号的读取与缓存（0.7.5 起「设置 → 关于」显示）。
///
/// 数据源是 `package_info_plus`（读 Android 的 versionName/versionCode，
/// 即 pubspec 的 `version: 0.7.5+40`）。缓存成单个 Future：多处以版本号
/// 建UI 时不会重复走平台通道。
///
/// **可注入的 loader**：widget 测试里没有平台通道（`PackageInfo.fromPlatform`
/// 会抛 MissingPluginException），测试用 [stub] 塞一个假值即可。
library;

import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  AppVersion._();

  static Future<String>? _cached;

  /// 测试注入点。传 null 恢复默认。
  static Future<String> Function()? stub;

  /// 返回形如 `0.7.5 (40)` 的版本串（versionName + versionCode）。
  static Future<String> load() {
    if (stub != null) return _cached ??= stub!();
    return _cached ??= PackageInfo.fromPlatform()
        .then((p) => '${p.version} (${p.buildNumber})');
  }
}

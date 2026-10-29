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

import 'package:flutter/widgets.dart';

import 'app_locale.dart';
import 'messages.dart';

/// [AppLocale] 与 Flutter [Locale] 的互转。
///
/// 刻意放在这里、而不是 `app_locale.dart`：`Locale` 来自 `dart:ui`，纯 Dart VM
/// 里没有它；把它留在这一层，`app_locale.dart` / `messages.dart` 才能保持纯 Dart、
/// 被 `dart test` 直接跑到。
extension AppLocaleFlutter on AppLocale {
  /// 对应的 Flutter [Locale]。繁体走 `zh_TW`，简体走 `zh_CN`。
  Locale get flutterLocale {
    switch (this) {
      case AppLocale.zhCN:
        return const Locale('zh', 'CN');
      case AppLocale.zhTW:
        return const Locale('zh', 'TW');
      case AppLocale.en:
        return const Locale('en');
    }
  }

  /// 从 Flutter [Locale] 反查；命中语言码即可（地区码可选匹配）。找不到返回 null。
  static AppLocale? fromFlutter(Locale? l) {
    if (l == null) return null;
    for (final e in AppLocale.values) {
      final f = e.flutterLocale;
      if (f.languageCode == l.languageCode &&
          (f.countryCode == null || f.countryCode == l.countryCode)) {
        return e;
      }
    }
    return null;
  }
}

/// 把 [AppL10n] 接进 Flutter 的 `Localizations` 体系。
///
/// 这样 `MaterialApp(localizationsDelegates: [AppL10nDelegate()])` 之后，
/// 任意 `BuildContext` 都能用 `context.l10n.tr('key')` 取到当前语言的文案。
///
/// `load` 是异步的，但文案表是静态的、立即就绪；这里在载入库的同时把
/// [AppL10n.current] 同步成同一份，供**没有 BuildContext** 的地方
/// （如 [AppController] 里的错误文案）直接使用。
class AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const AppL10nDelegate();

  @override
  bool isSupported(Locale locale) => AppLocaleFlutter.fromFlutter(locale) != null;

  @override
  Future<AppL10n> load(Locale locale) async {
    final app = AppLocaleFlutter.fromFlutter(locale) ?? AppLocale.zhCN;
    final l10n = AppL10n(app);
    AppL10n.current = l10n;
    return l10n;
  }

  @override
  bool shouldReload(covariant AppL10nDelegate old) => false;
}

/// 便捷访问：在 widget 树里用 `context.l10n.tr('key')`。
///
/// 优先用 `Localizations` 解析当前 locale 下的 [AppL10n]；解析失败（极少数
/// 还没挂载的瞬间）则回落到 [AppL10n.current] 单例，保证不为空。
extension L10nContext on BuildContext {
  AppL10n get l10n =>
      Localizations.of<AppL10n>(this, AppL10n) ?? AppL10n.current;
}

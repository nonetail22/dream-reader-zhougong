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

import '../l10n/messages.dart';

/// 夜间配色方案。
///
/// 设计前提：**凌晨醒来时会用它，第一诉求是「不晃眼」**。据此定了三条硬规则，
/// 后面加新方案时请一并遵守：
///
/// 1. **底色不用纯白，深色方案里连正文也不用纯白。** `#FFFFFF` 放在暗底上对比过硬，
///    夜里看反而更累眼——所以正文一律是 `#C8CEDC` 这类灰白。
/// 2. **大面积色块只用到中低明度。** 记录页那个 132px 的大圆按钮是整屏最亮的元素，
///    主色压暗一档它就不再是刺眼源；按下时变亮反而成了「它在听」的反馈。
/// 3. **语义标签色在深色下必须提亮。** 见 [Accents]：`Colors.indigo` / `Colors.teal`
///    这类中深色放在暗底上读不清。
enum DreamPalette {
  /// 原来的浅色主题。留着的理由是白天在外面看深色反而吃力。
  dawn(
    id: 'dawn',
    brightness: Brightness.light,
    seed: Color(0xFF4A4E9B),
  ),

  /// 保住原来的蓝紫调性，整体压暗。改动最小，默认。
  deepBlue(
    id: 'deep_blue',
    brightness: Brightness.dark,
    seed: Color(0xFF7C84D8),
    background: Color(0xFF12151C),
    surface: Color(0xFF1B202B),
    surfaceAlt: Color(0xFF262C38),
    primary: Color(0xFF7C84D8),
    onPrimary: Color(0xFF12151C),
    text: Color(0xFFC8CEDC),
    muted: Color(0xFF7A8294),
    outline: Color(0xFF2B3240),
    error: Color(0xFFD98A7A),
    onError: Color(0xFF2A1512),
  ),

  /// OLED 屏像素不发光，是四套里最暗也最省电的一档。
  pureBlack(
    id: 'pure_black',
    brightness: Brightness.dark,
    seed: Color(0xFF8E93E8),
    background: Color(0xFF000000),
    surface: Color(0xFF121214),
    surfaceAlt: Color(0xFF1C1C20),
    primary: Color(0xFF8E93E8),
    onPrimary: Color(0xFF0A0A0C),
    text: Color(0xFFCFD0D6),
    muted: Color(0xFF75767E),
    outline: Color(0xFF232327),
    error: Color(0xFFD98A7A),
    onError: Color(0xFF2A1512),
  ),

  /// 色温最暖、蓝光最少，四套里最护眼（对褪黑素干扰最小）。
  /// 代价是"梦"原本的清冷蓝调没了，气质变柔和。
  warmAmber(
    id: 'warm_amber',
    brightness: Brightness.dark,
    seed: Color(0xFFC9974F),
    background: Color(0xFF191410),
    surface: Color(0xFF241C16),
    surfaceAlt: Color(0xFF332820),
    primary: Color(0xFFC9974F),
    onPrimary: Color(0xFF1A1512),
    text: Color(0xFFD9CDBF),
    muted: Color(0xFF8A7B69),
    outline: Color(0xFF3A2C22),
    error: Color(0xFFD98A6E),
    onError: Color(0xFF2A1710),
  ),

  /// 几乎零蓝光（天文观测/飞行员夜视那一套）。极适合「睁眼按一下、录完就睡」，
  /// 但不适合长时间阅读——翻梦境列表会有点难受。
  redShift(
    id: 'red_shift',
    brightness: Brightness.dark,
    seed: Color(0xFFA8402A),
    background: Color(0xFF0C0705),
    surface: Color(0xFF1A0F0B),
    surfaceAlt: Color(0xFF261711),
    primary: Color(0xFFA8402A),
    onPrimary: Color(0xFFF2DCD2),
    text: Color(0xFFC7A08E),
    muted: Color(0xFF7E5F51),
    outline: Color(0xFF301D16),
    error: Color(0xFFC9553C),
    onError: Color(0xFFF2DCD2),
  ),

  /// 跟随系统：不自己定深浅——系统深色 → 暖棕烛光（默认夜间配色），
  /// 系统浅色 → 浅色。这是**虚拟方案**，自身没有颜色，实际取哪套由
  /// [resolveDreamPalette] 在运行时按系统亮度解析；
  /// 下面的 brightness/seed 只是占位，别直接把本方案喂给 [buildDreamTheme]。
  systemFollow(id: 'system', brightness: Brightness.dark, seed: Color(0xFFC9974F));

  const DreamPalette({
    required this.id,
    required this.brightness,
    required this.seed,
    this.background,
    this.surface,
    this.surfaceAlt,
    this.primary,
    this.onPrimary,
    this.text,
    this.muted,
    this.outline,
    this.error,
    this.onError,
  });

  /// 落盘用的稳定标识（**不要改**，改了会丢用户已选的配色）。
  final String id;
  final Brightness brightness;

  /// 方案名 / 一句话说明（跟随当前界面语言）。
  ///
  /// 由 [id] 拼 key，所以新增方案时只要在 `messages.dart` 里补
  /// `palette_<id>_label` / `palette_<id>_note` 两条即可。
  String get label => AppL10n.current.tr('palette_${id}_label');
  String get note => AppL10n.current.tr('palette_${id}_note');

  /// 浅色方案直接用它播种；深色方案只当调色基准。
  final Color seed;

  final Color? background;
  final Color? surface;
  final Color? surfaceAlt;
  final Color? primary;
  final Color? onPrimary;
  final Color? text;
  final Color? muted;
  final Color? outline;
  final Color? error;
  final Color? onError;

  static const DreamPalette fallback = DreamPalette.deepBlue;

  /// 读到未知 id（老版本存的值 / 手改过配置文件）时回落到默认，不崩。
  static DreamPalette fromId(String? id) => DreamPalette.values.firstWhere(
        (p) => p.id == id,
        orElse: () => fallback,
      );
}

/// 「跟随系统」的运行时解析：系统深色 → [DreamPalette.warmAmber]
/// （暖棕烛光，指定的默认夜间配色），系统浅色 → [DreamPalette.dawn]。
/// 固定方案原样返回——落到任何消费方手里的都一定是**有真实颜色**的方案。
DreamPalette resolveDreamPalette(DreamPalette p, Brightness systemBrightness) {
  if (p != DreamPalette.systemFollow) return p;
  return systemBrightness == Brightness.dark
      ? DreamPalette.warmAmber
      : DreamPalette.dawn;
}

/// 语义标签色：状态徽章、置信度分级。
///
/// 浅色主题沿用原来的颜色（不改动既有观感）；深色主题下**必须提亮**——
/// `Colors.indigo` (#3F51B5) 这类中深色在 `#12151C` 上几乎读不出来。
abstract final class Accents {
  static bool _dark(Brightness b) => b == Brightness.dark;

  /// 梦境列表里的「已解析」
  static Color analyzed(Brightness b) =>
      _dark(b) ? const Color(0xFF5EC9B8) : Colors.teal;

  /// 置信度 A · 文本可见
  static Color confidenceA(Brightness b) =>
      _dark(b) ? const Color(0xFFA6BAC6) : Colors.blueGrey;

  /// 置信度 B · 理论推演
  static Color confidenceB(Brightness b) =>
      _dark(b) ? const Color(0xFF9AA6F0) : Colors.indigo;

  /// 置信度 C · 开放假设
  static Color confidenceC(Brightness b) =>
      _dark(b) ? const Color(0xFFE8B062) : Colors.orange;

  /// 「原文改过、解析结论已过期」
  ///
  /// 是**需要留意**，不是出错，所以用琥珀而不是错误红 —— 旧结论本身没错，
  /// 只是对不上改之后的原文了。深色下同样必须提亮。
  static Color stale(Brightness b) =>
      _dark(b) ? const Color(0xFFE8B062) : const Color(0xFF8A6100);

  /// 「录音占地方了」的提醒。
  ///
  /// 与 [stale] 同一档语气：是**需要留意**，不是出错 —— 录音占了 500MB 本身
  /// 没有任何问题，只是该清一清了。取值直接复用 [stale]，是刻意的：两者从不在
  /// 同一处并排出现，给两个色值反而会被读成"两种不同的严重程度"。
  static Color audioWarn(Brightness b) => stale(b);
}

/// 按方案构造 ThemeData。
///
/// 深色方案用 `ColorScheme.fromSeed(brightness: dark)` 打底再覆盖关键色：
/// 这样 `surfaceContainer*`、`secondary` 等一堆衍生色仍然协调，
/// 我们只钉死真正影响观感的几个（底色 / 面板 / 主色 / 正文 / 次要文字 / 描边 / 错误色）。
ThemeData buildDreamTheme(DreamPalette p) {
  if (p.brightness == Brightness.light) {
    return ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(seedColor: p.seed, brightness: Brightness.light),
    );
  }

  final scheme = ColorScheme.fromSeed(
    seedColor: p.seed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: p.primary,
    onPrimary: p.onPrimary,
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceAlt,
    surfaceContainerHighest: p.surfaceAlt,
    outline: p.outline,
    outlineVariant: p.outline,
    error: p.error,
    onError: p.onError,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 记录页的提示文字用的是 theme.hintColor，M3 下它不会自动跟着 onSurfaceVariant 走
    hintColor: p.muted,
    scaffoldBackgroundColor: p.background,
  );
}

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

/// 语音识别错误码 → 可读中文。
///
/// **刻意不依赖任何 Flutter 包**：本文件是纯字符串逻辑，可以用 `dart test` 直接跑，
/// 不依赖 flutter_tester / 浏览器（见 README 第九节协作约定第 10 条）。
/// transcriber.dart 依赖 speech_to_text（含 Flutter 依赖），测试跑不动，
/// 所以这部分必须拆出来。
///
/// 错误码清单来自 Android `SpeechRecognizer` 文档，
/// 与 speech_to_text 7.5.0 包内注释一致。
library;

import '../l10n/messages.dart';

/// 把设备上报的英文错误码，翻译成「原因 + 下一步该干什么」。
///
/// 注意：识别失败**绝大多数时候不会抛异常**，只会走 onError 回调，
/// 或者干脆什么都不发生（返回空结果）。所以这段映射是用户唯一的线索来源，
/// 不能退化成「识别失败」四个字。
String mapSpeechError(String raw) {
  final e = raw.toLowerCase();
  final tr = AppL10n.current.tr;

  if (e.contains('permission')) {
    return tr('err_speech_permission');
  }
  if (e.contains('busy')) {
    return tr('err_speech_busy');
  }
  if (e.contains('audio')) {
    return tr('err_speech_audio');
  }
  if (e.contains('network')) {
    return tr('err_speech_network');
  }
  if (e.contains('language_not_supported') || e.contains('language_unavailable')) {
    return tr('err_speech_language');
  }
  if (e.contains('speech_timeout')) {
    return tr('err_speech_timeout');
  }
  if (e.contains('no_match')) {
    return tr('err_speech_no_match');
  }
  if (e.contains('recognizer_disabled')) {
    return tr('err_speech_disabled');
  }
  if (e.contains('client') || e.contains('server')) {
    return tr('err_speech_service', {'raw': raw});
  }
  return tr('err_speech_unknown', {'raw': raw});
}

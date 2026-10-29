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

/// 离线模型的「确认 → 下载 → 进度」对话框，设置页与录音页共用。
///
/// 0.6.0 起模型不预装进安装包：用户第一次选离线识别（或第一次离线转写）时
/// 在这里补上"知情 → 同意 → 看得到进度"这一段。下载实现与校验在
/// `services/offline_model.dart`，本文件只负责界面。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/offline_model.dart';
import '../services/sherpa_onnx_transcriber.dart';

/// 确保离线模型可用：
/// - 已下载 → 直接返回 true；
/// - 未下载 → 弹确认框；同意则下载并显示进度，完成返回 true；
/// - 用户拒绝 / 取消 / 失败 → 返回 false，调用方据此放弃本次识别或不切换模式。
///
/// 返回 false 时**不抛异常**——"用户先不下载"是正当选择，不是错误。
Future<bool> ensureOfflineModel(BuildContext context) async {
  final transcriber = SherpaOnnxTranscriber();
  if (await transcriber.isModelInstalled()) return true;
  if (!context.mounted) return false;

  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.tr('offline_dl_title')),
      content: Text(l10n.tr('offline_dl_body', {
        'name': OfflineModelFiles.displayName,
        'size': OfflineModelFiles.approxSize,
      })),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.tr('offline_dl_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.tr('offline_dl_confirm',
              {'size': OfflineModelFiles.approxSize})),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  if (!context.mounted) return false;

  // 下载要几分钟，期间本页可能被切走：跨异步一律用这里抓好的 navigator /
  // messenger，不再碰 context。
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final progress = ValueNotifier<double>(0);
  final statusText =
      ValueNotifier<String>(l10n.tr('offline_dl_progress', {'pct': '0'}));
  var cancelled = false;

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false, // 防止系统返回键把进度框关掉、留下看不见的下载
      child: AlertDialog(
        title: Text(l10n.tr('offline_dl_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, __) => LinearProgressIndicator(value: v),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: statusText,
              builder: (_, s, __) => Text(s),
            ),
          ],
        ),
        actions: [
          // 只置位不关弹窗：让下载循环自己抛 ModelDownloadCancelled，
          // 收尾（关弹窗 + 提示）统一走下面唯一的出口。
          TextButton(
            onPressed: () => cancelled = true,
            child: Text(l10n.tr('offline_dl_cancel')),
          ),
        ],
      ),
    ),
  ));

  try {
    await transcriber.downloadModel(
      onProgress: (received, total) {
        final v = total <= 0 ? 0.0 : received / total;
        progress.value = v;
        statusText.value = l10n.tr(
            'offline_dl_progress', {'pct': (v * 100).toStringAsFixed(0)});
      },
      isCancelled: () => cancelled,
    );
    if (navigator.canPop()) navigator.pop();
    return true;
  } on ModelDownloadCancelled {
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.tr('offline_dl_cancelled'))),
    );
    return false;
  } catch (e) {
    if (navigator.canPop()) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.tr('offline_dl_failed', {'e': '$e'}))),
    );
    return false;
  }
}

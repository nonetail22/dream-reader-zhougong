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

import '../l10n/app_localizations.dart';

/// 修改梦境原文的对话框 —— 记录页 / 时间线 / 详情页三处共用。
///
/// 返回用户确认后的新原文；取消则返回 `null`。
///
/// 为什么做成对话框，而不是在三个页面里各放一个可编辑区域：
/// 1. 时间线和详情页本来就是"回头看"的场景，页面结构里没有天然可编辑的位置；
/// 2. 改原文是做决定的事，需要一个**明确的开始与结束**。半梦半醒时误触
///    把识别结果改花、自己还不知道，比"多点一步"糟糕得多；
/// 3. 一处实现三处复用，行为（尤其"还原识别结果"这类细节）不会各写各的。
///
/// [rawText] 传识别器的原始输出（手输记录传 null）。它与当前原文不一致时，
/// 会多出一个「还原识别结果」的入口 —— 改坏了的退路。
Future<String?> showEditTranscriptDialog(
  BuildContext context, {
  required String text,
  String? rawText,
  bool willNeedReanalysis = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditTranscriptDialog(
      text: text,
      rawText: rawText,
      willNeedReanalysis: willNeedReanalysis,
    ),
  );
}

/// 独立成 StatefulWidget 是为了**正确释放 TextEditingController**：
/// 在 `showDialog` 外面造好再 dispose，会在关闭动画期间踩到
/// 「A TextEditingController was used after being disposed」。
class _EditTranscriptDialog extends StatefulWidget {
  const _EditTranscriptDialog({
    required this.text,
    this.rawText,
    this.willNeedReanalysis = false,
  });

  final String text;
  final String? rawText;
  final bool willNeedReanalysis;

  @override
  State<_EditTranscriptDialog> createState() => _EditTranscriptDialogState();
}

class _EditTranscriptDialogState extends State<_EditTranscriptDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.text);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 能不能还原成识别结果：有原始输出，且当前内容与它不同。
  bool get _canRestore =>
      widget.rawText != null && widget.rawText!.trim() != _ctrl.text.trim();

  /// 空原文等于把这条记录废掉 —— 想删记录走「删除」，不是把字删空。
  bool get _isValid => _ctrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 输入框高度上限＝屏高的 40%（键盘弹出后 AlertDialog 会被压到不足半屏，
    // 固定行数（maxLines: 12）在长文本 + 键盘场景下会把内容区撑穿——文字
    // 画出对话框边界、盖住按钮（0.7.1 用户截图）。改成**分数高度封顶 +
    // 框内滚动**，键盘弹出、文字再多都出不了框。
    final maxFieldHeight = MediaQuery.sizeOf(context).height * 0.4;
    return AlertDialog(
      // 内容超出可用高度时在对话框内滚动，actions 始终完整可见
      scrollable: true,
      title: Text(context.l10n.tr('edit_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('edit_intro'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxFieldHeight),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 4,
              // 行数不设上限（null），实际高度由上面的 maxHeight 封顶，
              // 超出部分在输入框内滚动。
              maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: context.l10n.tr('edit_hint'),
              ),
            ),
          ),
          if (widget.willNeedReanalysis) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.tr('edit_will_reanalyze'),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        // 注意：`AlertDialog.actions` 由 `OverflowBar` 排布，**不能塞 `Spacer`**
        // （它要求父级是宽度有界的 Flex），所以还原入口就跟在按钮组里。
        if (_canRestore)
          TextButton(
            onPressed: () => setState(
              () => _ctrl.text = widget.rawText!.trim(),
            ),
            child: Text(context.l10n.tr('restore')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.tr('cancel')),
        ),
        FilledButton(
          // 空原文不给保存，并让按钮的禁用状态本身说明原因
          onPressed:
              _isValid ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: Text(context.l10n.tr('save')),
        ),
      ],
    );
  }
}

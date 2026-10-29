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

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/dream_entry.dart';
import '../theme/palettes.dart';
import 'dream_detail_page.dart';
import 'edit_transcript_dialog.dart';

/// 梦境时间线：倒序浏览全部记录（音频+转写+解析状态）。
///
/// [highlightId] 非空时，对应的那条会**被标亮**并自动滚到视野里——
/// 录音页选「否，去梦境列表」后用它把"刚存的那条"指给用户看。
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, this.highlightId});

  final String? highlightId;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _highlightKey = GlobalKey();

  /// 关键字搜索（0.7.3）：只搜梦的**内容**（转写文本与原始识别输出），
  /// 不搜解析结论——想找的是"做过什么梦"，不是"当时怎么解读的"。
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// 状态筛选（0.7.3）。默认「全部」，行为与老版本一致。
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    // 标亮项通常在列表顶部，但同一次会话里若已有更早的记录也不保证，
    // 所以挂载后滚一下确保它进视野（新记录恒在最前，这步基本是 no-op）。
    if (widget.highlightId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlight());
    }
  }

  void _scrollToHighlight() {
    final ctx = _highlightKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      alignment: 0.15,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 筛选 + 搜索条件下的可见记录。
  List<DreamEntry> _visible(List<DreamEntry> entries) {
    final q = _query.toLowerCase();
    return entries.where((e) {
      // ---- 状态筛选（互斥的显示口径：失败 > 过期 > 已解析）----
      switch (_filter) {
        case _StatusFilter.all:
          break;
        case _StatusFilter.unanalyzed:
          if (e.analysis != null || e.status == 'failed') return false;
        case _StatusFilter.analyzed:
          if (e.analysis == null || e.analysisIsStale || e.status == 'failed') {
            return false;
          }
        case _StatusFilter.stale:
          if (!e.analysisIsStale) return false;
        case _StatusFilter.failed:
          if (e.status != 'failed') return false;
      }
      // ---- 关键字搜索 ----
      if (q.isEmpty) return true;
      return e.transcript.toLowerCase().contains(q) ||
          (e.rawTranscript ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final theme = Theme.of(context);
    final visible = _visible(c.entries);
    final Widget body;
    if (c.entries.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.tr('timeline_empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (visible.isEmpty) {
      // 有记录但被筛选/搜索条件滤光——给出能解释条件的提示，别让用户
      // 以为记录丢了。
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.tr('timeline_no_match'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.hintColor),
          ),
        ),
      );
    } else {
      body = ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final entry = visible[i];
          final highlight = entry.id == widget.highlightId;
          return _EntryTile(
            key: highlight ? _highlightKey : null,
            entry: entry,
            highlight: highlight,
          );
        },
      );
    }

    return Column(
      children: [
        // 「录音占地方了」的提醒。放在时间线而不是只放设置页里，是因为
        // 只藏在设置页里等于没有提醒 —— 用户没事不会去翻设置。
        if (c.shouldWarnAudio) const _AudioWarnBanner(),
        if (c.entries.isNotEmpty) ...[
          _SearchField(controller: _searchCtrl, onChanged: (v) {
            setState(() => _query = v.trim());
          }),
          _FilterChips(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
        ],
        Expanded(child: body),
      ],
    );
  }
}

/// 状态筛选的口径。
///
/// 五档互斥显示（不是布尔正交）：失败与过期是**特征更强**的状态，优先归入
/// 那一档——比如"重新解析失败但旧结论还在"的记录，出现在「解析失败」里
/// 而不是「已解析」，因为"需要处理"的信号是失败不是已解析。
enum _StatusFilter { all, unanalyzed, analyzed, stale, failed }

extension _StatusFilterX on _StatusFilter {
  String get key => switch (this) {
        _StatusFilter.all => 'timeline_filter_all',
        _StatusFilter.unanalyzed => 'timeline_filter_unanalyzed',
        _StatusFilter.analyzed => 'timeline_filter_analyzed',
        _StatusFilter.stale => 'timeline_filter_stale',
        _StatusFilter.failed => 'timeline_filter_failed',
      };
}

/// 顶部关键字搜索框。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            hintText: context.l10n.tr('timeline_search_hint'),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// 状态筛选条（横向滚动的 ChoiceChips）。
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final _StatusFilter selected;
  final ValueChanged<_StatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget label(_StatusFilter f) => Text(l10n.tr(f.key));
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final f in _StatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: label(f),
                selected: f == selected,
                onSelected: (_) => onSelected(f),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

/// 「录音占地方了」的横幅。
///
/// 三个刻意的设计：
/// 1. 只**提醒**，绝不自动删。音频是用户自己的原话，删掉拿不回来；
/// 2. 说的不只是"占了多少"，还有"去哪儿清" —— 只报数字的提醒等于给用户
///    布置了一道作业；
/// 3. 「知道了」记下的是**当时的字节数**（见 [AppController.dismissAudioWarn]），
///    只有占用又明显变大才再现身。用 bool 记的版本只有两种下场：每次启动都弹
///    （很快被无视）或永远不再提（危险）。
class _AudioWarnBanner extends StatelessWidget {
  const _AudioWarnBanner();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final theme = Theme.of(context);
    final tint = Accents.audioWarn(theme.brightness);
    final u = c.audioUsage;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sd_storage_outlined, size: 18, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('warn_banner_main',
                      {'total': u.humanTotal, 'count': '${u.fileCount}'}),
                  style: theme.textTheme.bodySmall?.copyWith(color: tint),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.tr('warn_banner_tip'),
                  style:
                      theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: c.dismissAudioWarn,
            child: Text(context.l10n.tr('warn_dismiss')),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    super.key,
    required this.entry,
    this.highlight = false,
  });
  final DreamEntry entry;

  /// 是否被标亮（录音页「否，去梦境列表」后，把这条指给用户看）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 「原文改过 → 结论对不上」要盖过「已解析」显示。否则用户看到"已解析"，
    // 会以为这就是当前原文的结论，而实际上它对应的是一段已经不存在的原文。
    final (label, color) = entry.analysisIsStale
        ? (context.l10n.tr('status_stale'), Accents.stale(theme.brightness))
        : switch (entry.status) {
            // 深色主题下 teal 会糊在暗底里，按 brightness 取提亮后的色
            'analyzed' =>
              (context.l10n.tr('status_analyzed'), Accents.analyzed(theme.brightness)),
            'failed' => (context.l10n.tr('status_failed'), theme.colorScheme.error),
            'parsing' =>
              (context.l10n.tr('status_parsing'), theme.hintColor),
            _ => (context.l10n.tr('status_only_record'), theme.hintColor),
          };
    return Card(
      margin: EdgeInsets.zero,
      // ★ 标亮：主色描边 + 极淡主色填充，让"刚存的那条"一眼可辨。
      // 走 theme.colorScheme.primary（已是调色板处理过的、深浅主题都安全的色），
      // 不要直接写 Colors.xxx（深色下会糊）。
      color: highlight ? theme.colorScheme.primary.withValues(alpha: 0.08) : null,
      shape: highlight
          ? RoundedRectangleBorder(
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DreamDetailPage(entryId: entry.id)),
        ),
        onLongPress: () => _confirmDelete(context),
        title: Row(
          children: [
            // 标亮时加一个主色小圆点，进一步把视线引到这条
            if (highlight) ...[
              Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Text(_fmt(entry.recordedAt), style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
            ),
            if (entry.hasTraumaFlag) ...[
              const SizedBox(width: 6),
              Icon(Icons.shield_outlined, size: 16, color: theme.colorScheme.error),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标签放在原文预览**上面**：标签是"一眼扫过去就能分类"的东西，
              // 而原文预览两行要占满时会把标签挤到看不见的位置。
              // 用 Wrap 而不是 Row：窄屏上 4 个标签放不下一行是常态，
              // Row 会直接溢出报错，Wrap 只是换行。
              if (entry.hasTags) ...[
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    if (entry.moodLabel != null) _tagChip(theme, entry.moodLabel!),
                    for (final label in entry.flagLabels) _tagChip(theme, label),
                  ],
                ),
              ],
              Text(
                _clip(entry.transcript, 60),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.audioPath != null)
              Icon(Icons.graphic_eq, size: 18, color: theme.hintColor),
            // 语音识别会听错字，改原文是常用动作，所以给一个明面上的入口，
            // 而不是藏进长按菜单（长按仍是删除，那个不该被误触）。
            IconButton(
              tooltip: context.l10n.tr('edit_original'),
              onPressed: () => _editTranscript(context),
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  /// 改这条记录的原文。
  ///
  /// 只改原文、不自动重新解析：旧结论要不要丢是用户的决定，
  /// 而且每改一次就跑一次 BYOK 调用等于花用户的钱。界面会给出提示。
  Future<void> _editTranscript(BuildContext context) async {
    final c = AppScope.of(context);
    final next = await showEditTranscriptDialog(
      context,
      text: entry.transcript,
      rawText: entry.rawTranscript,
      willNeedReanalysis: entry.analysis != null,
    );
    if (next == null || next == entry.transcript) return;
    await c.updateTranscript(entry.id, next);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    // 0.3.3 起删记录会**连带删掉它的录音文件**（在这之前只删 JSON，
    // 音频会永远留在盘上没人认得）。所以确认文案必须把这件事说出来 ——
    // 用户以为只删了一条文字记录，实际被删掉的还有自己的声音。
    final hasAudio = entry.audioPath != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('delete_record_title')),
        content: Text(
          hasAudio
              ? context.l10n.tr('delete_record_body_has_audio')
              : context.l10n.tr('delete_record_body'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.tr('delete'))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await AppScope.of(context).deleteEntry(entry.id);
    }
  }

  /// 时间线上一个标签的小色块。
  ///
  /// 用 `surfaceContainerHighest / onSurfaceVariant` 而不是在 [Accents] 里新增一个
  /// 色值：标签是**中性信息**，不表示任何严重程度（不像 stale 的琥珀、错误的红），
  /// 而语义色一旦给出就会被读成"这个标签有特殊含义"。走主题令牌还顺带保证
  /// 五套配色（含 OLED 黑与天文红）都自动适配，不必逐套调。
  static Widget _tagChip(ThemeData theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  /// 按**用户感知的字符**截断。
  ///
  /// 原来直接用 `substring(0, 60)`：那是按 UTF-16 码元切，正好切在一个
  /// 代理对中间时会把一个 emoji 劈成两半，渲染出乱码方块。说梦里出现
  /// 表情符号完全可能，所以用 `characters` 按字素簇切
  /// （`package:characters` 由 `material.dart` 直接导出，不需额外依赖）。
  static String _clip(String s, int max) {
    final chars = s.characters;
    if (chars.length <= max) return s;
    return '${chars.take(max)}…';
  }

  static String _fmt(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}';
  }
}

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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/dream_entry.dart';
import '../services/dream_tags.dart';
import '../services/speech_mode.dart';
import '../services/transcriber.dart';
import '../theme/palettes.dart';
import '../l10n/app_localizations.dart';
import 'audio_player_bar.dart';
import 'edit_transcript_dialog.dart';
import 'offline_model_dialog.dart';

/// 梦境详情：原文 + 解析结果（理论标注 + 置信度分级逐条展示）。
/// UI 层刻意把「置信度」做成显眼标签——可查证性是本产品与"解梦词典"的核心区别。
class DreamDetailPage extends StatelessWidget {
  const DreamDetailPage({super.key, required this.entryId});
  final String entryId;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final entry = c.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) {
      return Scaffold(body: Center(child: Text(context.l10n.tr('not_found'))));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_fmt(entry.recordedAt)),
        actions: [
          IconButton(
            tooltip: context.l10n.tr('edit_original'),
            onPressed: () => _editTranscript(context, entry),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: context.l10n.tr('reanalyze_tooltip'),
            onPressed: c.busy ? null : () => _reanalyze(context, entry),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(context.l10n.tr('section_transcript')),
          Card(
            // 0.7.1：原文卡整张可点进「修改原文」——AppBar 右上角的编辑图标
            // 可发现性太差（用户反馈"页面上要能改文字"）。与录音卡里新增的
            // 「修改原文」按钮共用同一个入口函数，行为不会各写各的。
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editTranscript(context, entry),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                    entry.transcript, style: theme.textTheme.bodyLarge),
              ),
            ),
          ),
          if (entry.transcriptWasEdited)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 16, color: theme.hintColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.tr('edited_note'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ),
                ],
              ),
            ),
          // 录音是原文的**原始证据**：识别把哪句听错了，回听一下就知道。
          // 0.3.3 起「保留录音」默认打开，所以这条路径是常态而不是附加品，
          // 给它一张独立的卡片（而不是原来那行「录音已保存在本机」的小字）——
          // 一行字承诺了"保存了"，却没有任何办法听到它。
          if (entry.audioPath != null) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.graphic_eq, size: 16, color: theme.hintColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.l10n.tr('audio_evidence'),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AudioPlayerBar(
                      path: entry.audioPath!,
                      onDelete: () => _confirmDeleteAudio(context, entry),
                    ),
                    // 0.6.2：录音可以**多次**重新识别。换识别方式（离线⇄云端）、
                    // 模型升级、上次识别得不好——都是再点一次的理由。
                    // 0.7.1：旁边加「修改原文」——识别完紧跟着就要改错字，
                    // 两个动作是一对，放在一起才顺（AppBar 图标留着兜底）。
                    Wrap(
                      spacing: 4,
                      runSpacing: 0,
                      children: [
                        TextButton.icon(
                          onPressed: () => _retranscribe(context, entry),
                          icon: const Icon(Icons.mic_external_on, size: 16),
                          label:
                              Text(context.l10n.tr('retranscribe_button')),
                        ),
                        TextButton.icon(
                          onPressed: () => _editTranscript(context, entry),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: Text(context.l10n.tr('edit_original')),
                        ),
                      ],
                    ),
                    Text(
                      context.l10n.tr('audio_note'),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // 标签放在解析结果**之前**：它是解析的输入之一，用户改完标签再重解析
          // 才有意义；放在结论下面就变成"读完了才想起要改输入"。
          const SizedBox(height: 10),
          _TagsCard(
            entry: entry,
            onMood: (mood) => _applyTags(
              context,
              entry,
              mood: mood,
              clearMood: mood == null,
            ),
            onFlag: (flag, on) => _applyTags(
              context,
              entry,
              flags: [
                for (final f in DreamTags.flags)
                  if (f.id == flag ? on : entry.flags.contains(f.id)) f.id,
              ],
            ),
          ),
          // 结论过期要放在**解析结果之前**：用户是先看到这句话，再往下看那些
          // 结论的，顺序反了就变成"先读完才发现白读"。
          if (entry.analysisIsStale) _StaleNotice(entry: entry),
          const SizedBox(height: 16),
          if (entry.status == 'parsing')
            // 解析是长耗时操作（最快 3 分钟、推理型 15 分钟）。用"正在解析"卡
            // 取代裸转圈：明确告诉用户它没卡死，且中途退出也无妨。
            const _ParsingCard()
          else if (entry.analysis == null)
            _AnalyzeCta(
              entry: entry,
              error: entry.analysisError ?? c.lastError,
              onSupplement: () => _supplementContext(context, entry),
            )
          else ...[
            // 重新解析失败但上一次的结论还在：把失败原因摆出来，但**不覆盖**旧结论，
            // 否则用户会以为"解析出了问题、结论没了"。
            if (entry.status == 'failed')
              _ReparseFailedBanner(reason: entry.analysisError ?? ''),
            ..._analysisSections(context, entry),
          ],
        ],
      ),
    );
  }

  /// 改标签 → 落盘 → 给一条"可以用新标签重新解析"的出口。
  ///
  /// **不自动重解析**：那要花用户自己的 BYOK 额度，而点标签是个很轻的动作
  /// （与改原文、答提问同一个规矩，见 README 第九节第 42 条）——
  /// 让"按一下色块"顺带扣一次钱，是这类应用最容易被骂的设计。
  ///
  /// 但也不能什么都不说：标签是**解析的输入**，用户改了它却不知道要不要重跑，
  /// 就会停在"那我这标签白打了？"。所以给一条能一键走完的出口。
  Future<void> _applyTags(
    BuildContext context,
    DreamEntry entry, {
    String? mood,
    bool clearMood = false,
    List<String>? flags,
  }) async {
    final c = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await c.updateTags(entry.id, mood: mood, clearMood: clearMood, flags: flags);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.tr('tag_saved')),
        action: SnackBarAction(
          label: context.l10n.tr('reanalyze_confirm_diff'),
          onPressed: () {
            // 重新取一次：上面那次 updateTags 已经 refresh 过，手上这份 entry 是旧的
            final fresh = c.entryById(entry.id);
            if (fresh != null && context.mounted) _reanalyze(context, fresh);
          },
        ),
      ),
    );
  }

  /// 「重新解析」。
  ///
  /// 与「改完原文顺手再解析一次」不同：这个按钮是**没有上下文的一下点击**
  /// （在去点「修改原文」的路上很容易误触），而它会做两件有代价的事——
  /// 覆盖已经存下来的结论、再消耗一次用户的 BYOK 调用。所以有结论时必须先问一句。
  ///
  /// 问的时候要说得准：把"这次重来有没有意义"摆明白。输入指纹一致就直说
  /// 「大概率得到相同的结论」，别让用户以为花钱能换来别的东西——那正是
  /// 上一次修复的问题（点一下刷新，结论就换一套说法，用户无从判断该信哪一份）。
  Future<void> _reanalyze(BuildContext context, DreamEntry entry) async {
    final c = AppScope.of(context);
    // 还没有结论：不是在覆盖什么，直接解析
    if (entry.analysis == null) {
      await c.analyzeEntry(entry);
      return;
    }

    final sameInput =
        entry.analysisInputUnchanged(await c.fingerprintOf(entry));
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sameInput ? context.l10n.tr('reanalyze_same_title') : context.l10n.tr('reanalyze_diff_title')),
        content: Text(
          sameInput
              ? context.l10n.tr('reanalyze_same_body')
              : context.l10n.tr('reanalyze_diff_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(sameInput ? context.l10n.tr('reanalyze_confirm_same') : context.l10n.tr('reanalyze_confirm_diff')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await c.analyzeEntry(entry);
  }

  /// 补充「近期状态 / 对提问的回答」。
  ///
  /// 这是 v1.1.0 提问层的落点。为什么非要这个入口：
  /// 解析提示需要更多材料才能判断，而 `recentContext` 在 v1.0.x 里
  /// **模型/prompt/解析链路全通、界面上却没有任何地方能填** —— 真机实测时模型自己在
  /// 输出里写了「用户未填写近期状态，无法确认意识态度的基线」，这就是那个缺口的证据。
  ///
  /// 三个按钮而不是两个：「保存并解析」是主路径，但用户可能想一次把几个问题都答完
  /// 再解析（每次解析都花他自己的钱），所以「只保存」必须存在。
  Future<void> _supplementContext(BuildContext context, DreamEntry entry) async {
    final c = AppScope.of(context);
    final controller = TextEditingController(text: entry.recentContext);
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.tr('supplement_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('supplement_intro'),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: context.l10n.tr('supplement_hint'),
                    hintStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.tr('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: Text(context.l10n.tr('supplement_save_only')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save_analyze'),
              child: Text(context.l10n.tr('supplement_save_analyze')),
            ),
          ],
        ),
      );
      if (action == null) return;
      final text = controller.text.trim();
      await c.updateRecentContext(entry.id, text);
      if (action != 'save_analyze') return;
      // 用刷新后的那条：updateRecentContext 会 refresh，新条目才带上刚写的说明
      final fresh = c.entryById(entry.id);
      if (fresh != null) await c.analyzeEntry(fresh);
    } finally {
      controller.dispose();
    }
  }

  /// 改原文。与时间线、记录页共用同一个对话框，行为不会各写各的。
  Future<void> _editTranscript(BuildContext context, DreamEntry entry) async {
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

  /// 「重新识别文字」（0.6.2）：用当前语音识别方式，对这条**已存的录音**
  /// 再跑一次转写，可反复使用。
  ///
  /// 三个使用场景：上次识别得不好（换模型后尤其）、想换一条识别路线
  /// （离线⇄云端）、录音还在但文字被改坏了想拿回一份机器版本。
  ///
  /// 纪律与「重新解析」同源：
  /// - 有文字时先确认——**会覆盖现有文字**（含用户手改过的内容），且旧解析
  ///   会标记为过期；
  /// - 失败或识别为空时**绝不动现有文字**（宁可放过，别把真东西丢掉）；
  /// - 成功后**不自动重新解析**（花用户的钱，界面给「已过期」横幅 + 一键入口）。
  Future<void> _retranscribe(BuildContext context, DreamEntry entry) async {
    final c = AppScope.of(context);
    final path = entry.audioPath;
    if (path == null) return;
    final l10n0 = context.l10n;
    final messenger0 = ScaffoldMessenger.of(context);
    // 录音文件可能已被清理（无主列表清理 / 换机）——先确认存在再谈别的
    if (!File(path).existsSync()) {
      messenger0.showSnackBar(
        SnackBar(content: Text(l10n0.tr('retranscribe_no_file'))),
      );
      return;
    }
    if (c.speechMode == SpeechMode.offline) {
      final modelReady = await ensureOfflineModel(context);
      if (!modelReady || !context.mounted) return;
    }

    final l10n = context.l10n;
    // 有文字（尤其是手改过的）必须先问；空白文字则直接跑
    if (entry.transcript.trim().isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.tr('retranscribe_title')),
          content: Text(l10n.tr('retranscribe_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.tr('retranscribe_confirm')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final status = ValueNotifier<String?>(null);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.tr('retranscribe_running_title')),
          content: ValueListenableBuilder<String?>(
            valueListenable: status,
            builder: (_, s, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text(
                  s ?? l10n.tr('retranscribe_running_hint'),
                  style: const TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ));

    // ★ 先等进度框**真的画出来**，再开始重活。
    // showDialog 只是把路由排进队列，下面的识别管线（读波形 → 分段规划 →
    // 模型解码）是同步大块头；不等一帧就开干，对话框连进场动画都跑不了，
    // 用户看到的就是"点了重新识别之后什么都没有，过一会儿文字自己冒出来"
    // （0.7.0 用户反馈），还以为没点上。
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    FileTranscriber? transcriber;
    try {
      transcriber = c.buildFileTranscriber(onStatus: (s) => status.value = s);
      final issue = await transcriber.readyIssue();
      if (issue != null) {
        throw TranscriberException(issue);
      }
      final text = (await transcriber.transcribe(path)).trim();
      if (text.isEmpty) {
        // 识别为空 ≠ 覆盖成空：现有文字（可能是手改过的）一字不动
        if (navigator.canPop()) navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.tr('retranscribe_empty'))),
        );
        return;
      }
      await c.applyRetranscription(entry.id, text, text);
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tr('retranscribe_done'))),
      );
    } catch (e) {
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.tr('retranscribe_failed', {'e': '$e'})),
        ),
      );
    } finally {
      transcriber?.dispose();
      status.dispose();
    }
  }

  /// 删掉这条录音、**保留整条记录**。
  ///
  /// 与时间线里长按删除刻意分成两个确认级别：那边删的是**文字**（梦本身），
  /// 这里删的只是**证据**。不分开的话，用户想腾点空间时不敢按 —— 会怕把梦删掉。
  Future<void> _confirmDeleteAudio(BuildContext context, DreamEntry entry) async {
    final c = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('delete_audio_title')),
        content: Text(
          context.l10n.tr('delete_audio_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('delete_audio_btn')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await c.deleteEntryAudio(entry.id);
  }

  List<Widget> _analysisSections(BuildContext context, DreamEntry entry) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    if (entry.hasTraumaFlag) {
      widgets.add(
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.tr('trauma_note'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 12));
    }

    // ① 白话主结论放最前（v1.1.0）。用户第一眼要看到"这个梦可能和什么有关"，
    //    而不是先读七条机制名。老记录没有这一层 → 整块跳过，不会出现空卡。
    if (entry.hasPlainReading) {
      widgets.add(_ReadingCard(
        headline: entry.readingHeadline,
        mood: entry.readingMood,
      ));
      widgets.add(const SizedBox(height: 16));
    }

    widgets.add(_SectionTitle(context.l10n.tr('section_itemized')));
    if (entry.analysisItems.isEmpty) {
      widgets.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            context.l10n.tr('fragment_note'),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ));
    } else {
      for (final item in entry.analysisItems) {
        widgets.add(_AnalysisCard(item: item));
      }
    }

    // ② 术语对照表。术语只出现在折叠区里，这张表是术语与结论之间的桥：
    //    「凝缩」这类词不进主阅读路径，但用户想看时得能立刻查到人话解释。
    if (entry.terms.isNotEmpty) {
      widgets.add(const SizedBox(height: 4));
      widgets.add(_TermsCard(terms: entry.terms));
    }

    // ③ 提问（v1.1.0 的产品要点）：把"信息不足"从结论变成下一步动作。
    if (entry.openQuestions.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(_OpenQuestionsCard(
        questions: entry.openQuestions,
        onAnswer: () => _supplementContext(context, entry),
      ));
    } else if (entry.noMoreQuestions) {
      // 模型明确说"问完了"（v1.1.2）。要说出来，不能让它静默消失——
      // 用户看到"没有提问"时的默认解读是"解析出问题了"，而不是"信息已经够了"。
      widgets.add(const SizedBox(height: 16));
      widgets.add(_SectionTitle(context.l10n.tr('no_questions_title')));
      widgets.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            context.l10n.tr('no_questions_body'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ));
    }

    if (entry.advice.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(_SectionTitle(context.l10n.tr('section_advice')));
      widgets.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entry.advice
                .map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('· $a'),
                    ))
                .toList(),
          ),
        ),
      ));
    }

    if (entry.limitationsNote.isNotEmpty) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(Text(
        entry.limitationsNote,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ));
    }
    widgets.add(const SizedBox(height: 10));
    widgets.add(Text(
      context.l10n.tr('disclaimer'),
      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
    ));
    widgets.add(const SizedBox(height: 24));
    return widgets;
  }

  static String _fmt(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}';
  }
}

/// 「标签」卡片：醒来第一感觉（单选）+ 这条梦的属性（多选）。
///
/// 为什么放在解析结果**之前**：它是**解析的输入**（见 [DreamTags.promptLine]），
/// 和原文、近期状态是同一层的东西。用户在这里改完，再点「重新解析」才对得上。
///
/// 刻意**不做成打卡**：没有连续天数、没有完成度、没有"连续记录 7 天解锁"。
/// 打不打标签完全不影响记录本身，也不影响任何其他功能——
/// 一旦给它加激励，它就变成了"为了让用户多记梦"的东西，那不在本产品的承诺里
/// （见 README 第一节硬边界）。
class _TagsCard extends StatelessWidget {
  const _TagsCard({
    required this.entry,
    required this.onMood,
    required this.onFlag,
  });

  final DreamEntry entry;

  /// 选「醒来第一感觉」；传 null 表示**取消已选的**（不是"没选"）。
  final void Function(String? mood) onMood;

  /// 勾上 / 取消一个属性。
  final void Function(String flag, bool on) onFlag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.tr('tags_title'),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(context.l10n.tr('mood_label_dtl'), style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in DreamTags.moods)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: entry.mood == o.id,
                    // 再点一次已选中的 = 取消（点错了要能退回来）
                    onSelected: (_) => onMood(entry.mood == o.id ? null : o.id),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(context.l10n.tr('flag_label_dtl'), style: theme.textTheme.labelSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in DreamTags.flags)
                  FilterChip(
                    label: Text(o.label),
                    selected: entry.flags.contains(o.id),
                    onSelected: (on) => onFlag(o.id, on),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr('flag_note'),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyzeCta extends StatelessWidget {
  const _AnalyzeCta({required this.entry, this.error, this.onSupplement});

  final DreamEntry entry;
  final String? error;

  /// 「还没解析就先补充近期状态」的入口（v1.1.0）。
  ///
  /// 为什么要在**第一次解析之前**就给：解析结果的好坏几乎全看输入材料，
  /// 而近期状态正是最能提高判断质量的那一项（它决定"这个意象是最近的事
  /// 还是长期议题"）。等解析完再补，用户已经白读了一版。
  final VoidCallback? onSupplement;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: () => c.analyzeEntry(entry),
          icon: const Icon(Icons.auto_awesome),
          label: Text(context.l10n.tr('analyze_cta_btn')),
        ),
        if (onSupplement != null)
          TextButton.icon(
            onPressed: onSupplement,
            icon: const Icon(Icons.edit_note, size: 16),
            label: Text(context.l10n.tr('analyze_cta_supplement')),
          ),
        const SizedBox(height: 8),
        Text(context.l10n.tr('analyze_cta_note'),
            style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// 解析进行中：长耗时操作的状态提示卡。
///
/// 取代原来"只看得到一个转圈"的裸 indicator——解析最快 3 分钟、推理型 15 分钟，
/// 光一个转圈很容易被误判成卡死或无响应。这里明确说"正在解析"、并告诉用户
/// 中途退出也无妨（解析跑在控制器上，不依赖这个页面），回来就能看到结果。
class _ParsingCard extends StatelessWidget {
  const _ParsingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.tr('parsing_title'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr('parsing_hint'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 重新解析失败、但上一次的结论还在时的提示横幅。
///
/// 失败路径刻意**保留旧结论**（见 [AppController.analyzeEntry]），所以这里只把
/// 失败原因摆出来、提示"旧结论没被覆盖"，而不是把整页变成"解析失败"的红字——
/// 否则用户会以为之前辛辛苦苦解析出来的东西没了。
class _ReparseFailedBanner extends StatelessWidget {
  const _ReparseFailedBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.error;
    final reasonText =
        reason.isNotEmpty ? reason : context.l10n.tr('reparse_failed_unknown');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.tr('reparse_failed_banner', {'reason': reasonText}),
              style: theme.textTheme.bodySmall?.copyWith(color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「原文改过 → 旧结论对不上」的横幅。
///
/// 刻意**不自动重新解析**：重解析要花用户自己的钱，而且用户可能只是改了个
/// 别字、还没改完。这里只把事实摆明白，把「要不要重来」的决定权交回去。
class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.entry});

  final DreamEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppScope.of(context);
    final tint = Accents.stale(theme.brightness);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: tint),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.tr('stale_title'),
                    style: theme.textTheme.bodySmall?.copyWith(color: tint),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: c.busy ? null : () => c.analyzeEntry(entry),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(context.l10n.tr('stale_reparse')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 白话主结论卡（v1.1.0）。
///
/// 这是详情页的**入口**：一句话说清这个梦可能在说什么。
/// 刻意做得比正文更醒目（主色描边 + 更大的字号）——它必须被一眼认出是"主结论"，
/// 而不是与下面几条并列的又一段专业文字。这正是 0.3.4 之前缺的那块：
/// 结论有、理论有、证据有，但没有"人话版的总结"。
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.headline, this.mood = ''});

  final String headline;
  final String mood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: tint),
              const SizedBox(width: 6),
              Text(
                context.l10n.tr('reading_title'),
                style: theme.textTheme.labelSmall?.copyWith(color: tint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
          ),
          if (mood.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.tr('mood_overall', {'mood': mood}),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// 术语 → 人话的对照表（v1.1.0）。
///
/// 术语被赶出了主阅读路径（只在折叠区的展开论述里出现），但**不能顺手删掉它们**——
/// 它们是"理论锚定"的载体。这张表是两者之间的桥：平时收起来不占地方，
/// 用户想查的时候一眼能看着人话解释。
class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.terms});

  final List<({String term, String plain})> terms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // 去掉 ExpansionTile 展开时默认画出的上下分隔线
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Icon(Icons.menu_book_outlined, size: 16, color: theme.hintColor),
              const SizedBox(width: 6),
              Text(
                context.l10n.tr('section_terms', {'n': '${terms.length}'}),
                style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
          children: terms
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.term,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(t.plain, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

/// 「想更准一点，可以补这几件事」。
///
/// v1.0.x 遇到材料不足会输出一句「无法判定」然后结束——用户读完什么也没得到，
/// 也不知道下一步该做什么。同一份缺口在这里被翻过来：**缺什么就问什么**，
/// 答完点一下用新信息重新解析。这比"把不确定说成结论"诚实，也比它有用。
class _OpenQuestionsCard extends StatelessWidget {
  const _OpenQuestionsCard({required this.questions, required this.onAnswer});

  final List<({String question, String why})> questions;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.tr('section_questions'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...questions.map((q) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('· ${q.question}', style: theme.textTheme.bodyMedium),
                      if (q.why.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 10, top: 2),
                          child: Text(
                            q.why,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ),
                    ],
                  ),
                )),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAnswer,
                icon: const Icon(Icons.edit_note, size: 16),
                label: Text(context.l10n.tr('reanswer_reanalyze')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条解读。
///
/// v1.1.0 的三层分工，正好对应这张卡的三块：
/// ① **主阅读路径**（不折叠）= 人话结论 + 置信度 + 原文证据。
///    置信度刻意留在外面：可读性不能以牺牲可信度为代价（框架第四节的要求）。
///    证据也刻意留在外面：结论挂在原文片段上供核对，是本产品的立身之本。
/// ② **折叠区** = 机制名（theory）+ 展开论述（术语在这一层）。
///    机制名是给"想深究的人"看的，不该占据第一眼。
/// ③ **老记录降级**：v1.0.x 的条目没有 point，主文案直接用 content ——
///    读起来还是术语味，但至少不是空白，历史记录不会因框架升级而消失。
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.item});

  final AnalysisItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = item.normalizedConfidence;
    final color = switch (confidence) {
      // 这三个原色都是中深色，直接放深色主题的暗底上会读不清 → 走 Accents 按亮度取值
      'A' => Accents.confidenceA(theme.brightness),
      'B' => Accents.confidenceB(theme.brightness),
      _ => Accents.confidenceC(theme.brightness),
    };
    final confKey = switch (confidence) {
      'A' => 'conf_A',
      'B' => 'conf_B',
      _ => 'conf_C',
    };
    // 老记录的主文案就是 content，此时折叠区不再重复显示一遍
    final showContentInFold = item.hasPlainPoint && item.content.isNotEmpty;
    final hasFold = item.theory.isNotEmpty || showContentInFold;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 14, 14, hasFold ? 2 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(context.l10n.tr(confKey), style: TextStyle(fontSize: 11, color: color)),
            ),
            const SizedBox(height: 8),
            Text(item.plain, style: theme.textTheme.bodyLarge),
            if (item.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.tr('evidence', {'ev': item.evidence}),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (hasFold)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(
                    context.l10n.tr('fold_basis'),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                  ),
                  children: [
                    if (item.theory.isNotEmpty) ...[
                      Chip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        label: Text(item.theory, style: const TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (showContentInFold)
                      Text(item.content, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

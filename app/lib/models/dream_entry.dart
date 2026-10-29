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

import 'dart:convert';

import '../services/dream_tags.dart';
import '../services/fingerprint.dart';

/// 单条梦境记录。存储格式为 JSON（见 DreamRepository）。
class DreamEntry {
  final String id; // 形如 20260920-0712
  final DateTime recordedAt;
  final String? audioPath; // 原生平台为本地文件路径；web 端为 null（音频不落盘）
  final String transcript; // 口述转写文本（**可被用户手动编辑**）

  /// 识别器**原始**输出，创建后再不改动。
  ///
  /// 为什么要留着它：用户改错字是常态，改着改着发现"还不如识别出来的那版"
  /// 也是常态。没有这一份，一次误编辑就把识别结果永久覆盖掉了，无从对照、
  /// 无从还原。手输的记录没有"机器版本"，所以是 null。
  final String? rawTranscript;

  /// 用户的补充说明：近期状态、以及**对解析提问的回答**（v1.1.0 起界面可编辑）。
  ///
  /// 它直接进 User Prompt，是模型判断"这个意象是日间残余还是长期议题"的关键材料。
  /// v1.0.x 里这个字段在模型/prompt/解析链路上全通、**界面上却没有入口**——
  /// 结果是模型在输出里自己写「用户未填写近期状态，无法确认基线」（真机实测）。
  /// v1.1.0 把它接上界面：解析给出的提问（`open_questions`）就答在这里，
  /// 答完重新解析——输入指纹会发现 `recentContext` 变了，于是重解析是有意义的。
  final String recentContext;

  /// **醒来第一感觉**（结构化标签，见 [DreamTags]）。取 [DreamTags.moods] 里的 id，
  /// 形如 `calm` / `uneasy`；**老记录没有这个键 → null**，语义就是"没打过标签"。
  ///
  /// 为什么单独给它一个字段而不是混进 [flags]：它是**单选**，而且它有一个别的标签
  /// 都没有的位置——半梦半醒时、在录音之前就能答上来的东西。画面丢得最快，
  /// 情绪残留比画面持久得多，所以它常常是这条记录里**唯一可得的信息**
  /// （它同时也是解析的输入：情绪本就是梦境内容的一个维度）。
  final String? mood;

  /// 用户自行标注的梦属性（多选，取值域见 [DreamTags.flags]）。
  ///
  /// 老记录没有这个键 → 空列表，语义是"没标注过"，不要凭空显示任何标签。
  final List<String> flags;

  final String status; // recorded | analyzed | failed
  final String? analysisError;
  final Map<String, dynamic>? analysis; // 解析引擎原始 JSON（见框架文档第四节 Schema）

  /// **解析时用的那份原文**。
  ///
  /// 存在理由：语音识别会出错，用户会去改；改完之后旧的解析结果就对不上了 ——
  /// 而"解析结论挂在原文片段上"正是本产品的立身之本（见 README 第四节），
  /// 拿改之前的结论去对应改之后的原文，等于自己把这个根基破坏掉。
  /// 所以记下"当初拿哪段文字去解析的"，好让界面能判断结论是否已经过期。
  ///
  /// 老记录里没有这个字段（null）—— 那就当作"没过期"，不要凭空提示。
  final String? analyzedTranscript;

  /// **这次解析用到的全部输入**的指纹（见 [inputFingerprint]）。
  ///
  /// 存在理由：用户点「重新解析」时界面得说清楚"这一次重来有没有意义"。
  /// 模型温度不保证逐字可复现（见 LlmClient.complete 的说明），但**输入是否相同
  /// 是确定的**——这就够判断"这次重来是不是纯属重复花钱"了。
  /// 它覆盖原文、近期状态、**结构化标签（[mood] / [flags]）**、模型名、框架文档、
  /// 近期梦境摘要全部输入，任何一项变了指纹就变。
  ///
  /// 老记录为 null：界面要按"不知道"处理，不要拿它下任何判断。
  final String? analyzedFingerprint;

  const DreamEntry({
    required this.id,
    required this.recordedAt,
    this.audioPath,
    required this.transcript,
    this.rawTranscript,
    this.recentContext = '',
    this.mood,
    this.flags = const [],
    this.status = 'recorded',
    this.analysisError,
    this.analysis,
    this.analyzedTranscript,
    this.analyzedFingerprint,
  });

  /// 原文被用户改过了（与识别器原始输出不一致）。
  bool get transcriptWasEdited =>
      rawTranscript != null && rawTranscript != transcript;

  /// 原文在解析之后被改过了 → 现有结论已经对不上，建议重新解析。
  ///
  /// 判据刻意包含 `analysis != null`：只改过但**从没解析过**的记录不算过期，
  /// 否则每条刚改完的手输记录都会冒出一个"重新解析"提示，纯噪音。
  bool get analysisIsStale =>
      analysis != null &&
      analyzedTranscript != null &&
      analyzedTranscript != transcript;

  /// 这次重解析的输入与上次是否**完全相同**。
  ///
  /// 刻意不复用 [analysisIsStale] 那条路：过期提示只在"原文"变了才值得弹，
  /// 否则近期摘要每天随窗口滑动带来的变化会让每条记录都挂上"需重新解析"，
  /// 变成人人无视的噪音。指纹是给「用户主动点刷新」那一刻用的**一次性判断**，
  /// 它可以把范围放宽到全部输入，因为它不常驻界面。
  ///
  /// 老记录没有 [analyzedFingerprint] → 返回 false（"未知"就当"有变化"），
  /// 这样重解析不会被误判成"白花钱"而拦下来。
  bool analysisInputUnchanged(String currentFingerprint) =>
      analyzedFingerprint != null && analyzedFingerprint == currentFingerprint;

  // ---- 解析结果的类型化读取（供 UI 使用，容错优先）----
  List<AnalysisItem> get analysisItems {
    final list = analysis?['analysis_layer'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => AnalysisItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// 白话层（v1.1.0）。**必须先做类型检查再取字段**——
  /// 直接写 `analysis?['reading']?['headline']` 看着更短，但 `?[]` 只在接收者是
  /// Map 或 null 时合法：模型偶尔会把 reading 写成一个字符串，
  /// 那种脏数据会当场抛 NoSuchMethodError，把整个详情页打崩。
  Map<String, dynamic> get _reading {
    final r = analysis?['reading'];
    return r is Map ? Map<String, dynamic>.from(r) : const {};
  }

  /// 白话主结论（v1.1.0）。老记录没有这一层 → 空串，界面据此跳过白话卡。
  ///
  /// 为什么白话层单独一个字段而不是从条目里拼：它是**入口**。
  /// 用户打开详情页第一眼要看到"这个梦可能和什么有关"，而不是先读七条机制。
  String get readingHeadline => (_reading['headline'] ?? '').toString().trim();

  /// 白话情绪基调（v1.1.0）。
  String get readingMood => (_reading['mood'] ?? '').toString().trim();

  /// 这条记录带不带 v1.1.0 的白话层。
  bool get hasPlainReading => readingHeadline.isNotEmpty;

  /// 术语 → 人话（v1.1.0）。空 term / 空解释的条目一律丢掉——
  /// 半截数据只会让界面出现一个点了没反应的折叠项。
  List<({String term, String plain})> get terms {
    final list = analysis?['terms'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      return (
        term: (e['term'] ?? '').toString().trim(),
        plain: (e['plain'] ?? '').toString().trim(),
      );
    }).where((t) => t.term.isNotEmpty && t.plain.isNotEmpty).toList();
  }

  /// 需要用户补的信息（v1.1.0）—— 信息缺口被改造成「能回答的问题」。
  ///
  /// 这是 v1.1.0 最要紧的一处产品改动：v1.0.x 遇到材料不足会输出一句
  /// 「无法判定」，用户读完什么也没得到、也不知道下一步做什么；
  /// 现在同一个缺口变成一句可回答的提问 + 补上它能判断什么。
  List<({String question, String why})> get openQuestions {
    final list = analysis?['open_questions'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      return (
        question: (e['question'] ?? '').toString().trim(),
        why: (e['why'] ?? '').toString().trim(),
      );
    })        .where((q) => q.question.isNotEmpty).toList();
  }

  /// 「这次问完了」——模型明确表示当前材料已足以支撑结论（v1.1.2 新增字段）。
  ///
  /// 为什么要把它单独暴露出来：提问区在 [openQuestions] 为空时会被整块隐藏，
  /// 而"隐藏"与"问完了"在用户看来是一样的——都像是缺了什么。有了这个标志，
  /// 界面就能把"没有要你再答的了"当成一个**明确的结论**说出来。
  /// （护栏里"必须有提问"这条约束在结构上会惩罚诚实，见 README 规则 49。）
  bool get noMoreQuestions => analysis?['no_more_questions'] == true;

  List<String> get advice {
    final list = analysis?['advice_layer'];
    if (list is List) return list.map((e) => e.toString()).toList();
    return const [];
  }

  String get limitationsNote => (analysis?['limitations_note'] ?? '').toString();

  String get safetyFlag => (analysis?['safety_flag'] ?? 'none').toString();

  bool get hasTraumaFlag => safetyFlag == 'trauma_pattern';

  /// 界面显示用的「醒来第一感觉」文案（没打过 → null）。
  String? get moodLabel => DreamTags.moodLabel(mood);

  /// 界面显示用的标签文案。未知 id 在 [fromJson] 已经挡过一道，这里再兜一层——
  /// 界面代码不该关心"这个 id 认不认识"。
  List<String> get flagLabels => DreamTags.flagLabels(flags);

  /// 这条记录有没有真打过标签（决定界面显不显示标签区、prompt 加不加那一行）。
  bool get hasTags => !DreamTags.isEmpty(mood: mood, flags: flags);

  String get codingSummary {
    final cl = analysis?['coding_layer'];
    if (cl is! Map) return '';
    final chars = (cl['characters'] as List?)?.length ?? 0;
    final imgs = (cl['imagery'] as List?)?.length ?? 0;
    final inters = (cl['interactions'] as List?)?.length ?? 0;
    return '人物 $chars · 意象 $imgs · 交互 $inters';
  }

  DreamEntry copyWith({
    String? audioPath,
    String? transcript,
    String? rawTranscript,
    String? recentContext,
    String? mood,
    List<String>? flags,
    String? status,
    String? analysisError,
    Map<String, dynamic>? analysis,
    String? analyzedTranscript,
    String? analyzedFingerprint,
    /// 显式把 [audioPath] 清成 null。
    ///
    /// 没有这个参数就**清不掉**——`audioPath ?? this.audioPath` 遇到 null 只会
    /// 保留旧值。而"删掉音频、保留文字"正是清理功能要做的事：不清的话记录仍然
    /// 声称自己有音频（详情页照样显示"录音已保存在本机"），点播放却发现文件没了。
    bool clearAudioPath = false,
    /// 显式把 [mood] 清成 null（用户把已选的"醒来第一感觉"点掉了）。
    ///
    /// 同 [clearAudioPath] 的道理：没有这个开关就**清不掉**——
    /// `mood ?? this.mood` 遇到 null 只会保留旧值，用户会发现标签点掉了却还在。
    bool clearMood = false,
    /// 显式把 [analysisError] 清成 null。
    ///
    /// 同 [clearAudioPath] 的道理：解析**失败**后再解析**成功**，`??` 语义会
    /// 把上一次的失败原因一直留在记录里（`status` 已是 analyzed，`analysisError`
    /// 却还挂着"解析失败"）。现在已有结论时界面不显示它，所以肉眼看不见；
    /// 但记录本身在骗人，导出或将来复用这个字段时就会踩到。
    bool clearAnalysisError = false,
  }) {
    return DreamEntry(
      id: id,
      recordedAt: recordedAt,
      audioPath: clearAudioPath ? null : (audioPath ?? this.audioPath),
      transcript: transcript ?? this.transcript,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      recentContext: recentContext ?? this.recentContext,
      mood: clearMood ? null : (mood ?? this.mood),
      // 空列表天然能覆盖（`[] ?? old` 得到 `[]`），所以清空标签不需要额外的 clear 开关
      flags: flags ?? this.flags,
      status: status ?? this.status,
      analysisError: clearAnalysisError ? null : (analysisError ?? this.analysisError),
      analysis: analysis ?? this.analysis,
      analyzedTranscript: analyzedTranscript ?? this.analyzedTranscript,
      analyzedFingerprint: analyzedFingerprint ?? this.analyzedFingerprint,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'recorded_at': recordedAt.toIso8601String(),
        'audio_path': audioPath,
        'transcript': transcript,
        'raw_transcript': rawTranscript,
        'recent_context': recentContext,
        'mood': mood,
        'flags': flags,
        'status': status,
        'analysis_error': analysisError,
        'analysis': analysis,
        'analyzed_transcript': analyzedTranscript,
        'analyzed_fingerprint': analyzedFingerprint,
      };

  static DreamEntry fromJson(Map<String, dynamic> j) => DreamEntry(
        id: j['id'].toString(),
        recordedAt: DateTime.parse(j['recorded_at'].toString()),
        audioPath: j['audio_path']?.toString(),
        transcript: (j['transcript'] ?? '').toString(),
        // 老记录没有这个键 → null。[transcriptWasEdited] 会因此为 false，
        // 也就是"当作没改过" —— 这正是老数据该有的语义。
        rawTranscript: j['raw_transcript']?.toString(),
        recentContext: (j['recent_context'] ?? '').toString(),
        // 老记录没有这两个键 → 走规范化后得到 null / 空列表，
        // 语义正好是"没打过标签"（不凭空显示任何标签、prompt 里也不出那一行）。
        // 走 normalize* 而不是直接 toString：手改过的 JSON 里可能是任意值，
        // 未知 id 必须在这里就被挡掉，不能让它流到界面和 prompt 里。
        mood: DreamTags.normalizeMood(j['mood']),
        flags: DreamTags.normalizeFlags(j['flags']),
        status: (j['status'] ?? 'recorded').toString(),
        analysisError: j['analysis_error']?.toString(),
        analysis: j['analysis'] is Map
            ? Map<String, dynamic>.from(j['analysis'] as Map)
            : null,
        // 老记录没有这个键 → null，由 [analysisIsStale] 当作"没过期"处理
        analyzedTranscript: j['analyzed_transcript']?.toString(),
        // 老记录没有这个键 → null，[analysisInputUnchanged] 会一律返回 false
        analyzedFingerprint: j['analyzed_fingerprint']?.toString(),
      );

  String toJsonString() => jsonEncode(toJson());

  static DreamEntry fromJsonString(String s) =>
      fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// 生成记录 id：本地时间 YYYYMMDD-HHmm
  static String makeId(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${p2(t.month)}${p2(t.day)}-${p2(t.hour)}${p2(t.minute)}';
  }
}

/// 解析层的一条结论。
///
/// v1.1.0 起每条结论都必须带 [point]（一句没有术语的人话）——这是可读性的落点：
/// 用户主要读的就是这一句，机制名、置信度、原文证据都退到它旁边可展开的位置。
///
/// **[point] 为 null 表示这是 v1.0.x 的老记录**（那时没有这个字段）。
/// 此时 [plain] 回退到 [content]：读起来仍然是术语味的，但**至少不是空白**。
/// 历史记录不该因为框架升级就变成读不了的东西——降级要能读，不能消失。
class AnalysisItem {
  /// 人话结论（v1.1.0 新增；老记录为 null）
  final String? point;

  /// 展开论述（可含术语）—— 老记录里它同时充当"主文案"
  final String content;

  final String theory;
  final String confidence;
  final String evidence;

  const AnalysisItem({
    this.point,
    this.content = '',
    this.theory = '',
    this.confidence = '',
    this.evidence = '',
  });

  /// 主阅读路径上显示的那一句。
  String get plain {
    final p = point?.trim() ?? '';
    return p.isNotEmpty ? p : content;
  }

  /// 真的带 v1.1.0 的人话结论（而不是回退成 content）。
  bool get hasPlainPoint => (point?.trim() ?? '').isNotEmpty;

  /// 界面按 A/B/C 上色与写标签，取值不在枚举内时一律按 C 处理。
  String get normalizedConfidence {
    final c = confidence.trim().toUpperCase();
    return (c == 'A' || c == 'B') ? c : 'C';
  }

  static AnalysisItem fromJson(Map<String, dynamic> j) => AnalysisItem(
        // 注意这里不用 `?? ''`：要保留"字段本来就不存在"这个信息，
        // 界面才能区分"老记录"和"模型给了一句空话"。
        point: j['point']?.toString(),
        content: (j['content'] ?? '').toString(),
        theory: (j['theory'] ?? '').toString(),
        confidence: (j['confidence'] ?? '').toString(),
        evidence: (j['evidence'] ?? '').toString(),
      );
}

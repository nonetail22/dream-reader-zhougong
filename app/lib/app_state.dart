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

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'l10n/app_locale.dart';
import 'l10n/messages.dart';
import 'models/dream_entry.dart';
import 'services/analysis_service.dart';
import 'services/app_dirs.dart';
import 'services/audio_store.dart';
import 'services/cloud_transcriber.dart';
import 'services/dream_repository.dart';
import 'services/dream_tags.dart';
import 'services/llm_client.dart';
import 'services/prompt_builder.dart';
import 'services/settings_service.dart';
import 'services/sherpa_onnx_transcriber.dart';
import 'services/speech_mode.dart';
import 'services/transcriber.dart';
import 'theme/palettes.dart';

/// 简单的应用级状态容器（MVP 阶段不引入额外状态管理依赖）。
class AppController extends ChangeNotifier {
  final DreamRepository repository;
  final SettingsService settings;
  final AnalysisService analysis;

  AppController({
    required this.repository,
    required this.settings,
    required this.analysis,
    this.fileTranscriberFactory,
  });

  List<DreamEntry> entries = [];
  LlmConfig config = const LlmConfig(baseUrl: '', apiKey: '', model: '');
  bool busy = false;
  String? lastError;

  /// 夜间配色。默认深蓝夜——这个 App 的主要使用场景是凌晨醒来时。
  DreamPalette palette = DreamPalette.fallback;

  /// 用哪条路子把话变成字。默认离线（见 [SpeechMode.fallback] 的说明）：
  /// 只有它不依赖设备自带服务、不联网、不上传。
  SpeechMode speechMode = SpeechMode.fallback;

  /// 云端转写（BYOK）配置
  CloudAsrConfig asrConfig = const CloudAsrConfig();

  /// 界面语言。默认简体中文（见 [AppLocale.zhCN]）。
  AppLocale locale = AppLocale.zhCN;

  /// 识别完成后是否把录音留在本机。**默认开**（见 [SettingsService.loadKeepRecording]）。
  ///
  /// 注意它**不控制"录不录"**：离线/云端模式下音频本来就要录（识别需要它），
  /// 这个开关只管识别完删不删。系统识别模式下请看 [alsoRecordDuringSystemAsr]。
  bool keepRecording = true;

  /// 「系统识别」时是否**额外**录一份音频。默认关 ——
  /// 打开会让本应用占住麦克风、把系统识别静音（见
  /// [SettingsService.loadAlsoRecordDuringSystemAsr]）。
  bool alsoRecordDuringSystemAsr = false;

  /// 录音占用（设置页显示 + 超线提醒用）。由 [refreshAudioUsage] 刷新。
  AudioUsage audioUsage = AudioUsage.empty;

  /// 没有记录引用的音频路径。设置页的「管理录音」要**逐条列出来给用户听** ——
  /// 删之前得先知道要删的是什么，所以这里给的是路径而不是计数。
  /// 与 [audioUsage] 在同一次刷新里一起算出来，避免两次扫描结果互相矛盾。
  List<String> orphanAudioPaths = const [];

  /// 用户上次点「知道了」时的占用字节数；占用涨过一定比例才再提醒。
  int audioWarnDismissedBytes = 0;

  /// 现在该不该显示"录音占地方了"的提醒。
  ///
  /// 两个条件都满足才提醒：① 超过阈值；② 比用户上次忽略时**明显更大了**
  /// （多 10% 以上）。只满足 ① 的话，用户点一次"知道了"之后每次启动都还会看到，
  /// 很快就变成人人无视的噪音。
  bool get shouldWarnAudio => audioUsage.overWarnLine &&
      audioUsage.totalBytes > audioWarnDismissedBytes * 1.1;

  /// 测试 / 替身用的注入点：造一个「整段音频出字」的转写器。
  /// 传 null 就按当前 [speechMode] 造真实实现。
  final FileTranscriber Function(StatusSink? onStatus)? fileTranscriberFactory;

  Future<void> init() async {
    config = await settings.load();
    palette = DreamPalette.fromId(await settings.loadPaletteId());
    keepRecording = await settings.loadKeepRecording();
    alsoRecordDuringSystemAsr = await settings.loadAlsoRecordDuringSystemAsr();
    audioWarnDismissedBytes = await settings.loadAudioWarnDismissedBytes();
    speechMode = await settings.loadSpeechMode();
    locale = await settings.loadLocale();
    asrConfig = await settings.loadAsrConfig();
    await refresh();
    await refreshAudioUsage();
  }

  /// 切换配色：**先切主题再落盘** —— 落盘失败也不该让界面没反应。
  Future<void> setPalette(DreamPalette next) async {
    if (palette == next) return;
    palette = next;
    notifyListeners();
    await settings.savePaletteId(next.id);
  }

  /// 切换「识别完保留录音」：同样先改内存再落盘。
  Future<void> setKeepRecording(bool value) async {
    if (keepRecording == value) return;
    keepRecording = value;
    notifyListeners();
    await settings.saveKeepRecording(value);
  }

  /// 切换「系统识别时同时录一份」。
  Future<void> setAlsoRecordDuringSystemAsr(bool value) async {
    if (alsoRecordDuringSystemAsr == value) return;
    alsoRecordDuringSystemAsr = value;
    notifyListeners();
    await settings.saveAlsoRecordDuringSystemAsr(value);
  }

  /// 重新统计录音占用。
  ///
  /// 会读一遍音频目录并逐文件 stat —— 目录里通常只有几十个文件，够快；
  /// 但它确实碰磁盘，所以放在**改动之后**调用（删完记录/清完音频/进设置页），
  /// 不要放进 build。
  Future<void> refreshAudioUsage() async {
    try {
      final dir = await appAudioDir();
      // 引用集合与目录各取一次，两个统计共用 —— 分两次取的话，中间要是正好
      // 存下一条新记录，占用和"无主列表"就会互相矛盾。
      final referenced = _referencedAudio();
      orphanAudioPaths = listOrphanAudio(dir, referenced: referenced);
      audioUsage = measureAudioUsage(dir, referenced: referenced);
    } catch (_) {
      // web 端没有文件系统、或目录不可达：如实显示成 0，不因为统计失败把界面弄崩
      orphanAudioPaths = const [];
      audioUsage = AudioUsage.empty;
    }
    notifyListeners();
  }

  /// 删掉单个音频文件（「管理录音」里逐条清无主音频用）。
  Future<void> deleteAudioAt(String path) async {
    await deleteAudioFile(path);
    await refreshAudioUsage();
  }

  /// 所有记录引用着的音频路径。
  Set<String> _referencedAudio() => {
        for (final e in entries)
          if (e.audioPath != null && e.audioPath!.isNotEmpty) e.audioPath!,
      };

  /// 记下"用户已经知道了"，占用再明显变大之前不再提醒。
  Future<void> dismissAudioWarn() async {
    audioWarnDismissedBytes = audioUsage.totalBytes;
    notifyListeners();
    await settings.saveAudioWarnDismissedBytes(audioWarnDismissedBytes);
  }

  /// 删掉一条记录**以及它的录音文件**。
  ///
  /// 连带删音频是 0.3.3 补的：在这之前只删 JSON，音频文件会永远留在盘上、
  /// 再也找不到主人（记录没了，没有任何东西引用它）。开了"保留录音"的人
  /// 每删一条梦就多一个孤儿文件，而界面上完全看不出异常。
  Future<void> deleteEntry(String id) async {
    final target = entryById(id);
    await repository.delete(id);
    await deleteAudioFile(target?.audioPath);
    await refresh();
    await refreshAudioUsage();
  }

  /// 删掉某条记录的录音，但**保留记录本身**（文字是最重要的，音频只是证据）。
  Future<void> deleteEntryAudio(String id) async {
    final target = entryById(id);
    if (target == null || target.audioPath == null) return;
    await deleteAudioFile(target.audioPath);
    // copyWith 的 `?? this.audioPath` 清不掉，必须走 clearAudioPath，
    // 否则记录会继续声称自己有音频、点播放却发现文件没了。
    await repository.save(target.copyWith(clearAudioPath: true));
    await refresh();
    await refreshAudioUsage();
  }

  /// 清掉所有**无主**音频（没有任何记录引用的文件）。
  /// 返回删掉的个数。
  Future<int> purgeOrphanAudioFiles() async {
    final dir = await appAudioDir();
    final n = await purgeOrphanAudio(dir, referenced: _referencedAudio());
    await refreshAudioUsage();
    return n;
  }

  /// 删掉**全部**录音，记录与文字一条不动。返回删掉的个数。
  ///
  /// 这是个不可逆动作，界面必须先让用户确认；这里只负责把事做干净——
  /// 文件删掉、记录的 `audioPath` 一并清空。
  Future<int> deleteAllAudio() async {
    final dir = await appAudioDir();
    final paths = <String>[];
    try {
      paths.addAll(await listAudioFiles(dir));
    } catch (_) {}
    final n = await deleteAudioFiles(paths);
    for (final e in entries) {
      if (e.audioPath != null && e.audioPath!.isNotEmpty) {
        await repository.save(e.copyWith(clearAudioPath: true));
      }
    }
    await refresh();
    await refreshAudioUsage();
    return n;
  }

  /// 切换转写方式。先改内存再落盘，保证点下去界面立刻有反应。
  Future<void> setSpeechMode(SpeechMode next) async {
    if (speechMode == next) return;
    speechMode = next;
    notifyListeners();
    await settings.saveSpeechMode(next);
  }

  /// 切换界面语言。**先切再落盘**——落盘失败也不该让界面没反应。
  /// 切换语言只改内存 + notifyListeners，[MaterialApp] 监听着控制器，
  /// 会立即用新的 locale 重建（见 `main.dart`）；无需单独通知 Localizations。
  Future<void> setLocale(AppLocale next) async {
    if (locale == next) return;
    locale = next;
    notifyListeners();
    await settings.saveLocale(next);
  }

  Future<void> setAsrConfig(CloudAsrConfig next) async {
    asrConfig = next;
    notifyListeners();
    await settings.saveAsrConfig(next);
  }

  /// 按当前设置造一个「整段音频出字」的转写器。
  ///
  /// 放在控制器里而不是记录页里，是因为它依赖 [speechMode] 与 [asrConfig]
  /// 这两份设置；让页面自己去取配置、自己 new，配置就会有两个真相来源。
  FileTranscriber buildFileTranscriber({StatusSink? onStatus}) {
    final injected = fileTranscriberFactory;
    if (injected != null) return injected(onStatus);
    switch (speechMode) {
      case SpeechMode.offline:
        return SherpaOnnxTranscriber(onStatus: onStatus);
      case SpeechMode.cloud:
        return CloudTranscriber(config: asrConfig, onStatus: onStatus);
      case SpeechMode.system:
        // 系统识别不走这条路；真被调到就退化成离线，别崩。
        return SherpaOnnxTranscriber(onStatus: onStatus);
    }
  }

  /// 当前设置下的转写方式，在界面上怎么称呼
  String get speechModeLabel => speechMode.label;

  Future<void> refresh() async {
    entries = await repository.listAll();
    notifyListeners();
  }

  Future<void> saveConfig(LlmConfig next) async {
    config = next;
    await settings.save(next);
    notifyListeners();
  }

  /// 保存一条新记录（录音结束后调用）
  ///
  /// [rawTranscript] 是识别器的原始输出，只在**语音识别**这条路上传；
  /// 手动输入没有"机器版本"，留空即可。它不参与展示，作用是让用户改坏了
  /// 还能还原（见 [DreamEntry.rawTranscript]）。
  Future<DreamEntry> addEntry({
    required String transcript,
    String? rawTranscript,
    String? audioPath,
    DateTime? at,
    String recentContext = '',
    String? mood,
    List<String> flags = const [],
  }) async {
    final now = at ?? DateTime.now();
    final entry = DreamEntry(
      id: DreamEntry.makeId(now),
      recordedAt: now,
      audioPath: audioPath,
      transcript: transcript,
      rawTranscript: rawTranscript,
      recentContext: recentContext,
      mood: DreamTags.normalizeMood(mood),
      flags: DreamTags.normalizeFlags(flags),
    );
    await repository.save(entry);
    await refresh();
    return entry;
  }

  /// 按 id 取当前记录（列表是唯一真相来源，页面不自己缓存副本）。
  DreamEntry? entryById(String id) => entries.where((e) => e.id == id).firstOrNull;

  /// 用户手动修正原文 —— 语音识别会出错，得给用户一个改的机会。
  ///
  /// 只改原文，**刻意不自动重新解析**，两个理由：
  /// 1. 每次编辑都触发一次 BYOK 调用 = 花用户的钱，而"边想边改"会改很多次；
  /// 2. 旧结论该不该丢是用户的决定 —— 改一个字就跑掉原结论，用户就再也没法
  ///    对照"原来是怎么说的、结论是怎么来的"了。
  ///
  /// 改为让界面提示「原文已修改，建议重新解析」（见 [DreamEntry.analysisIsStale]），
  /// 由用户点一下决定。
  Future<void> updateTranscript(String id, String transcript) async {
    final current = entryById(id);
    if (current == null) return;
    if (current.transcript == transcript) return;
    await repository.save(current.copyWith(transcript: transcript));
    await refresh();
  }

  /// 用**重新识别**的结果覆盖原文（0.6.2）。
  ///
  /// 与 [updateTranscript]（手动编辑）的三点区别：
  /// - 同时写 [DreamEntry.rawTranscript]：机器输出要跟着这次识别一起更新，
  ///   否则详情页的「还原识别结果」还原的是上一个模型的旧话；
  /// - 不做「没变就不写」的短路——识别出同样的文字也是一次有效操作，
  ///   短路了用户会以为按钮坏了；
  /// - **不自动重新解析**：与手动改原文同一规矩（重解析花用户的钱），
  ///   旧的 [DreamEntry.analysisIsStale] 会因 transcript 变化自动亮起。
  Future<void> applyRetranscription(String id, String text, String raw) async {
    final current = entryById(id);
    if (current == null) return;
    await repository.save(
      current.copyWith(transcript: text, rawTranscript: raw),
    );
    await refresh();
  }

  /// 现在这份输入算出来的指纹（原文 / 近期状态 / 模型 / 框架文档 / 近期梦境摘要）。
  ///
  /// 与 [DreamEntry.analyzedFingerprint] 比对，就能回答"用户点这次刷新到底有没有意义"：
  /// 一致 → 模型看到的输入一字未改，重解析只是重复花一次钱。
  /// 界面必须走这个入口、不要自己拼 prompt —— 两边口径一旦不同，
  /// 界面就会永远报"输入变了"。
  Future<String> fingerprintOf(DreamEntry entry) async {
    final digest = await repository.recentDigest(excludeId: entry.id);
    return analysis.fingerprintFor(
      config: config,
      entry: entry,
      dreamHistoryDigest: digest,
      languageDirective: locale.analysisLanguageDirective,
    );
  }

  /// 用户补充「近期状态 / 对解析提问的回答」（v1.1.0）。
  ///
  /// 与 [updateTranscript] 同样是**只改输入、不自动重新解析**：
  /// 解析要花用户自己的钱，而且用户可能想一次把几个问题都答完再解析。
  /// 界面上的做法是答完由用户点「用新信息重新解析」。
  ///
  /// 这里**不必**清 [DreamEntry.analyzedFingerprint]：新指纹天然与旧的不同
  /// （`recentContext` 是指纹的输入之一），所以重解析会被正确判定为"输入变了"，
  /// 而不会被 0.3.5 那道「输入没变」的闸门拦下来。
  Future<void> updateRecentContext(String id, String recentContext) async {
    final current = entryById(id);
    if (current == null) return;
    if (current.recentContext == recentContext) return;
    await repository.save(current.copyWith(recentContext: recentContext));
    await refresh();
  }

  /// 改这条记录的结构化标签（[DreamEntry.mood] 醒来第一感觉 / [DreamEntry.flags]）。
  ///
  /// 与 [updateTranscript] / [updateRecentContext] 同一个规矩：**只改输入，
  /// 不自动重新解析**。标签是进 user prompt 的，改完得由用户自己点一下重解析
  /// —— 那要花他自己的钱，而"点标签"是个很轻的动作，不该顺带扣费。
  ///
  /// 这里**不必**清 [DreamEntry.analyzedFingerprint]：标签是指纹的输入之一，
  /// 新指纹天然与旧的不同，所以重解析会被正确判定为"输入变了"，
  /// 不会被 0.3.5 那道「输入没变」的闸门拦下来。
  ///
  /// [clearMood] 是"把已选的醒来第一感觉取消掉"——不给这个开关就清不掉，
  /// 因为 `mood ?? this.mood` 遇到 null 只会保留旧值（同 [DreamEntry.copyWith]）。
  Future<void> updateTags(
    String id, {
    String? mood,
    bool clearMood = false,
    List<String>? flags,
  }) async {
    final current = entryById(id);
    if (current == null) return;
    final next = current.copyWith(mood: mood, clearMood: clearMood, flags: flags);
    if (next.mood == current.mood && listEquals(next.flags, current.flags)) return;
    await repository.save(next);
    await refresh();
  }

  /// 触发解析（BYOK）。返回是否成功。
  Future<bool> analyzeEntry(DreamEntry entry) async {
    if (!config.isConfigured) {
      lastError = AppL10n.current.tr('err_no_model_config');
      notifyListeners();
      return false;
    }
    // ★ 解析是 BYOK 长耗时操作（最快 3 分钟、推理型 15 分钟），而且用户很可能在
    //   解析途中退出详情页、切到别的记录再回来。把"正在解析"写进**这条记录自己的
    //   status**（仅内存、不落盘）而不是只靠全局 busy：这样无论怎么导航、回来，
    //   界面都能从记录状态正确判断该显示"解析中"还是"结果"——不会卡在转圈，
    //   也不会因为全局标志的时序误判成失败。不落盘是为了避免应用被杀后留下
    //   一个永远"解析中"的僵尸状态（落盘的最终状态由下面的 save 负责）。
    _markParsing(entry.id);
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      final digest = await repository.recentDigest(excludeId: entry.id);
      // 解析内容跟随界面语言：把当前 locale 的「请使用 X 回答」指令塞进 system prompt。
      // zhCN 回落 null（见 [AppLocale.analysisLanguageDirective]），不会改动指纹。
      final outcome = await analysis.analyze(
        config: config,
        entry: entry,
        dreamHistoryDigest: digest,
        languageDirective: locale.analysisLanguageDirective,
      );
      final updated = outcome.ok
          ? entry.copyWith(
              status: 'analyzed',
              analysis: outcome.analysis,
              // 记下"这次解析用的是哪份原文"，之后用户改了原文就能看出结论已过期
              analyzedTranscript: entry.transcript,
              // 记下"这次解析吃进去的全部输入"，用户点刷新时才知道重来有没有意义
              analyzedFingerprint: outcome.fingerprint,
              // 上一次失败的原因必须清掉：现在已经有结论了，再挂着"解析失败"是记录在骗人
              clearAnalysisError: true,
            )
          // 失败也**保留上一次的结论**：覆盖掉用户已有的好结论、只因为这次重解析
          // 没成功，比"没解析过"更糟（判据守两个方向——宁可放过、别把真东西丢掉）。
          // 失败原因单独记在 analysisError，界面会作为横幅提示，不至于静默。
          : entry.copyWith(status: 'failed', analysisError: outcome.error);
      await repository.save(updated);
      if (!outcome.ok) lastError = outcome.error;
      await refresh();
      return outcome.ok;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 把某条记录标记为"正在解析"（仅改内存中的列表，不落盘；见 [analyzeEntry]）。
  void _markParsing(String id) {
    entries = entries
        .map((e) => e.id == id
            ? e.copyWith(status: 'parsing', clearAnalysisError: true)
            : e)
        .toList();
  }
}

/// 供 UI 层拿到的 PromptBuilder 单例（由 main 注入）
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController super.notifier, required super.child});

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未挂载');
    return scope!.notifier!;
  }
}

/// 便于测试与预热的解析服务构造
AnalysisService buildAnalysisService(PromptBuilder builder) =>
    AnalysisService(llm: LlmClient(), promptBuilder: builder);

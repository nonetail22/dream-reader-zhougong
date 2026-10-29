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
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../app_state.dart';
import '../l10n/app_localizations.dart';
import '../l10n/messages.dart';
import '../models/dream_entry.dart';
import '../services/audio_level.dart';
import '../services/dream_tags.dart';
import '../services/recorder_service.dart';
import '../services/speech_mode.dart';
import '../services/transcriber.dart';
import 'offline_model_dialog.dart';
import 'dream_detail_page.dart';

/// 「说话」按钮的标称直径。
///
/// 原来是 132 —— 半梦半醒时眼睛可能还没睁开、也未必找得到眼镜，
/// 目标太小会按空；按用户要求放大到 **2 倍**。
const double _kTalkButtonNominal = 264;

/// 再怎么挤也不小于这个尺寸，否则按钮就失去「闭着眼也能按到」的意义了。
const double _kTalkButtonFloor = 120;

/// 短于这个时长就认为"没真的说话"，不去识别。
///
/// 改成一键切换之后，**误触的代价变大了**：以前是"按着才录"，现在是
/// "点一下就一直录"，点错了再点一下收尾，就会得到一段几乎没声音的录音。
/// 而识别模型遇到近乎静音的输入**不会返回空，会编出一句像模像样的话**
/// （这个坑真实踩过，见 README 第七节），用户就会把幻觉当成自己的梦存下来。
///
/// **注意它只挡"手滑点两下"，不挡"点了开始却没说话"。** 后者录了好几分钟也有，
/// 时长判据一定过得去 —— 真正能挡住它的是**输入电平判据**
/// （`services/audio_level.dart`，在 [_transcribePending] 里生效）。
/// 两道闸各管一段，别以为有了这个就够了（2026-09-21 模拟器实测打脸过一次）。
const Duration _kMinRecordedLength = Duration(milliseconds: 800);

/// 编辑原文后延迟多久写回磁盘。
///
/// 边想边改会触发很多次变更，每次落盘都写文件没必要；但也不能等"失焦"
/// 才写 —— 用户改完随手锁屏就丢了。取 700ms：打字停顿即落盘。
const Duration _kEditCommitDelay = Duration(milliseconds: 700);

/// 记录页当前处于哪一段。用显式状态机而不是几个 bool，
/// 是因为"正在识别"和"正在录音"必须互斥——以前的布尔组合可以同时为真，
/// 于是按钮会出现"看起来能按、按下去什么也不发生"的中间态。
enum _Phase { idle, recording, working }

/// 记录页：点一下开始说，再点一下结束。
///
/// **为什么是"点一下"而不是"按住不放"**（2026-09-21 按用户反馈改）：
/// 按住期间只要有人松手，这次记录就结束了 —— 而说梦说到一半停下来想一想
/// 是最自然不过的事，用户会下意识松手，于是整条记录就断了。改成点击切换后，
/// 中间想停多久都行，说完了再点一下结束。
///
/// 曾经用按住方式是有理由的（避开 `onLongPress` 约 500ms 的判定延迟，
/// 免得头几个字被吃掉）；但点击式**没有这个延迟**，那个理由自然消失。
/// 代价是"误触一次就一直在录"，所以补了两道：录音中的计时显示（随时看得出
/// 还在录）与过短录音拦截（见 [_kMinRecordedLength]）。
///
/// 三条转写路子在这里汇合，按 [SpeechMode] 分流：
/// - `system`：识别服务自己开麦克风，边说边出字；
/// - `offline` / `cloud`：本应用先录一整段 WAV，结束后交给转写器出字。
///
/// 分流的关键差异是**谁占麦克风**，这一点本项目栽过跟头（见 README 中华为那次），
/// 所以代码里刻意把它写成显式分支，而不是藏在几个 if 里。
class RecordPage extends StatefulWidget {
  const RecordPage({
    super.key,
    this.recorder,
    this.liveTranscriber,
    this.fileTranscriber,
    this.onDeferToTimeline,
  });

  final RecorderService? recorder;

  /// 「边说边出字」的转写器（系统识别）。测试可注入替身。
  final LiveTranscriber? liveTranscriber;

  /// 「整段出字」的转写器（离线/云端）。留空则按当前设置现造。
  final FileTranscriber? fileTranscriber;

  /// 用户选择「不立即解析」时调用：把这条记录的 id 交给上层，
  /// 由上层切到梦境列表并把它标亮。可空（测试 / 独立使用时）不影响保存。
  final void Function(String)? onDeferToTimeline;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  late final RecorderService _recorder =
      widget.recorder ?? RealRecorderService();
  late final LiveTranscriber _live =
      widget.liveTranscriber ?? SystemTranscriber();

  /// 缓存的 [AppController]。
  ///
  /// 在 [didChangeDependencies] 里取（不能放 `initState`，那里还不允许
  /// `dependOnInheritedWidgetOfExactType`）：[_flushEdit] 会在 `dispose()` 里被调用，
  /// 而那时 `context` 已经 deactivated，再调 `AppScope.of(context)` 会抛
  /// "Looking up a deactivated widget's ancestor is unsafe"。新流程里用户选
  /// 「否，去梦境列表」会触发 HomeShell 切 Tab 卸载本页 → dispose，没有这层缓存
  /// 就会在切页瞬间崩。controller 实例在 App 生命周期内稳定，缓存一份没问题。
  AppController? _controller;

  /// 懒建：它要读设置（离线/云端配置），而设置页随时可能被改。
  FileTranscriber? _file;
  SpeechMode? _fileBuiltFor;

  /// 本次是否真的开起了录音（决定结束时要不要去 stop）
  bool _recorderActive = false;

  _Phase _phase = _Phase.idle;

  /// 是否已确认**这台设备没有系统语音识别能力**。
  ///
  /// 判定依据只有一个：转写器抛出了 [TranscriberException]（设备级不可用），
  /// 而不是任何偶发错误。一旦确认，就把入口从"说话"改成能真正出结果的动作。
  ///
  /// 刻意**不在启动时探测**：探测会触发麦克风权限弹窗，而权限本来就该在
  /// 用户第一次真的要用时再要。改成「第一次失败后学会」，还能自愈。
  bool _speechBroken = false;

  String _liveText = '';
  String? _error;

  /// 正在做什么（首次准备模型 / 加载模型 / 上传 / 识别中）。
  /// 没有它，结束后的几秒钟在用户眼里就是"卡死了"。
  String? _status;

  /// 已经录好、但还没成功转成文字的音频。失败后可以原地重试，
  /// 不用让用户在凌晨三点再说一遍同一段梦。
  String? _pendingAudio;

  /// 刚识别出来、正显示在上方框里的那条记录。
  ///
  /// 有它才能把用户的改动写回**同一条**记录 —— 否则"改原文"就会变成
  /// 新建一条，凭空多出一条重复的梦。
  String? _currentEntryId;

  /// 上方框里的文字。识别结果与用户的手动修改共用这一个控制器。
  final TextEditingController _transcript = TextEditingController();

  /// 本次要随记录一起存下的「醒来第一感觉」（[DreamTags.moods] 的 id）。
  ///
  /// 它是**页面级的暂存值**，不是某条记录的回读值：用户可以在录音前先点，
  /// 也可以录完再点，保存那一刻取当前值。
  String? _mood;

  /// 这个 [_mood] 是否已经被"用掉"（随上一次保存落盘了）。
  ///
  /// 存在的唯一理由是解决一个会**写脏数据**的问题：
  /// 页面是常驻的，同一次会话里连录两条梦时，如果只靠 `_mood` 一个值，
  /// 第二条梦会**静默继承**第一条的"不安"——而用户什么提示都没看到。
  /// 拆成两个值之后行为就明确了：
  /// - 点色块 → 明确是"为下一条梦选的"，`_moodCommitted = false`；
  /// - 保存成功 → 标记已用掉，但**仍然显示**（否则用户会以为标签丢了）；
  /// - 下一次点「开始录音」→ 因为已用掉，清空，下一条梦从空白开始。
  bool _moodCommitted = false;

  /// 录音计时：既是"还在录"的持续证据，也让用户敢放心中途停顿。
  Timer? _tick;
  int _elapsedSeconds = 0;

  /// 真实录音时长，单独用秒表量。
  ///
  /// 不用 [_elapsedSeconds] 兼任：那个是每秒递增的整数，拿它判"够不够
  /// [_kMinRecordedLength]"会把阈值悄悄变成约 1 秒，而且结果还取决于
  /// 计时器首次触发的抖动（0.9 秒与 1.1 秒可能得到同一个读数）。
  /// 拦截幻觉输入这件事上，判据必须是真的。
  final Stopwatch _rec = Stopwatch();

  /// 编辑落盘的防抖计时器。
  Timer? _commitDebounce;

  @override
  void initState() {
    super.initState();
    // 识别服务的错误必须冒到界面上：以前它是被 `onError: (_) {}` 吞掉的，
    // 用户只看到「没识别到内容」，完全无从判断是权限、麦克风还是设备不支持。
    _live.onError = _onTranscriberError;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 此处 context 处于活跃态，可以取 AppScope（initState 里还不行）。
    // 缓存到 [_controller]：dispose 时 context 已失效，不能再调 AppScope.of。
    _controller = AppScope.of(context);
  }

  void _onTranscriberError(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _onStatus(String? message) {
    if (mounted) setState(() => _status = message);
  }

  void _startTick() {
    _tick?.cancel();
    _elapsedSeconds = 0;
    _rec
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _stopTick() {
    _rec.stop();
    _tick?.cancel();
    _tick = null;
  }

  /// 用户在上方框里改了字 → 防抖写回磁盘。
  void _onTranscriptChanged(String value) {
    final id = _currentEntryId;
    if (id == null) return;
    _commitDebounce?.cancel();
    _commitDebounce = Timer(_kEditCommitDelay, () async {
      if (!mounted) return;
      await AppScope.of(context).updateTranscript(id, value.trim());
    });
  }

  /// 把编辑立刻落盘（离开页面前调用，避免防抖还没到就走了）。
  Future<void> _flushEdit() async {
    _commitDebounce?.cancel();
    _commitDebounce = null;
    final id = _currentEntryId;
    if (id == null) return;
    final text = _transcript.text.trim();
    if (text.isEmpty) return; // 空原文不写，等同没改
    // 用缓存的 [_controller]，因为本方法也会在 `dispose()` 里被调用，
    // 那时 context 已失效，不能走 AppScope.of(context)。
    await _controller!.updateTranscript(id, text);
  }

  /// 取回刚存下的那条记录（编辑与"是否过期"判断都以磁盘上的为准）。
  DreamEntry? _currentEntry(AppController c) {
    final id = _currentEntryId;
    if (id == null) return null;
    return c.entryById(id);
  }

  /// 按当前设置取（必要时新建）整段转写器。
  FileTranscriber _ensureFileTranscriber(AppController c) {
    final existing = _file;
    if (existing != null && _fileBuiltFor == c.speechMode) return existing;
    existing?.dispose();
    final next =
        widget.fileTranscriber ?? c.buildFileTranscriber(onStatus: _onStatus);
    next.onError = _onTranscriberError;
    _file = next;
    _fileBuiltFor = c.speechMode;
    return next;
  }

  Future<void> _start() async {
    if (_phase != _Phase.idle) return;
    final controller = AppScope.of(context);
    // 上一次的改动可能还在防抖队列里，先落盘再开始新的
    await _flushEdit();
    await _discardPending();
    setState(() {
      _phase = _Phase.recording;
      _liveText = '';
      _error = null;
      _status = null;
      // 新一次录音与上一条记录脱钩：编辑要作用在"当前这条"上，
      // 不脱钩的话用户改着改着会被写回上一条。
      _currentEntryId = null;
      _transcript.clear();
      // 上一次的「醒来第一感觉」已经随上一条记录落盘了 → 清空，下一条梦从空白开始。
      // 只清"已用掉"的那种：用户刚点完色块就按录音时，那是为这一条选的，不能丢。
      if (_moodCommitted) {
        _mood = null;
        _moodCommitted = false;
      }
    });
    _startTick();
    // 触觉确认：半梦半醒、可能还没睁眼时，「震一下」比视觉更可靠
    HapticFeedback.mediumImpact();

    if (controller.speechMode.needsRecording) {
      // ★ 离线 / 云端：音频必须由我们自己录下来。
      // 这条路上不存在麦克风争用——整段时间里只有我们在采集。
      try {
        await _recorder.start(
          'tmp-${DateTime.now().millisecondsSinceEpoch}',
          format: AudioCaptureFormat.wav16k,
        );
        _recorderActive = true;
      } catch (e) {
        _stopTick();
        if (mounted) {
          setState(() {
            _phase = _Phase.idle;
            _error = context.l10n.tr('mic_error', {'e': e.toString()});
          });
        }
      }
      return;
    }

    // ★★ 系统识别这条路，两行代码的顺序是华为那次问题的根因所在，别想当然地调换。
    //
    // 系统语音识别服务是**独立进程**，它要自己开麦克风采集；而 Android 10+
    // 只允许一个应用采集音频，且**前台应用优先**。所以只要本应用先用
    // `record` 插件开起 AudioRecord，识别服务就被静音 ——
    // 表现就是「说了话，却一个字都识别不出来」，而且不报错。
    //
    // 结论：**默认让识别独占麦克风**。想要音频文件的人可在设置里显式打开
    // 「系统识别时同时录一份」（默认关），并接受识别可能失效（那里写明了代价）。
    //
    // 这里读的是 alsoRecordDuringSystemAsr，**不是** keepRecording。后者只管
    // "识别完留不留"——而这条路上音频压根不是我们录的（是系统录的），留不留谈不上。
    // 0.3.3 拆开关之前两者共用同一个 save_audio，正是这个混淆的根源。
    if (controller.alsoRecordDuringSystemAsr) {
      try {
        await _recorder.start(
          'tmp-${DateTime.now().millisecondsSinceEpoch}',
          // 系统识别这条路默认不录（麦克风要让给识别服务）；开了「同时录一份」
          // 时，这里特意录 **WAV16k** 而不是 m4a——只有 WAV 才能被下面的
          // `analyzeWavFile` 解析，m4a 解析不了会被当成"判不了"而直接放过，
          // 那道静音闸就形同虚设。
          format: AudioCaptureFormat.wav16k,
        );
        _recorderActive = true;
      } catch (e) {
        // 录音失败不该拖累转写——识别才是主功能
        if (mounted) setState(() => _error = '$e');
      }
    }

    try {
      await _live.start((text, _) {
        if (!mounted) return;
        setState(() => _liveText = text);
      });
    } catch (e) {
      // 起不来就把已经开着的录音一并收干净，别让麦克风一直被占着
      await _stopRecorderQuietly();
      _stopTick();
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          // 设备级不可用 → 记下来，把大按钮切成"写下来"并推荐离线模式
          if (e is TranscriberException) _speechBroken = true;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _stop() async {
    if (_phase != _Phase.recording) return;
    final controller = AppScope.of(context);
    _stopTick();

    if (controller.speechMode.needsRecording) {
      final folding = context.l10n.tr('status_folding');
      setState(() {
        _phase = _Phase.working;
        _status = folding;
      });
      String? path;
      try {
        path = await _recorder.stop();
      } catch (e) {
        if (mounted) setState(() => _error = context.l10n.tr('stop_rec_fail', {'e': e.toString()}));
      }
      _recorderActive = false;
      if (!mounted) return;
      if (path == null) {
        setState(() {
          _phase = _Phase.idle;
          _status = null;
          _error ??= context.l10n.tr('no_file');
        });
        return;
      }
      // 太短就不送去识别：模型在近乎静音的输入上会**编出一句像模像样的话**，
      // 与其显示幻觉，不如直说"这段没听到内容"。
      if (_rec.elapsed < _kMinRecordedLength) {
        final secs = (_rec.elapsedMilliseconds / 1000).toStringAsFixed(1);
        await _deleteQuietly(path);
        if (!mounted) return;
        setState(() {
          _phase = _Phase.idle;
          _status = null;
          _error = context.l10n.tr('too_short', {'secs': secs});
        });
        return;
      }
      _pendingAudio = path;
      await _transcribePending(controller);
      return;
    }

    setState(() => _phase = _Phase.working);

    // 先停转写：它会回吐最后一次 finalResult，丢了可惜
    try {
      await _live.stop();
    } catch (_) {}

    String? audioPath;
    if (_recorderActive) {
      _recorderActive = false;
      try {
        audioPath = await _recorder.stop();
      } catch (_) {}
    }

    final text = _liveText.trim();
    if (text.isEmpty) {
      // 把识别服务报的原始原因带出来 —— 只说「没识别到内容」等于什么都没说
      final why = _live.lastError;
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _error = why == null
              ? context.l10n.tr('no_content') + context.l10n.tr('no_content_tip')
              : '$why\n${context.l10n.tr('no_content_tip')}';
        });
      }
      return;
    }

    // 系统识别这条路，默认不录音频（麦克风要让给识别服务，见 [_start] 的说明），
    // 没有输入可校验；只有用户显式开了「系统识别时同时录一份」才有 [audioPath]。
    // 有音频时，先按和离线路同一道闸量一遍"有没有人说话"——识别服务在几乎没声音
    // 时也可能吐出一些词（尤其开了 partialResults 的流式模式），不校验就会把
    // 这些乱七八糟的内容当真存下来。
    if (audioPath != null) {
      final level = analyzeWavFile(audioPath);
      if (level != null && level.seemsSilent) {
        if (!controller.keepRecording) await _deleteQuietly(audioPath);
        if (mounted) {
          setState(() {
            _phase = _Phase.idle;
            _status = null;
            _error = context.l10n.tr('silent_error_main') +
                (controller.keepRecording
                    ? context.l10n.tr('silent_error_kept')
                    : '');
          });
        }
        return;
      }
      if (level != null && level.lowConfidence) {
        // 听到了一些声音、但不太像人说话：仍存下来（别丢真实但很短的语音），
        // 但不自动解析、并提示用户核对。
        await _saveEntry(controller, text, audioPath,
            rawTranscript: text, promptAnalyze: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.tr('lowconf_warn'))),
          );
        }
        return;
      }
    }

    await _saveEntry(controller, text, audioPath, rawTranscript: text);
  }

  /// 把已录好但尚未转写的音频交给当前的整段转写器。
  ///
  /// 单独抽出来是为了支持「重试识别」：上传失败、模型首次加载失败这类问题
  /// 都是可重试的，没道理让用户在凌晨三点把同一段梦再说一遍。
  Future<void> _transcribePending(AppController controller) async {
    final path = _pendingAudio;
    if (path == null) return;

    // ★ 送识别之前先看**输入**。
    //
    // 识别模型遇到近乎静音的输入**不会返回空，而是会编出一句像模像样的话**。
    // 这个坑踩过两次（见 README 第七节）：验证脚本里一次，改成点击式录音后
    // 又在应用里复现了一次——「点开始 → 忘了说话 → 再点结束」时长判据过得去，
    // 那句编造的话就被当成一条梦境记录存了下来。对一个卖点是"可查证"的梦境
    // 应用来说，最坏的失败就是**用户把模型编的话当成自己的梦**。
    //
    // 放在这里（而不是放在各个转写器内部）有两个额外好处：
    // 1. 离线与云端两条路共用同一道闸，不会只堵一边；
    // 2. 判在 `_ensureFileTranscriber` **之前**，静音录音连模型加载都不必开始。
    //
    // `analyzeWavFile` 返回 null 表示"判不了"（不是 WAV / 截断），此时**放过**：
    // 宁可漏判一次静音，也绝不因为解析器的问题丢掉用户真实说的话。
    // ★ 0.7.1 起放进后台 isolate：analyzeWavFile 是整文件同步扫描（纯 Dart），
    // 几十分钟的长录音在主 isolate 上会冻住界面一秒上下——与识别管线的
    // 同款病，同一次治掉。判据本体仍是 audio_level.dart 那一份。
    // 回退：flutter_tester（widget 测试环境）不支持 spawn isolate，落回同步；
    // 真机上 spawn 不会失败，回退分支只在测试里走。
    SpeechPresence? level;
    try {
      level = await Isolate.run(() => analyzeWavFile(path));
    } on ArgumentError {
      level = analyzeWavFile(path);
    }
    // ★ 每一次录音都记一条电平，**不只是判成静音的时候**。
    //
    // 0.4.4 之前只在"判成静音"那个分支里打印，于是最要紧的那种情况——
    // 闸门放过了一段其实没人在说话的录音、模型编出一句话存下来——**日志里
    // 一点痕迹都没有**。这个毛病只能靠用户的听感发现，而听感说不清电平。
    // 现在两种结果都留档：真机上再出问题时，`峰值 / 噪声底 / 有声帧占比`
    // 三个数直接说明闸门当时是怎么判的，不必再猜。
    debugPrint(level == null
        ? '[DreamReader] 录音电平判不了（不是 16-bit PCM WAV，或短到估不出噪声底），'
            '按放过处理'
        : '[DreamReader] 录音电平：${level.summary}'
            '${level.seemsSilent ? ' → 判为没人说话，不送识别' : ' → 送识别'}');
    if (level != null && level.seemsSilent) {
      // 删不删要跟正常路径一个规矩：设置里开了「保留录音」就留着。
      // 这里的判断本来就可能是误判（阈值再保守也是阈值），而**用户说的话
      // 一旦删掉就拿不回来了**——留着，他还能回听确认是不是真没说。
      // 这段音频没挂到任何记录上，所以它只会出现在「设置 → 录音文件 → 管理」
      // 的「没有记录引用的录音」里（0.3.3 起那个列表可以逐条回听）。
      if (!controller.keepRecording) await _deleteQuietly(path);
      // 同一段静音重试多少次还是静音 → 不给无意义的重试入口
      _pendingAudio = null;
      if (!mounted) return;
      // 文案在 await 前抓好（Isolate.run 引入了异步间隙，跨间隙用 context 会触发 lint）
      final silentMsg = context.l10n.tr('silent_error_main') +
          (controller.keepRecording ? context.l10n.tr('silent_error_kept') : '');
      setState(() {
        _phase = _Phase.idle;
        _status = null;
        // 措辞别写成"几乎没有声音"：0.4.4 起判据是"有没有人说话"，
        // 被拦下的情形包括"环境有噪声（空调、风扇）但确实没人说话"——
        // 那时说"几乎没有声音"就是一句不老实的话。
        _error = silentMsg;
      });
      return;
    }

    // Isolate.run 是异步间隙：之后还要用 context（ensureOfflineModel /
    // 各处文案），先确认页面还活着。
    if (!mounted) return;

    if (controller.speechMode == SpeechMode.offline) {
      // 0.6.0 起模型不预装：没下载就先弹窗确认并下载（进度见对话框）。
      // 用户拒绝或下载失败 → 不识别，但**不清掉待转写音频**：能走到这里
      // 说明电平闸已放过、多半是真话，删了就拿不回来；留在 _pendingAudio 里，
      // 下载完点重试即可。
      final ok = await ensureOfflineModel(context);
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.idle;
          _status = null;
          _error = context.l10n.tr('offline_dl_cancelled');
        });
        return;
      }
    }
    if (!mounted) return;

    final transcriber = _ensureFileTranscriber(controller);
    // 在 await 之前取好文案：跨异步间隙用 context 会触发 lint，而这条文案只依赖
    // transcriber.label，与异步结果无关。
    final notReady =
        context.l10n.tr('transcriber_not_ready', {'label': transcriber.label});
    if (mounted) {
      final working = context.l10n.tr('box_working');
      setState(() {
        _phase = _Phase.working;
        _error = null;
        _status ??= working;
      });
    }
    try {
      final issue = await transcriber.readyIssue();
      if (issue != null) {
        throw TranscriberException(notReady, hint: issue);
      }
      final text = await transcriber.transcribe(path);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        setState(() {
          _phase = _Phase.idle;
          _status = null;
          _error = context.l10n.tr('recognize_empty');
        });
        return;
      }
      final keep = controller.keepRecording;
      // level 在上方算过：seemsSilent 已在上一个分支拦掉，这里只剩
      // "低置信"（听到了一些声音但离人声很远）的情况——仍存盘，但不自动解析、
      // 并提示用户核对，避免把模型在勉强输入上编的话当成真梦。
      final lowConf = level != null && level.lowConfidence;
      await _saveEntry(controller, text, keep ? path : null,
          rawTranscript: text, promptAnalyze: !lowConf);
      if (!keep) await _deleteQuietly(path);
      _pendingAudio = null;
      if (lowConf && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('lowconf_warn'))),
        );
      }
    } on TranscriberException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _status = null;
          _error = '$e';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _status = null;
          _error = context.l10n.tr('recognize_failed', {'e': e.toString()});
        });
      }
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  /// 保存识别结果，并把它留在上方框里让用户校对。
  ///
  /// **不再自动跳详情页**（2026-09-21 按用户反馈改）：识别错的地方就在眼前，
  /// 正是最想改的时候；一保存就跳走，反而要退回来才改得动。
  ///
  /// 落盘仍然是**立刻**的，没有改成"用户确认后才存"。理由是这条路径针对的是
  /// 凌晨半梦半醒：说完可能又睡过去了，**梦必须先落到盘上**，编辑只是锦上添花。
  /// 所以这里的设计是"先存下来，之后改的就是同一条"（靠 [_currentEntryId]）。
  Future<void> _saveEntry(
    AppController controller,
    String text,
    String? audioPath, {
    String? rawTranscript,
    bool promptAnalyze = true,
  }) async {
    final entry = await controller.addEntry(
      transcript: text,
      // 留一份识别器原始输出：用户改坏了能还原，也能对照"机器原来听成了什么"
      rawTranscript: rawTranscript,
      audioPath: audioPath,
      // 「醒来第一感觉」只管这一条 —— 存下去之后就不再是"待用"状态了
      mood: _mood,
    );
    if (!mounted) return;
    setState(() {
      _transcript.text = text;
      _liveText = text;
      _currentEntryId = entry.id;
      _phase = _Phase.idle;
      _status = null;
      // 已落盘，但**保留显示**：如果这里把色块清掉，用户会以为"我选的标签没存上"。
      // 真正的清空发生在下一次点「开始录音」时（见 [_start]）。
      _moodCommitted = true;
    });
    // 不再保存后**立刻自动解析**（2026-09-28 用户反馈）：那样用户还没来得及
    // 校对口述文本，解析就已经用未经编辑的原文跑掉了——既花 BYOK 额度，
    // 又产出对不上最终原文的"过期结论"。改为保存后把文本留在框里让用户校对，
    // 再询问是否解析（见 [_askAnalyze]）。
    // [promptAnalyze] 为 false 时（音频低置信度）不弹这个框：那句识别结果
    // 很可能本身就是错的，自动解析只会白花 BYOK 额度，交给用户自己决定。
    if (promptAnalyze) await _askAnalyze(controller, entry);
  }

  /// 保存成功后，询问用户是否**现在**解析这段梦境。
  ///
  /// 三个出口：
  /// - 「是，立即解析」→ 现在就解析（异步，不阻塞）；
  /// - 「否，去梦境列表」→ 跳到梦境列表并把这条标亮，用户稍后可从列表里再解析；
  /// - 点空白处关掉 → 留在记录页继续改文本，之后点「查看解析」再解析。
  ///
  /// 没配置模型时不弹这个框（弹了也解析不了），退回原来的"已保存"提示。
  Future<void> _askAnalyze(AppController controller, DreamEntry entry) async {
    if (!controller.config.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('saved_no_model'))),
        );
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('analyze_confirm_title')),
        content: Text(context.l10n.tr('analyze_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('analyze_confirm_no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('analyze_confirm_yes')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == true) {
      await controller.analyzeEntry(entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('analyze_started'))),
        );
      }
    } else if (choice == false) {
      // 否 → 跳到梦境列表并把这条标亮（用户稍后可从列表里再解析）
      widget.onDeferToTimeline?.call(entry.id);
    }
    // choice == null（点空白关闭）→ 留在记录页，用户可继续改文本
  }

  /// 手动输入兜底。
  ///
  /// 存在的理由：输入方式有三条，但没有一条是万无一失的——设备可能没有系统
  /// 语音服务，离线模型可能没释放成功，云端可能没网。没有这条兜底，
  /// 任意一环出问题整个 App 就在那一刻废掉了；而转写只是**输入方式之一**，
  /// 后面的时间线、AI 解析都不依赖它。
  ///
  /// 与语音路径**走同一套收尾**：存下来 → 文字留在框里可继续改 → 需要时再点
  /// 「查看解析」。不单独跳详情页，否则同一个页面会有两种截然不同的结束方式。
  Future<void> _manualInput() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualInputDialog(),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    final controller = AppScope.of(context);
    // 手输没有"机器版本"，rawTranscript 留空 —— 界面因此不会给"还原识别结果"
    await _saveEntry(controller, text.trim(), null);
  }

  /// 去看这条记录的解析结果。
  void _openDetail() {
    final id = _currentEntryId;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DreamDetailPage(entryId: id)),
    );
  }

  /// 设备没有系统识别时的一键解法：切到离线识别。
  /// 比让用户自己去设置页里找要靠谱得多——凌晨三点不该考搜索能力。
  Future<void> _switchToOffline() async {
    final c = AppScope.of(context);
    await c.setSpeechMode(SpeechMode.offline);
    // 设置变了下一次会按新模式重造转写器
    setState(() {
      _speechBroken = false;
      _error = null;
      _status = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('offline_switched'))),
    );
  }

  Future<void> _stopRecorderQuietly() async {
    if (!_recorderActive) return;
    _recorderActive = false;
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 开始新一次录音前，先把上一段没转成功的音频处理掉。
  ///
  /// 仍然由 [AppController.keepRecording] 说了算，**不是**无条件删：
  /// 用户在设置里明确说了"我的录音要留着"，本应用就不该反过来替他判定
  /// 哪一段算垃圾。留着不等于失控——它会在「设置 → 录音文件 → 管理」的
  /// 「没有记录引用的录音」里列出来，能回听、能手删，他知道自己有什么。
  Future<void> _discardPending() async {
    final path = _pendingAudio;
    _pendingAudio = null;
    if (path == null) return;
    final c = AppScope.of(context);
    if (!c.keepRecording) await _deleteQuietly(path);
  }

  @override
  void dispose() {
    // 走之前把还没落盘的编辑写掉 —— 否则"改完立刻切页"会丢改动
    _flushEdit();
    _tick?.cancel();
    _commitDebounce?.cancel();
    _transcript.dispose();
    _recorder.dispose();
    _live.cancel();
    _file?.dispose();
    // 有没转成功的音频就留着（用户可能下次进来还能用），但别留成孤儿：
    // 默认不留音频的人，这里也不留。
    final p = _pendingAudio;
    if (p != null) _deleteQuietly(p);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppScope.of(context);
    final mode = c.speechMode;
    final busy = _phase == _Phase.working;

    // 虚拟键盘是否弹起。
    //
    // ★ 这个判断是为了修一个真实 bug（2026-09-21 用户反馈）：
    // 点文本框准备改字时，键盘把 body 高度压掉约 300dp，而 Column 里那些
    // **固定高度**的东西（264dp 的大圆按钮、两行说明、底部一排按钮，合计约
    // 370dp）一步不让 —— `Expanded` 里的文本框区于是被压成**负值**，
    // 屏幕上只剩一个录音按钮，用户正在改的那句话反而看不见了。
    //
    // 修法是**让，而不是缩**：键盘一弹起，就把「录音」这一整套整体撤掉。
    // 用户此刻在做的是打字，录音按钮对他没用；收起键盘它原样回来。
    // 只把按钮缩小是不够的 —— 缩小仍然占着那一两百 dp，而文本框要的是全部空间。
    //
    // ★★ 判据**不能**用 `MediaQuery.viewInsetsOf(context)`。
    //
    // 本页挂在 `home_shell` 那个 Scaffold 的 body 里，而 Scaffold 在
    // `resizeToAvoidBottomInset: true`（默认）时**会把 body 的
    // `viewInsets.bottom` 抹掉** —— 它已经用"减小 body 高度"这种方式处理过键盘了，
    // 不需要下游再来一遍。于是在 body 里读它**永远是 0**，判断恒为 false。
    //
    // 0.3.4 的第一版就是这么写的：analyze 干净、157 项测试全绿、包也构建成功，
    // 一派"改好了"的样子；上机一 dump 才发现槽位根本没切 —— 键盘弹起时
    // 「开始录音」大按钮还在，文本框被压成 32dp 高的一条缝。
    // 改用 `MediaQueryData.fromView(View.of(context))`：从平台视图直接重建，
    // 绕开 Scaffold 的 removeViewInsets。→ README 第九节第 36 条。
    return Padding(
      padding: const EdgeInsets.all(20),
      // 按钮放大后要防两件事：窄屏放不下宽度、横屏放不下高度
      // （横屏时可用高度只剩约 300dp，固定 264 会直接顶爆 Column）。
      // 所以按可用空间取上限，标称值仍是 264。
      child: LayoutBuilder(
        builder: (context, constraints) {
          // ★★ 键盘判定**必须在 builder 里面算**，不能提到 build 方法里去。
          //
          // 本页在 home_shell 里是 `const RecordPage()`。键盘弹起时 Scaffold 确实
          // 会 rebuild 自己，但传下来的永远是**同一个 const 实例**，于是 Flutter
          // 在 `Element.updateChild` 里直接短路（`child.widget == newWidget`），
          // **本页的 `build` 根本不会再被调用** —— 提在外面的 keyboardUp 会一直
          // 停在初始的 false。
          //
          // 而 `LayoutBuilder` 的 builder 是由 RenderObject 在 constraints 变化时
          // 执行的：键盘弹起 → Scaffold 把 body 压矮 → constraints 变了 → builder
          // 一定重跑。所以只有放在这里才拿得到新值。
          //
          // 0.3.4 第二版就栽在这：上机 dump 出来的结果与第一版**逐字节相同**
          // （大按钮还在、编辑条没有），就是这么来的。→ README 第九节第 37 条。
          final keyboardUp =
              MediaQueryData.fromView(View.of(context)).viewInsets.bottom > 0;
          final buttonSize = math.min(
            _kTalkButtonNominal,
            math.max(
              _kTalkButtonFloor,
              math.min(constraints.maxWidth, constraints.maxHeight * 0.45),
            ),
          );
          // ★★ 下面五个槽位的**位置在两种状态下必须一模一样**，只换格子里的内容。
          //
          // 原因是 Column 靠「位置 + runtimeType + key」复用 Element：如果
          // `Expanded` 因为上面多一个少一个子项而挪了位置，它里面那个正握着焦点的
          // TextField 就会被连 FocusNode 一起重建 → 失焦 → 键盘收起 → 布局变回
          // 非键盘态 → 又重建 …… 用户看到键盘来回闪。
          // 所以槽位 0 / 2 / 3 一律用「同位置换 widget」，而不是 `if` 插入删除。
          return Column(
            children: [
              // ── 槽位 0：顶栏 ──
              // 键盘弹起时，那两行说明换成一条紧凑的编辑条：说明字在编辑时没人看，
              // 却要占掉约 60dp，正是文本框最缺的东西。
              keyboardUp
                  ? _editingBar(context)
                  : Column(
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          _titleFor(mode),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _hintFor(mode),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),

              // ── 槽位 1：醒来第一感觉（固定槽位，键盘弹起时留空占位）──
              //
              // 为什么不塞进录音区：那一片已经全是固定高度的元素
              // （264dp 大按钮 + 说明 + 一排按钮），窄屏上本来就紧，
              // 再塞一行进去会把 Column 顶爆。而且用户正在改字时这一行毫无用处，
              // 所以键盘弹起就留空，把高度让给文本框。
              //
              // ★ 它必须在两种状态下**都存在**（内容不同），不能写成 `if`：
              // Column 靠「位置 + runtimeType + key」复用 Element，少一个子项会让
              // 下面那个正握着焦点的 TextField 被重建 → 失焦 → 键盘收起 →
              // 布局变回去 → 又重建，用户看到键盘来回闪。
              keyboardUp ? const SizedBox.shrink() : _moodRow(theme),

              // ── 槽位 2：文本框（两种状态下位置都不动，焦点才保得住）──
              Expanded(
                child: SingleChildScrollView(
                  child: _transcriptBox(theme, mode),
                ),
              ),

              // ── 槽位 3：错误提示 ──
              _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                            if (_pendingAudio != null && !busy)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _transcribePending(AppScope.of(context)),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: Text(context.l10n.tr('retry_recognize')),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

              // ── 槽位 4：录音区 ──
              // 键盘弹起 = 用户正在改字，这一整套（大按钮、状态说明、底部按钮）
              // 整体让位，见 [keyboardUp] 的说明。
              keyboardUp
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        const SizedBox(height: 12),
                        if (busy)
                          _CircleFace(
                            size: buttonSize,
                            icon: Icons.hourglass_top,
                            fill: theme.colorScheme.surfaceContainerHighest,
                            foreground: theme.colorScheme.onSurfaceVariant,
                          )
                        else if (_speechBroken)
                          // 形状保持圆形大目标（凌晨闭眼也能按到），但改成一按即写。
                          _CircleActionButton(
                            size: buttonSize,
                            icon: Icons.edit_note,
                            onTap: _manualInput,
                          )
                        else
                          _TalkButton(
                            recording: _phase == _Phase.recording,
                            size: buttonSize,
                            onToggle:
                                _phase == _Phase.recording ? _stop : _start,
                          ),
                        const SizedBox(height: 10),
                        Text(
                          _captionFor(mode, busy),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                        // 识别完成后**不自动跳详情页**（跳走就没法改字了），
                        // 想看解析的人点这里过去。
                        if (_currentEntryId != null &&
                            !busy &&
                            !_speechBroken) ...[
                          const SizedBox(height: 2),
                          OutlinedButton.icon(
                            onPressed: _openDetail,
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: Text(context.l10n.tr('view_analysis')),
                          ),
                        ],
                        if (_speechBroken) ...[
                          const SizedBox(height: 4),
                          FilledButton.icon(
                            onPressed: _switchToOffline,
                            icon: const Icon(
                              Icons.offline_bolt_outlined,
                              size: 18,
                            ),
                            label: Text(context.l10n.tr('switch_offline')),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _speechBroken = false;
                              _error = null;
                            }),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(context.l10n.tr('retry_system')),
                          ),
                        ] else
                          TextButton.icon(
                            onPressed: busy ? null : _manualInput,
                            icon: const Icon(
                              Icons.keyboard_alt_outlined,
                              size: 18,
                            ),
                            label: Text(context.l10n.tr('manual_input_btn')),
                          ),
                        const SizedBox(height: 4),
                      ],
                    ),
            ],
          );
        },
      ),
    );
  }

  /// 「醒来第一感觉」——记录页上**唯一**的结构化标签。
  ///
  /// 为什么只放这一个、其余标签都推到详情页：画面丢得最快，而情绪残留比画面
  /// 持久得多——半梦半醒时"心里是慌的还是松的"答得上来，"你的梦讲了什么"
  /// 答不上来。所以它是此刻**唯一答得上来**的那一项。
  /// 噩梦 / 反复出现的梦这类要回过神想一想，放详情页更合适，
  /// 也免得把"醒来说完就完事"这条主路径搞复杂。
  ///
  /// 刻意**不强制、不提醒、不催**：不点也照样能直接录音，一个字都不劝。
  /// 它只提供一条"如果此刻脑子里只剩一个感觉，先把它留下"的捷径。
  ///
  /// 界面用横向 ListView 而不是 Wrap：6 个色块在窄屏上放不下两行会占掉
  /// 60~80dp，而窄屏正是最需要留给文本框的场合；横向滚动只占一行 44dp。
  Widget _moodRow(ThemeData theme) {
    final controller = AppScope.of(context);
    // 上方框里若已经是一条**存下来过**的记录，这个选择必须真的写回它 ——
    // 否则色块变了、记录里却没变，是一处"看起来生效了"的假象。
    final currentId = _currentEntryId;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Icon(Icons.wb_twilight, size: 16, color: theme.hintColor),
          const SizedBox(width: 6),
          Text(
            context.l10n.tr('mood_label'),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: DreamTags.moods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final option = DreamTags.moods[i];
                final selected = _mood == option.id;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: selected,
                  // 再点一次已选中的那个 = 取消。半梦半醒时点错了要能退回来，
                  // 而"没有这个手势"的代价是用户被迫留着一个错的标签。
                  onSelected: (_) => _pickMood(
                    controller,
                    selected ? null : option.id,
                    currentId,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 选中 / 取消一个「醒来第一感觉」。
  ///
  /// 分两种情况，这不是重复代码而是两个不同的事：
  /// - 上方框里**还没有**记录（要录新的）→ 这个值先存在 [_mood]，
  ///   等保存时随记录一起落盘；
  /// - 上方框里**已经有一条**记录（刚存完、正在改原文）→ 必须**立刻写回那条记录**。
  ///   少了后一半，用户点完色块界面就变了、记录里却没变，还会以为已经生效。
  Future<void> _pickMood(
    AppController controller,
    String? mood,
    String? currentId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final hadAnalysis = currentId == null
        ? false
        : controller.entryById(currentId)?.analysis != null;
    setState(() {
      _mood = mood;
      // 用户刚做了选择 → 它是"为这条梦选的"，不能再算已用掉
      _moodCommitted = false;
    });
    if (currentId == null) return;
    await controller.updateTags(currentId, mood: mood, clearMood: mood == null);
    if (!mounted) return;
    // 改标签会改变解析输入，而已有的结论是按旧输入算的。不说清楚，
    // 用户会以为标签打完了就自动生效——那正是"结论过期却说已解析"这一类假话。
    if (hadAnalysis) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('tag_saved_hint')),
        ),
      );
    }
  }

  /// 键盘弹起时的顶栏：一句话说明 + 「完成」。
  ///
  /// 「完成」不是装饰。键盘一弹出，用户想回到完整界面**只能**靠收起键盘，
  /// 而 Flutter 默认不会"点空白处收键盘"——不给这个按钮，用户就得去摸系统
  /// 返回键，而半梦半醒时那是摸不准的。
  ///
  /// 高度刻意压到一行（约 36dp）：它顶上原本那两行说明值 60dp，而此刻
  /// 每一 dp 都该让给正在编辑的文本框。
  Widget _editingBar(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.edit_note, size: 16, color: theme.hintColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.l10n.tr('editing_bar_text'),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => FocusScope.of(context).unfocus(),
          child: Text(context.l10n.tr('editing_done')),
        ),
      ],
    );
  }

  /// 上方那块「你口述的内容」。
  ///
  /// 识别完成后它就是**可编辑的**（用户反馈：错字就在眼前却不能改，很别扭）。
  ///
  /// 只在 `idle` 且已经有记录时开放编辑，两个原因：
  /// 1. 录音/识别中开放没有意义，实时结果会把用户正在敲的字冲掉；
  /// 2. 编辑要写回**具体某一条**记录，而记录是识别成功那一刻才产生的。
  Widget _transcriptBox(ThemeData theme, SpeechMode mode) {
    final c = AppScope.of(context);
    final entry = _currentEntry(c);
    final editable = entry != null && _phase == _Phase.idle;

    return Container(
      width: double.infinity,
      // 按钮占了更多纵向空间，这块不能让得太狠——低于 120 就只剩一两行，
      // 转写结果就没法核对了
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                editable ? Icons.edit_note : Icons.notes,
                size: 16,
                color: theme.hintColor,
              ),
              const SizedBox(width: 6),
              Text(
                editable ? context.l10n.tr('box_editable') : context.l10n.tr('box_listening'),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (editable)
            TextField(
              controller: _transcript,
              onChanged: _onTranscriptChanged,
              minLines: 3,
              maxLines: 14,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: context.l10n.tr('transcript_edit_hint'),
              ),
            )
          else
            Text(_boxText(mode), style: theme.textTheme.bodyLarge),
          if (_phase == _Phase.working) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: const LinearProgressIndicator(minHeight: 4),
            ),
          ],
          if (editable && entry.transcriptWasEdited) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _restoreRaw(entry),
                icon: const Icon(Icons.undo, size: 16),
                label: Text(context.l10n.tr('restore_raw')),
              ),
            ),
          ],
          if (editable) _staleNotice(theme, c, entry),
        ],
      ),
    );
  }

  /// 把原文还原成识别器的原始输出。
  ///
  /// 这条退路是刻意留的：改错字是常态，而"改着改着发现还不如机器那版"也是常态。
  Future<void> _restoreRaw(DreamEntry entry) async {
    final raw = entry.rawTranscript?.trim();
    if (raw == null || raw.isEmpty) return;
    _commitDebounce?.cancel();
    await _flushEdit();
    if (!mounted) return;
    await AppScope.of(context).updateTranscript(entry.id, raw);
    if (!mounted) return;
    setState(() => _transcript.text = raw);
  }

  /// 「原文改过 → 旧结论对不上」的提示。
  ///
  /// 不自动重新解析（那会花用户的钱，且边想边改会触发很多次），
  /// 只把事实摆出来，让用户自己决定。
  Widget _staleNotice(ThemeData theme, AppController c, DreamEntry entry) {
    if (!entry.analysisIsStale) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: theme.hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('stale_title'),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.hintColor),
                ),
                TextButton.icon(
                  onPressed: c.busy ? null : () => c.analyzeEntry(entry),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(context.l10n.tr('stale_reparse')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(SpeechMode mode) {
    if (_speechBroken) return AppL10n.current.tr('rec_title_broken');
    return AppL10n.current.tr('rec_title');
  }

  String _hintFor(SpeechMode mode) {
    if (_speechBroken) {
      return AppL10n.current.tr('rec_hint_broken');
    }
    return AppL10n.current.tr('rec_hint', {'mode': mode.tagline});
  }

  String _captionFor(SpeechMode mode, bool busy) {
    if (busy) return _status ?? AppL10n.current.tr('caption_working');
    if (_speechBroken) return AppL10n.current.tr('caption_broken');
    if (_phase == _Phase.recording) {
      // 显示时长是为了让"还在录"这件事**看得见**：中途停下来想事情时，
      // 秒数还在走，用户才敢确定自己没有误触结束。
      return AppL10n.current.tr('caption_recording',
          {'clock': _fmtClock(_elapsedSeconds)});
    }
    return AppL10n.current.tr('caption_idle');
  }

  String _boxText(SpeechMode mode) {
    if (_liveText.isNotEmpty) return _liveText;
    if (_phase == _Phase.working) return _status ?? AppL10n.current.tr('caption_working');
    if (_phase == _Phase.recording) {
      return mode.needsRecording
          ? AppL10n.current.tr('box_recording_offline',
              {'clock': _fmtClock(_elapsedSeconds)})
          : AppL10n.current.tr('box_recording_system',
              {'clock': _fmtClock(_elapsedSeconds)});
    }
    return AppL10n.current.tr('box_hint');
  }

  static String _fmtClock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 手动输入对话框。
///
/// 单独做成 StatefulWidget 是为了**正确地释放 TextEditingController**：
/// 在 `showDialog` 外面创建再 dispose，会在关闭动画期间踩到
/// 「A TextEditingController was used after being disposed」。
class _ManualInputDialog extends StatefulWidget {
  const _ManualInputDialog();

  @override
  State<_ManualInputDialog> createState() => _ManualInputDialogState();
}

class _ManualInputDialogState extends State<_ManualInputDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.tr('manual_input_title')),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        decoration: InputDecoration(
          hintText: context.l10n.tr('manual_input_hint'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(context.l10n.tr('save')),
        ),
      ],
    );
  }
}

/// 圆形大按钮的「脸」：底色 + 光晕 + 图标。
///
/// 抽出来是为了让「按住说话」「写下来」「正在识别」共用同一套观感 ——
/// 它们只是**交互/状态不同**，视觉上应当是同一个按钮。
///
/// 图标与光晕都按直径等比缩放，这样换尺寸时观感比例不变；
/// 这几个系数是从原尺寸（132 / 图标 56 / 光晕 12,1 / 录音 30,6）反推的。
class _CircleFace extends StatelessWidget {
  const _CircleFace({
    required this.size,
    required this.icon,
    required this.fill,
    required this.foreground,
    this.blurFactor = 0.091,
    this.spreadFactor = 0.008,
  });

  final double size;
  final IconData icon;
  final Color fill;
  final Color foreground;
  final double blurFactor;
  final double spreadFactor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        boxShadow: [
          BoxShadow(
            color: fill.withValues(alpha: 0.3),
            blurRadius: size * blurFactor,
            spreadRadius: size * spreadFactor,
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.42, color: foreground),
    );
  }
}

/// 说话按钮：**点一下开始录，再点一下结束**。
///
/// 2026-09-21 由「按住不放」改来。改的原因是真实使用反馈：说梦说到一半
/// 停下来想一想是最自然的事，而按住式只要一松手这次记录就结束了 ——
/// 用户的动作和意图正好相反（"我想歇一下"变成了"我说完了"）。
///
/// 顺带说明为什么**可以**改成点击式：当初用 `Listener` 按下即录，是为了避开
/// `onLongPress` 约 500ms 的判定延迟（免得头几个字被吃掉）。点击式没有
/// 那个延迟，原顾虑不存在。
///
/// 新增的代价是"误触一次就一直在录"，靠两处补上：
/// 录音中的秒数显示（[caption] 里），以及过短录音拦截（[_kMinRecordedLength]）。
class _TalkButton extends StatefulWidget {
  const _TalkButton({
    required this.recording,
    required this.size,
    required this.onToggle,
  });

  final bool recording;

  /// 由上层按可用空间算好（标称 264）。
  final double size;

  /// 点一下要做什么：没在录就开录，正在录就结束。
  final VoidCallback onToggle;

  @override
  State<_TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<_TalkButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording = widget.recording;
    // 按下时轻微提亮，作为"收到了"的即时反馈 —— 松手才真正切换，
    // 没有这个反馈的话，点击式按钮会让人怀疑"我到底点上了没有"。
    final base = recording ? scheme.error : scheme.primary;
    final fill = _down
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.16), base)
        : base;
    return Semantics(
      button: true,
      label: recording
          ? context.l10n.tr('rec_stop_label')
          : context.l10n.tr('rec_start_label'),
      child: GestureDetector(
        onTap: widget.onToggle,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: _CircleFace(
          size: widget.size,
          icon: recording ? Icons.stop : Icons.mic,
          // 录音时底色换成 error，前景也要跟着换，否则是拿 onPrimary 配 error
          fill: fill,
          foreground: recording ? scheme.onError : scheme.onPrimary,
          blurFactor: recording ? 0.227 : 0.091,
          spreadFactor: recording ? 0.045 : 0.008,
        ),
      ),
    );
  }
}

/// 设备没有语音识别能力时，大按钮改成「点一下写下来」。
///
/// 保留圆形大目标的理由：凌晨半梦半醒时「不用看也能按准」这件事
/// 与用什么输入方式无关。
class _CircleActionButton extends StatefulWidget {
  const _CircleActionButton({
    required this.size,
    required this.icon,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_CircleActionButton> createState() => _CircleActionButtonState();
}

class _CircleActionButtonState extends State<_CircleActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 按下时提亮一档，作为「收到了」的反馈（按住说话那边是靠变红，这里没有状态可依赖）
    final fill = _down
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.16), scheme.primary)
        : scheme.primary;
    return Semantics(
      button: true,
      label: context.l10n.tr('write_down_label'),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: _CircleFace(
          size: widget.size,
          icon: widget.icon,
          fill: fill,
          foreground: scheme.onPrimary,
        ),
      ),
    );
  }
}

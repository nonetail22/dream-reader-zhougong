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

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/messages.dart';
import 'speech_errors.dart';

// 错误码映射放在纯逻辑文件里，好让 `dart test` 能覆盖到（本文件依赖 Flutter 插件，跑不动）
export 'speech_errors.dart' show mapSpeechError;

/// 转写失败时抛出，带**可操作**的说明。
///
/// 为什么需要这个类：原来 `onError: (_) {}` 把识别错误全部吞掉，
/// 用户只看到一句「没有识别到内容」——分不清是没给权限、麦克风被占用，
/// 还是这台设备根本没有可用的中文语音服务。**这类静默失败必须消灭**，
/// 否则用户和开发者都无从下手。
class TranscriberException implements Exception {
  const TranscriberException(this.message, {this.hint});

  /// 一句话说清「为什么失败」
  final String message;

  /// 「怎么办」——尽量给可执行的下一步
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}

/// 界面上的状态提示通道。传 `null` 表示「当前没在忙，把提示清掉」。
///
/// 用 `String?` 而不是「复用空字符串」：界面上要能区分
/// 「正在做一件要等几秒的事」和「什么都没发生」——前者必须给反馈，
/// 否则凌晨半梦半醒的用户会把 3 秒的等待当成卡死然后杀掉 App。
typedef StatusSink = void Function(String? message);

/// 「边说边出字」的转写器：**它自己开麦克风**。
///
/// 目前只有系统语音识别属于这一类。它的接口是推式的（start → 持续回调 → stop），
/// 因为识别过程本身就是流式的。
abstract class LiveTranscriber {
  /// 识别过程中的错误上报。**必须接住**——见 [TranscriberException] 的说明。
  set onError(void Function(String message) callback);

  /// 最近一次错误的可读描述（没有则为 null）
  String? get lastError;

  Future<bool> init();
  Future<void> start(void Function(String text, bool isFinal) onResult);
  Future<void> stop();
  Future<void> cancel();
  bool get isListening;
}

/// 「整段音频出字」的转写器：**音频由调用方先录好再喂进来**。
///
/// 离线识别（sherpa-onnx）与云端 BYOK 都走这条路。它们和 [LiveTranscriber]
/// 是两种东西，不该塞进同一个接口：前者自己占麦克风，后者等别人把文件交过来；
/// 混在一起就会出现「到底谁在开麦克风」的歧义，而麦克风独占正是本项目
/// 栽过跟头的地方（见 README 里华为那次排查）。
abstract class FileTranscriber {
  /// 识别过程中的错误上报。同样必须接住。
  set onError(void Function(String message) callback);

  /// 最近一次错误的可读描述（没有则为 null）
  String? get lastError;

  /// 这个名字用于日志与界面上说明「在用哪条路」
  String get label;

  Future<bool> init();

  /// 现在能不能用。返回 `null` 表示就绪；否则返回**给用户看的**原因。
  ///
  /// 之所以要单独有这个查询而不是「试一次看会不会失败」：设置页需要在用户
  /// 切到这条路之前就告诉他准备得怎么样（模型在不在、Key 填没填），
  /// 而不是等他凌晨三点按下去才发现没配好。
  Future<String?> readyIssue();

  /// 把一整段音频转成文字。失败抛 [TranscriberException]。
  Future<String> transcribe(String audioPath);

  /// 释放原生资源（离线模型会占可观的常驻内存，切走时应该放掉）
  void dispose();
}

/// 端侧转写：使用系统自带能力（Android SpeechRecognizer / iOS Speech /
/// 浏览器 Web Speech API），零成本、零 API Key，且音频不出设备。
///
/// **麦克风独占性**（本文件最重要的一条）：系统识别服务是**独立进程**，
/// 它要自己开麦克风采集。Android 10+ 只允许一个应用采集音频，且前台应用优先——
/// 如果本应用同时用 `record` 插件开着 AudioRecord，识别服务就会被静音，
/// 表现为「说了话但一个字都识别不出来」。**所以调用方必须保证同一时刻
/// 只有一个采集者**（见 RecordPage 的启动顺序）。
class SystemTranscriber implements LiveTranscriber {
  SystemTranscriber({this.preferredLocale = 'zh_CN'});

  /// 期望的识别语言；设备没装该语言包时会回落到任何中文变体，再不行交给系统默认。
  final String preferredLocale;

  final SpeechToText _stt = SpeechToText();

  bool _inited = false;
  bool _everFailed = false;
  String? _unavailableDetail;
  String? _lastError;
  String? _resolvedLocale;
  bool _localeLookedUp = false;

  void Function(String message)? _onError;

  @override
  set onError(void Function(String message) callback) => _onError = callback;

  @override
  String? get lastError => _lastError;

  @override
  bool get isListening => _stt.isListening;

  /// 设备是否真的提供了可用的识别服务。false 时**不要**指望能转写。
  bool get isAvailable => _inited;

  @override
  Future<bool> init() async {
    if (_inited) return true;
    // 失败**不缓存**：用户可能刚去系统设置里补了权限或装了语音服务，
    // 下一次按住就应该有机会成功。（speech_to_text 内部同样只在成功时缓存。）
    try {
      _inited = await _stt.initialize(
        onError: (e) {
          // 这里以前是 `(_) {}` —— 正是它让整个问题变得不可诊断。
          _lastError = mapSpeechError(e.errorMsg);
          // 同时也打到日志：用户报「识别不出来」时，
          // `adb logcat -s flutter` 就能看到设备到底报的哪个错误码。
          debugPrint('[DreamReader] 语音识别错误: raw=${e.errorMsg} '
              'permanent=${e.permanent} → $_lastError');
          _onError?.call(_lastError!);
        },
        onStatus: (_) {},
      );
    } catch (e) {
      _inited = false;
      _unavailableDetail = '$e';
      debugPrint('[DreamReader] 语音识别初始化抛异常: $e');
    }
    if (!_inited) {
      _everFailed = true;
      // 这个 detail 会原样出现在给用户看的 hint 里，所以也要跟随语言；
      // 若 init 抛过异常，则保留原始异常文本（那是诊断信息，不翻译）。
      _unavailableDetail ??= AppL10n.current.tr('err_system_reason_unknown');
      debugPrint('[DreamReader] 语音识别不可用: $_unavailableDetail');
    }
    return _inited;
  }

  /// 选一个设备真正支持的 locale。
  ///
  /// 之前直接写死 `localeId: 'zh_CN'`：设备没装这个语言包时不会报错，
  /// 只是**永远识别不出东西**——又一种静默失败。
  Future<String?> _resolveLocale() async {
    if (_localeLookedUp) return _resolvedLocale;
    _localeLookedUp = true;
    try {
      final available = await _stt.locales();
      final want = preferredLocale.replaceAll('-', '_').toLowerCase();
      for (final l in available) {
        if (l.localeId.replaceAll('-', '_').toLowerCase() == want) {
          _resolvedLocale = l.localeId;
          return _resolvedLocale;
        }
      }
      // 退一步：任何中文变体（zh-TW / zh-HK 识别普通话也能用，只是词表不同）
      for (final l in available) {
        if (l.localeId.toLowerCase().startsWith('zh')) {
          _resolvedLocale = l.localeId;
          return _resolvedLocale;
        }
      }
    } catch (_) {
      // 拿不到列表就交给系统默认，不因此阻断流程
    }
    return null;
  }

  @override
  Future<void> start(void Function(String text, bool isFinal) onResult) async {
    if (!await init()) {
      throw TranscriberException(
        AppL10n.current.tr('err_system_transcriber_unavailable'),
        hint: AppL10n.current.tr('err_system_transcriber_hint', {
          'detail': _unavailableDetail ??
              AppL10n.current.tr('err_system_reason_unknown'),
        }),
      );
    }
    _lastError = null;
    final locale = await _resolveLocale();
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      // speech_to_text 7.5+：listenFor / pauseFor / localeId 已收进 listenOptions
      listenOptions: SpeechListenOptions(
        partialResults: true, // 边说边出字，松手前用户就能看到识别结果
        cancelOnError: false,
        listenMode: ListenMode.dictation, // 口述模式：不因停顿提前截断
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 8),
        localeId: locale, // null = 用系统默认
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() => _stt.cancel();

  /// 供 UI 展示当前用的是哪个语言包（排查用）
  String? get resolvedLocale => _resolvedLocale;

  /// 是否曾经初始化失败过（用于给出「设备不支持」的稳定提示）
  bool get everFailed => _everFailed;
}

/// 测试用假实现：把预设文本按「逐字追加」模拟，再给一次 final 结果。
class FakeTranscriber implements LiveTranscriber {
  FakeTranscriber(this.script);

  final String script;
  bool _listening = false;
  void Function(String, bool)? _cb;

  @override
  set onError(void Function(String message) callback) {}

  @override
  String? get lastError => null;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> start(void Function(String text, bool isFinal) onResult) async {
    _listening = true;
    _cb = onResult;
  }

  /// 测试驱动：模拟识别过程中的一次增量与一次终稿
  void feed() {
    _cb?.call(script, true);
    _listening = false;
  }

  @override
  Future<void> stop() async => _listening = false;

  @override
  Future<void> cancel() async => _listening = false;
}

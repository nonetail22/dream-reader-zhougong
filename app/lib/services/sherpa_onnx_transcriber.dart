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
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../l10n/messages.dart';
import 'offline_asr_worker.dart';
import 'offline_model.dart';
import 'transcriber.dart';

/// 展示给用户的名字与体积说明（跟随当前界面语言）。
/// 元数据、下载与完整性校验在 `offline_model.dart`（OfflineModelSpec）。
class OfflineModelFiles {
  const OfflineModelFiles._();

  static String get displayName => AppL10n.current.tr('offline_model_name');
  static String get approxSize => AppL10n.current.tr('offline_model_size');
}

/// 端侧离线转写：sherpa-onnx + Paraformer 中文大模型（约 320MB 含标点模型，按需下载），**不联网识别**。
///
/// 这是三条路里唯一一条「任何设备都能用、且音频绝不出设备」的：
/// - 不依赖系统语音服务，所以华为这类没有 GMS 的机器也能用；
/// - 识别不需要网络，凌晨、地下室、飞行模式都能用；
/// - 音频只在本机内存里算一遍，不留档、不上传。
///
/// 代价有三条：首次使用要联网下载约 320MB 的模型（识别 243MB + 标点 75MB，
/// 0.6.0 起不再预装进安装包）；它是**整段识别**，松手后才出字；大模型解码更慢，
/// 长录音按段出进度。长录音的分段与静音段跳过见 [audio_chunker.dart] 与下方实现。
class SherpaOnnxTranscriber implements FileTranscriber {
  SherpaOnnxTranscriber({this.onStatus});

  /// 界面状态提示。传 `null` 表示"提示可以清掉了"。
  /// 凌晨半梦半醒时，一个没有任何反馈的 3 秒等待会被当成卡死。
  StatusSink? onStatus;

  void Function(String message)? _onError;

  @override
  set onError(void Function(String message) callback) => _onError = callback;

  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  String get label => AppL10n.current.tr('transcriber_offline_label');

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<bool> init() async => (await readyIssue()) == null;

  /// 就绪判断：平台支持 + 目录可建 + **模型已下载**。
  ///
  /// 模型未下载不算"这条路废了"——界面会先引导下载（见 `offline_model_dialog.dart`），
  /// 这里返回 issue 是给"没走引导就直接转写"的路径兜底。
  /// 只有硬盘写不进去（空间不足/目录不可写）才是真正的环境问题。
  @override
  Future<String?> readyIssue() async {
    if (kIsWeb) return AppL10n.current.tr('err_offline_web');
    if (!_supported) return AppL10n.current.tr('err_offline_platform');
    Directory dir;
    try {
      dir = await _modelDir();
    } catch (e) {
      return AppL10n.current.tr('err_offline_no_dir', {'e': '$e'});
    }
    if (!isModelInstalledIn(dir)) {
      return AppL10n.current.tr('offline_need_download');
    }
    return null;
  }

  /// 设置页显示用的、人话版的状态说明。
  ///
  /// 注意插值要写成 `${OfflineModelFiles.displayName}`：写成
  /// `$OfflineModelFiles.displayName` 时 Dart 只会替换类名，界面上会原样显示
  /// `OfflineModelFiles.displayName` —— 而这既不报错也过得了 analyze，
  /// 只有真的截图看一眼才会发现。这个坑踩过一次。
  Future<String> describeReadiness() async {
    final issue = await readyIssue();
    if (issue != null) return issue;
    final installed = await isModelInstalled();
    if (installed) {
      return AppL10n.current.tr('offline_ready', {
        'name': OfflineModelFiles.displayName,
        'size': OfflineModelFiles.approxSize,
      });
    }
    return AppL10n.current.tr('offline_first_prepare', {
      'name': OfflineModelFiles.displayName,
      'size': OfflineModelFiles.approxSize,
    });
  }

  /// 模型是否已经下载到本机（不代表已加载进内存）
  Future<bool> isModelInstalled() async {
    try {
      return isModelInstalledIn(await _modelDir());
    } catch (_) {
      return false;
    }
  }

  /// 下载缺失的模型文件。进度与取消语义见 [downloadOfflineModel]；
  /// 进度提示走调用方的下载进度条，不占用 [onStatus]（那是识别用的通道）。
  Future<void> downloadModel({
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    await downloadOfflineModel(
      await _modelDir(),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// 模型在本机的落点。**放 support 目录而不是 documents 目录**：
  /// documents 在 Android 上可能被系统备份工具扫到（243MB 的模型进备份毫无意义），
  /// support 目录才是"应用自己用的数据"该待的地方。
  Future<Directory> _modelDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/models/${OfflineModelSpec.dirName}');
  }

  @override
  Future<String> transcribe(String audioPath) async {
    try {
      _lastError = null;
      final dir = await _modelDir();
      if (!isModelInstalledIn(dir)) {
        // 正常流程到不了这里（界面会先引导下载）；走到这说明有路径绕过了引导
        throw TranscriberException(
          AppL10n.current.tr('transcriber_not_ready', {'label': label}),
          hint: AppL10n.current.tr('offline_need_download'),
        );
      }

      final sw = Stopwatch()..start();
      try {
        // 整条管线（读波形/分段/解码/标点）跑在 worker isolate 上：
        // 主 isolate 只收进度事件，识别再重界面也不冻（0.7.1）。
        // 2 线程：单线程在大段口述上偏慢，更多线程换来的收益很小而发热明显。
        final threads = Platform.numberOfProcessors >= 4 ? 2 : 1;
        final result = await _Runtime.transcribe(
          dir.path,
          audioPath,
          threads: threads,
          onEvent: (m) {
            switch (m['phase'] ?? (m['pct'] != null ? 'progress' : null)) {
              case 'loading':
                onStatus?.call(AppL10n.current.tr('offline_loading'));
              case 'loaded':
                debugPrint('[DreamReader] worker 模型加载完成：${m['ms']}ms');
                onStatus?.call(null);
              case 'recognizing':
                onStatus?.call(AppL10n.current.tr('box_working'));
              case 'progress':
                // 进度按**百分比**显示（用户 0.6.1 反馈：不要 x/y 段）。跳过的段
                // 瞬间完成，空白多的录音百分比会走得很快——这是真实进度，不是卡顿。
                onStatus?.call(AppL10n.current.tr(
                    'offline_recognizing_progress',
                    {'pct': '${m['pct']}'}));
            }
          },
        );
        debugPrint('[DreamReader] 离线识别完成：${result.log}');
        debugPrint('[DreamReader] 总耗时 ${sw.elapsedMilliseconds}ms');
        return result.text;
      } on WorkerFailure catch (f) {
        if (f.code == 'err_offline_no_samples') {
          // "读不出波形"必须带上文件头 —— 录音插件写出来的容器格式一旦变了，
          // 这条日志就是唯一能直接看出问题的线索。
          throw TranscriberException(
            AppL10n.current.tr('err_offline_no_samples'),
            hint: AppL10n.current.tr('err_offline_no_samples_hint',
                {'header': _describeHeader(audioPath)}),
          );
        }
        throw TranscriberException(
          AppL10n.current.tr(f.code, f.args),
          hint: AppL10n.current.tr('err_offline_failed_hint'),
        );
      } finally {
        _Runtime.touch(); // 用完就重新计时，闲置才释放
        onStatus?.call(null);
      }
    } on TranscriberException catch (e) {
      _lastError = e.message;
      _onError?.call(e.message);
      rethrow;
    } catch (e, st) {
      debugPrint('[DreamReader] 离线识别失败: $e\n$st');
      final msg = AppL10n.current.tr('err_offline_failed', {'e': '$e'});
      _lastError = msg;
      _onError?.call(msg);
      throw TranscriberException(
        msg,
        hint: AppL10n.current.tr('err_offline_failed_hint'),
      );
    }
  }

  /// 读文件头做个可读描述（只读前 64 字节，不把整文件读进来）
  static String _describeHeader(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) {
        return AppL10n.current.tr('err_header_missing', {'path': path});
      }
      final size = f.lengthSync();
      final raf = f.openSync();
      final List<int> head;
      try {
        head = raf.readSync(64);
      } finally {
        raf.closeSync();
      }
      final magic = String.fromCharCodes(head.take(4));
      final isRiff = magic == 'RIFF';
      final buf = StringBuffer()
        ..write(isRiff ? 'RIFF/WAVE' : '"$magic"')
        ..write('，${AppL10n.current.tr('header_bytes', {'size': '$size'})}');
      if (isRiff && head.length >= 44) {
        final bd = ByteData.sublistView(Uint8List.fromList(head));
        buf
          ..write('，${AppL10n.current.tr('header_channels', {
                'n': '${bd.getUint16(22, Endian.little)}',
              })}')
          ..write(' / ${bd.getUint32(24, Endian.little)} Hz')
          ..write(' / ${bd.getUint16(34, Endian.little)} bit');
      }
      return buf.toString();
    } catch (e) {
      return AppL10n.current.tr('err_header_failed', {'e': '$e'});
    }
  }

  @override
  void dispose() {
    // 刻意**不在这里杀 worker**：模型加载 1~3 秒、常驻内存数百 MB，
    // 而记录页会随底部导航切来切去。由 [_Runtime] 按闲置时间自己释放。
    onStatus = null;
  }
}

/// 加载好的识别器缓存。
///
/// 做成库级共享而不是每个实例各存一份，是因为模型太贵：
/// 加载 1~2 秒、常驻内存数百 MB。切一次页面就重载一次是不能接受的。
/// 但也不能一直占着——凌晨记完梦之后用户可能一整天不再用它，
/// 所以闲置 [idleRelease] 后主动释放。
class _Runtime {
  const _Runtime._();

  // ---- worker isolate 的句柄（模型常驻 worker，不在主 isolate）----
  static Isolate? _worker;
  static SendPort? _toWorker;
  static ReceivePort? _fromWorker;

  /// 当前在等的那个请求的回包；worker 一次只处理一个任务（主侧串行化）。
  static Completer<Map>? _reply;
  static void Function(Map event)? _onEvent;
  static Future<void> _queue = Future.value();
  static Timer? _idle;

  /// 闲置多久释放（杀掉 worker，模型内存随之回收）。3 分钟：够覆盖
  /// "记完一条又想起一点、再记一条"的间隔，又不至于整夜占着内存。
  static const Duration idleRelease = Duration(minutes: 3);

  static void _handleEvent(Map m) {
    switch (m['event']) {
      case 'phase':
      case 'progress':
        _onEvent?.call(m);
      case 'spawned':
      case 'released':
        break; // 与请求无关的握手/确认消息，忽略
      default:
        // ready/done/failed 都终结当前请求
        _reply?.complete(m);
    }
  }

  /// 拉起 worker（幂等）。spawn 失败按识别失败处理——不能比原来更糟。
  static Future<void> _ensureWorker() async {
    _idle?.cancel();
    if (_worker != null && _toWorker != null && _fromWorker != null) return;
    await _teardownWorker(); // 半死状态（例如刚被杀）先清干净
    final handshake = ReceivePort();
    try {
      _worker = await Isolate.spawn(
          offlineAsrWorkerMain, handshake.sendPort);
    } catch (e) {
      handshake.close();
      throw StateError('识别 worker 启动失败: $e');
    }
    final spawned = await handshake.first as Map;
    handshake.close();
    _fromWorker = ReceivePort();
    _fromWorker!.listen((m) => _handleEvent(m as Map));
    _toWorker = spawned['port'] as SendPort;
  }

  static Future<void> _teardownWorker() async {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _toWorker = null;
    _fromWorker?.close();
    _fromWorker = null;
    _reply = null;
  }

  /// 串行化：任何时刻只有一个任务在 worker 上跑。
  static Future<T> _serialized<T>(Future<T> Function() job) {
    final task = _queue.then((_) => job());
    _queue = task.then((_) {}, onError: (_) {});
    return task;
  }

  /// 发一个命令并等它的终结事件（ready/done/failed）；期间 phase/progress
  /// 事件转发给 [onEvent]。
  static Future<Map> _request(
    Map<String, Object?> msg, {
    void Function(Map event)? onEvent,
  }) async {
    await _ensureWorker();
    final completer = Completer<Map>();
    _reply = completer;
    _onEvent = onEvent;
    _toWorker!.send({...msg, 'reply': _fromWorker!.sendPort});
    try {
      return await completer.future;
    } finally {
      _reply = null;
      _onEvent = null;
    }
  }

  /// 完整识别：模型就位 → 读波形 → 分段解码 → 补标点 → 拼接。
  /// 全部发生在 worker isolate；主 isolate 只收进度事件，UI 全程可渲染。
  static Future<({String text, String log})> transcribe(
    String dir,
    String path, {
    required int threads,
    void Function(Map event)? onEvent,
  }) {
    return _serialized(() async {
      final result = await _request({
        'cmd': 'transcribe',
        'dir': dir,
        'path': path,
        'threads': threads,
      }, onEvent: onEvent);
      switch (result['event']) {
        case 'done':
          return (
            text: result['text'] as String,
            log: result['log'] as String? ?? '',
          );
        case 'failed':
          throw WorkerFailure(
            code: result['code'] as String? ?? 'err_offline_failed',
            args: (result['args'] as Map?)?.cast<String, String>() ?? const {},
          );
        default:
          throw WorkerFailure(code: 'err_offline_failed', args: {'e': '$result'});
      }
    });
  }

  /// 每次用完刷新闲置计时；到期杀 worker。
  static void touch() {
    _idle?.cancel();
    _idle = Timer(idleRelease, () {
      debugPrint(
          '[DreamReader] 离线识别 worker 闲置 ${idleRelease.inMinutes} 分钟，释放');
      _teardownWorker();
      _idle = null;
    });
  }
}

/// worker 回报的失败（带文案键与参数），由转写器翻译成用户可见消息。
class WorkerFailure implements Exception {
  WorkerFailure({required this.code, required this.args});

  final String code;
  final Map<String, String> args;

  @override
  String toString() => 'WorkerFailure($code, $args)';
}

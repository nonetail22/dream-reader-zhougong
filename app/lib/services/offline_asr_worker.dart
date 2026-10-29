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

/// 离线识别的**后台 isolate worker**（0.7.1）。
///
/// ## 为什么要有这个文件
///
/// 识别管线（读波形 → 分段规划 → 模型加载 → 逐段解码 → 补标点）整体是
/// **同步大块头**：模型构造与 `recognizer.decode()` 是阻塞数秒的 native
/// 调用，跑在 UI isolate 上时界面一帧都画不出来——用户看到的就是"点了
/// 重新识别之后冻住，百分比偶尔闪一下又卡住"（0.7.0 真机反馈，且在
/// 0.7.0 加了让帧后**依旧**如此：让帧只能让出段与段之间的间隙，段内
/// 两三秒的解码还是冻的）。
///
/// 正解（DETAILS §十一 早有预案）：把整条管线搬进后台 isolate。模型
/// FFI 的加载用的是 `DynamicLibrary.open('libsherpa-onnx-c-api.so')`，
/// 同一进程内任何 isolate 都能加载；sherpa 包文档也明确支持
/// 「每个用到它的 isolate 各自调一次 initBindings」。
///
/// ## 纪律
/// - 本文件**不 import 任何 Flutter 包、不做任何本地化**：worker 里没有
///   `AppL10n`（static 不跨 isolate 共享）。所有用户可见文案由主 isolate
///   按事件类型自行翻译（`sherpa_onnx_transcriber.dart` 负责）。
/// - worker 与外界只通过 SendPort 通信，消息是纯 Map/String/int。
/// - 一次只处理一个任务（主 isolate 侧串行化），worker 内不排队。
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'audio_chunker.dart';
import 'audio_level.dart';
import 'offline_model.dart';

/// worker 的入口。主 isolate 通过 `Isolate.spawn(offlineAsrWorkerMain, sendPort)` 启动。
void offlineAsrWorkerMain(SendPort initial) {
  final port = ReceivePort();
  initial.send({'event': 'spawned', 'port': port.sendPort});

  // 绑定按 isolate 各自初始化（见文件头注）。
  sherpa.initBindings();

  // 模型常驻本 isolate：加载贵（1~3s），重复任务直接复用；换目录才重载。
  // 释放只发生在收到 'release' 命令（主 isolate 闲置计时到期时）。
  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflinePunctuation? punctuator;
  String? loadedDir;

  void release() {
    try {
      recognizer?.free();
      punctuator?.free();
    } catch (_) {
      // native 释放失败不再扩散：isolate 马上会被杀，内存随之回收
    }
    recognizer = null;
    punctuator = null;
    loadedDir = null;
  }

  /// 补标点：锦上添花的步骤，任何失败都退回原文，绝不因此丢识别结果。
  String punctuate(String text) {
    final p = punctuator;
    if (text.isEmpty || p == null) return text;
    try {
      return p.addPunct(text);
    } catch (e) {
      return text;
    }
  }

  port.listen((msg) async {
    final Map m = msg as Map;
    final SendPort reply = m['reply'] as SendPort;
    final cmd = m['cmd'] as String?;

    if (cmd == 'release') {
      release();
      reply.send({'event': 'released'});
      return;
    }

    if (cmd != 'transcribe') return; // 未知命令直接忽略，不给 worker 留崩的口子

    final dir = m['dir'] as String;
    final path = m['path'] as String;
    final threads = (m['threads'] as int?) ?? 2;

    try {
      // ---- 模型就位（必要时加载，期间界面可以画"正在加载模型"）----
      if (recognizer == null || loadedDir != dir || punctuator == null) {
        reply.send({'event': 'phase', 'phase': 'loading'});
        release();
        final sw = Stopwatch()..start();
        recognizer = sherpa.OfflineRecognizer(
          sherpa.OfflineRecognizerConfig(
            model: sherpa.OfflineModelConfig(
              paraformer: sherpa.OfflineParaformerModelConfig(
                model: '$dir/${OfflineModelSpec.modelFile}',
              ),
              tokens: '$dir/${OfflineModelSpec.tokensFile}',
              numThreads: threads,
              modelType: 'paraformer',
              debug: false,
            ),
          ),
        );
        punctuator = sherpa.OfflinePunctuation(
          config: sherpa.OfflinePunctuationConfig(
            model: sherpa.OfflinePunctuationModelConfig(
              ctTransformer: '$dir/${OfflineModelSpec.punctFile}',
              numThreads: 1,
              debug: false,
            ),
          ),
        );
        loadedDir = dir;
        reply.send({
          'event': 'phase',
          'phase': 'loaded',
          'ms': sw.elapsedMilliseconds,
        });
      }

      // ---- 读波形（FFI，同步，但在 worker 里不再冻 UI）----
      final wave = sherpa.readWave(path);
      if (wave.samples.isEmpty) {
        // 空波形的具体文案（含文件头描述）由主 isolate 生成——它才有 l10n
        // 与文件路径上下文。
        reply.send({'event': 'failed', 'code': 'err_offline_no_samples'});
        return;
      }

      // ---- 分段解码（与 smoke/应用共用同一份 planChunks）----
      reply.send({'event': 'phase', 'phase': 'recognizing'});
      final ranges = planChunks(wave.samples, wave.sampleRate);
      final sw = Stopwatch()..start();
      final parts = <String>[];
      var skipped = 0;
      for (var i = 0; i < ranges.length; i++) {
        final r = ranges[i];
        final chunk = Float32List.sublistView(wave.samples, r.start, r.end);
        // 静音段直接跳过不解码：模型在无人声输入上会编话（audio_level.dart 头注）。
        final chunkLevel = judgeSpeechFloat(chunk, wave.sampleRate);
        if (chunkLevel != null && chunkLevel.seemsSilent) {
          skipped++;
        } else {
          final stream = recognizer!.createStream();
          try {
            stream.acceptWaveform(
                samples: chunk, sampleRate: wave.sampleRate);
            recognizer!.decode(stream);
            // 每段单独补标点：段最长 20s、几十个字，远在标点模型输入上限内。
            parts.add(
                punctuate(recognizer!.getResult(stream).text.trim()));
          } finally {
            stream.free();
          }
        }
        if (ranges.length > 1) {
          reply.send({
            'event': 'progress',
            'pct': (i + 1) * 100 ~/ ranges.length,
          });
        }
      }
      reply.send({
        'event': 'done',
        'text': joinTranscripts(parts).trim(),
        'log': '${(wave.samples.length / wave.sampleRate).toStringAsFixed(2)}s '
            '@${wave.sampleRate}Hz，分 ${ranges.length} 段，'
            '跳过静音 $skipped/${ranges.length}，'
            '解码 ${sw.elapsedMilliseconds}ms',
      });
    } catch (e) {
      reply.send({
        'event': 'failed',
        'code': 'err_offline_failed',
        'args': {'e': '$e'},
      });
    }
  });
}

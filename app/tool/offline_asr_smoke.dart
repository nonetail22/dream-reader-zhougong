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

// 离线识别冒烟测试（纯 Dart，**不需要 Flutter、不需要设备、不需要 Android**）。
//
// 为什么要有这个脚本：端侧离线识别是本项目里最容易"看起来跑起来了、
// 其实一个字都没认对"的一环——native 库加载成功、不报错、返回空字符串，
// 这些都不能说明模型可用。只有在**真实中文音频**上跑出**能读懂的句子**，
// 才算这一步真的通了。它同时也是以后换模型时的回归测试。
//
// 跑法（用 Flutter 自带的 dart，而不是系统的 dart）：
//   <flutter SDK>/bin/dart run tool/offline_asr_smoke.dart
//
// 可传参：第一个参数是模型目录，其后是若干 wav 文件路径。
//
// 2026-09-21 补充：加**输入电平判据**。原因是这个脚本差点放过一次假阳性——
// 模拟器以 -no-audio 启动，麦克风只给出 -72 dBFS 的底噪，而 paraformer 在
// 近静音输入上**不会返回空字符串，而是吐出一句像模像样的胡话**（实测得到
// "我的一我的我的时子"）。于是"出内容了"这个判据被满足，看起来像识别成功。
// 教训：**验证识别质量时，必须先确认输入里真的有人在说话**。只看输出非空，
// 等于没验。
//
// 2026-09-21 再补：同一套判据**搬进了应用运行时**（`lib/services/audio_level.dart`），
// 因为改成"点一下开始 / 再点一下结束"之后，"点了开始却没说话"会在应用里
// 复现同一个幻觉。现在这里**直接复用那份实现**，不再各写一份——
// 脚本里过关、应用里失灵（或反过来）这种漂移迟早会出事。
import 'dart:io';
import 'dart:typed_data';

import 'package:dream_reader/services/audio_chunker.dart';
import 'package:dream_reader/services/audio_level.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 「这段输入里到底有没有人在说话」的判据本体在
/// `lib/services/audio_level.dart`（应用运行时用的是同一份）。
/// 0.4.4 起判据是「有声帧占比」，不是峰值——理由见那个文件的头部。
/// 这里不另立常量，直接调 [judgeSpeechFloat]。

void main(List<String> args) {
  final modelDir = args.isNotEmpty ? args[0] : 'assets/models/paraformer-zh-large';
  final wavs = args.length > 1
      ? args.sublist(1)
      : Directory('../validation/asr_samples')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.wav'))
          .toList()
        ..sort();

  final modelFile = '$modelDir/model.int8.onnx';
  final tokensFile = '$modelDir/tokens.txt';
  for (final f in [modelFile, tokensFile]) {
    if (!File(f).existsSync()) {
      stderr.writeln('缺文件：$f');
      exitCode = 2;
      return;
    }
  }

  stdout.writeln('== 加载原生库 ==');
  sherpa.initBindings();
  stdout.writeln('   OK');

  stdout.writeln('== 加载模型 ==');
  final sw = Stopwatch()..start();
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer:
            sherpa.OfflineParaformerModelConfig(model: modelFile),
        tokens: tokensFile,
        numThreads: 2,
        modelType: 'paraformer',
        debug: false,
      ),
    ),
  );
  stdout.writeln('   OK，耗时 ${sw.elapsedMilliseconds}ms');

  // 0.7.0 起 App 会对每段识别结果补标点（CT-Transformer，随模型一起下载）。
  // 本地开发目录里放一份 punct_model.int8.onnx 时脚本与 App 同管线；
  // 没有也不报错，只是输出白文。
  sherpa.OfflinePunctuation? punct;
  final punctFile = '$modelDir/punct_model.int8.onnx';
  if (File(punctFile).existsSync()) {
    punct = sherpa.OfflinePunctuation(
      config: sherpa.OfflinePunctuationConfig(
        model: sherpa.OfflinePunctuationModelConfig(
          ctTransformer: punctFile,
          numThreads: 1,
          debug: false,
        ),
      ),
    );
    stdout.writeln('== 加载标点模型 ==\n   OK');
  }

  var ok = 0;
  var silent = 0;
  var silentChunks = 0;
  for (final wav in wavs) {
    final wave = sherpa.readWave(wav);
    if (wave.samples.isEmpty) {
      stdout.writeln('\n$wav\n   !! 读不出波形（文件坏了或不是 wav）');
      continue;
    }
    final seconds = wave.samples.length / wave.sampleRate;
    final level = judgeSpeechFloat(wave.samples, wave.sampleRate);
    // 判不了（null）按放过处理：这里的目的是"别把模型在静音上的幻觉当成成功"，
    // 而不是给自己加一道可能误拦的闸。
    final tooQuiet = level != null && level.seemsSilent;
    silentChunks = 0;
    final t = Stopwatch()..start();
    // 0.5.11 起：与 App 共用分段解码（Paraformer 整段解码超过 ~40s 中段崩坏，
    // 见 audio_chunker.dart 头注）。这里必须走同一份 planChunks，
    // 否则"脚本里过关、应用里失灵"的漂移迟早出事。
    final ranges = planChunks(wave.samples, wave.sampleRate);
    final parts = <String>[];
    var skipped = 0;
    for (final r in ranges) {
      // 与 App 同款：静音段直接跳过不解码（模型在无人声输入上会编话）
      final chunk = Float32List.sublistView(wave.samples, r.start, r.end);
      final chunkLevel = judgeSpeechFloat(chunk, wave.sampleRate);
      if (chunkLevel != null && chunkLevel.seemsSilent) {
        skipped++;
        continue;
      }
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: chunk, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      // 与 App 同款：每段单独补标点（段最长 20s，远在标点模型输入上限内）
      final raw = recognizer.getResult(stream).text.trim();
      parts.add(punct == null ? raw : punct.addPunct(raw));
      stream.free();
    }
    final text = joinTranscripts(parts);
    t.stop();
    if (skipped > 0) silentChunks = skipped;

    // 关键：近静音时的输出**不能**算作识别成功——那是模型在噪声上的幻觉，
    // 读起来往往很像人话，最容易骗过"看一眼觉得没问题"的复核。
    final String verdict;
    if (tooQuiet) {
      verdict = '输入里没有检测到人声，结果不可信';
      silent++;
    } else if (text.trim().isEmpty) {
      verdict = '空!!';
    } else {
      verdict = '有内容';
      ok++;
    }
    stdout.writeln('\n${wav.split(Platform.pathSeparator).last}'
        '  [${wave.sampleRate}Hz, ${seconds.toStringAsFixed(2)}s'
        '${ranges.length > 1 ? '，分 ${ranges.length} 段' : ''}'
        '${silentChunks > 0 ? '，跳过静音 $silentChunks 段' : ''}, '
        '${level?.summary ?? '电平判不了（按放过处理）'}, '
        '识别 ${t.elapsedMilliseconds}ms, $verdict]');
    stdout.writeln('   → $text');
  }
  punct?.free();
  recognizer.free();

  stdout.writeln('\n== 结果：$ok/${wavs.length} 段出了可信内容'
      '${silent > 0 ? '，$silent 段因输入近乎静音而结果不可信' : ''} ==');
  if (silent > 0) {
    stdout.writeln('   提示：静音段多半是采集端的问题（麦克风没接上 / 模拟器 -no-audio / '
        '权限被拒），不是模型的问题。别拿这种结果当识别成功。');
  }
  if (ok == 0) exitCode = 1;
}

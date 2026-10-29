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

// 校验「录音电平判据」在**真实 WAV 文件**上判得对不对。
//
// 为什么单测不够：`test/audio_level_test.dart` 里的 WAV 是**自己拼的字节**，
// 拿自己造的数据验自己的实现，很容易"自洽地骗过自己"——两边对同一处
// 理解偏差时，测试照样全绿。而这一层判错的代价是双向的：
// 判松了会存下模型编的假梦，判紧了会把用户真实说的话丢掉。
//
// 所以这里做四件事：
//   1. **交叉验证**：把本工程的 WAV 解析结果，与 sherpa-onnx 自带的解码器
//      （`sherpa.readWave`，一个完全独立的实现）逐文件比对。峰值对不上
//      就说明解析器有问题。（峰值 0.4.4 起不参与判定，但它是最适合用来
//      交叉验证解析器的量：一个数就能覆盖整段采样。）
//   2. **确认真人说话不会被误拦**。
//   3. **逐级衰减**：把每段真人语音整体调轻 10/20/…/50dB 再判一遍。
//      这一条针对的是一个很实在的用户场景——**凌晨怕吵醒人，压着嗓子说话**。
//      判据是相对的（比这段自己的噪声底高多少），所以占比本该几乎不随音量变。
//      哪天有人往判据里加了一条绝对下限，这一节会立刻红给他看。
//   4. **反向**：没有人在说话的几类输入（稳态噪声、单次冲击、数字静音）
//      必须被拦住。0.4.4 之前峰值判据正是在这里失手的。
//
// 跑法：
//   tool/f.sh dart run tool/audio_level_check.dart [wav...]
// 不给参数时默认跑 ../validation/asr_samples/ 下的全部 wav。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dream_reader/services/audio_level.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 两个实现对同一份 16-bit PCM 的峰值，允许的差（dB）。
/// 不该有差异——留一点浮点余量，免得因为最后一位的舍入误报。
const double _kPeakToleranceDb = 0.05;

/// 逐级衰减的档位（dB）。
const List<double> _kAttenuationSteps = [0, -10, -20, -30, -40, -50];

void main(List<String> args) {
  final files = args.isNotEmpty
      ? args
      : (Directory('../validation/asr_samples')
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .where((p) => p.endsWith('.wav'))
              .toList()
          ..sort());

  if (files.isEmpty) {
    stderr.writeln('没找到任何 wav 文件');
    exitCode = 2;
    return;
  }

  stdout.writeln('== 加载 sherpa 原生库（用作独立参照）==');
  sherpa.initBindings();

  var mismatched = 0;
  var falselySilent = 0;
  final margins = <double>[];

  stdout.writeln('\n== 1. 解析器交叉验证 + 判据（原声）==');
  for (final path in files) {
    final name = path.split(Platform.pathSeparator).last;

    final bytes = File(path).readAsBytesSync();
    final mine = analyzePcm16Wav(bytes);
    if (mine == null) {
      stdout.writeln('\n$name\n   !! 本工程的解析器读不了这个文件（返回 null）'
          '—— 应用里会"放过"，但这多半说明解析器有漏判');
      mismatched++;
      continue;
    }

    final ref = sherpa.readWave(path);
    final refDb = peakDbfsOf(ref.samples);
    final delta = (mine.peakDbfs - refDb).abs();

    // 两边都落到"全静音"兜底值时，数值上可能都不是精确的 -120，但那属于同一档
    final bothSilent =
        mine.peakDbfs <= kDigitalSilenceDbfs && refDb <= kDigitalSilenceDbfs;
    final agreed = delta <= _kPeakToleranceDb || bothSilent;
    if (!agreed) mismatched++;

    // 真人说话的样本被误判成静音 = 会把用户真说的话丢掉，最不能接受
    final isRealSpeechSample = !name.contains('silence');
    if (mine.seemsSilent && isRealSpeechSample) falselySilent++;
    if (!mine.seemsSilent) {
      margins.add(mine.voicedPitchRatio - kPitchVoicedFloor);
    }

    stdout.writeln('\n$name');
    stdout.writeln('   本工程解析: ${mine.sampleRate}Hz, '
        '${mine.durationSeconds.toStringAsFixed(2)}s, '
        '${mine.sampleCount} 采样, '
        '峰值 ${mine.peakDbfs.toStringAsFixed(2)}dBFS');
    stdout.writeln('   sherpa 参照: ${ref.sampleRate}Hz, '
        '${ref.samples.length} 采样, '
        '峰值 ${refDb.toStringAsFixed(2)}dBFS   '
        '${agreed ? '一致' : '❌ 差 ${delta.toStringAsFixed(2)}dB'}');
    stdout.writeln('   判定: ${mine.summary}');
    stdout.writeln('        → ${mine.seemsSilent ? '没有人声，不送识别' : '有人声，正常送识别'}'
        '${mine.seemsSilent && isRealSpeechSample ? '   ← ❌ 误拦真人语音！' : ''}');
  }

  stdout.writeln('\n== 2. ★ 逐级衰减：说得再轻也要认出来 ==');
  stdout.writeln('   （单元格 = 浊音帧占比；判据线 ${(kPitchVoicedFloor * 100).toStringAsFixed(0)}%，'
      '低于它就会被判成"没人在说话"）');
  final header = ['样本'] + _kAttenuationSteps.map((d) => d == 0 ? '原声' : '${d.toInt()}dB').toList();
  stdout.writeln('   ${header.map((h) => h.padLeft(9)).join('')}');
  var worstRatio = 1.0;
  var worstWhere = '';
  for (final path in files) {
    final name = path.split(Platform.pathSeparator).last;
    if (name.contains('silence')) continue;
    final base = _int16OfPcm16Wav(File(path).readAsBytesSync());
    if (base == null) continue;
    final cells = <String>[];
    for (final d in _kAttenuationSteps) {
      final r = judgeSpeech(_attenuate(base.samples, d), base.sampleRate);
      if (r == null) {
        cells.add('        -');
        continue;
      }
      cells.add('${(r.voicedPitchRatio * 100).toStringAsFixed(1)}%'.padLeft(9));
      if (r.voicedPitchRatio < worstRatio) {
        worstRatio = r.voicedPitchRatio;
        worstWhere = '$name @${d.toInt()}dB';
      }
    }
    stdout.writeln('   ${name.padLeft(9)}${cells.join()}');
  }
  stdout.writeln('   最差一格：${(worstRatio * 100).toStringAsFixed(1)}%'
      '（$worstWhere），距判据线还有 '
      '${(worstRatio / kPitchVoicedFloor).toStringAsFixed(1)} 倍余量');

  stdout.writeln('\n== 3. 反向：没有人在说话的输入必须拦住 ==');
  var leaked = 0;
  for (final c in _negativeCases()) {
    final r = judgeSpeech(c.samples, 16000);
    final passed = r == null || !r.seemsSilent;
    if (passed) leaked++;
    stdout.writeln('   ${c.name.padRight(30)}'
        '${r == null ? '判不了（按放过处理）' : r.summary}'
        ' → ${passed ? '❌ 放过了' : '✅ 拦住'}');
  }

  stdout.writeln('\n== 结果 ==');
  stdout.writeln('   文件数 ${files.length}，'
      '与参照解码器不一致 $mismatched，'
      '误判为静音的真话样本 $falselySilent，'
      '该拦没拦的合成输入 $leaked');

  if (falselySilent > 0) {
    stdout.writeln('   ★ 有真人语音被误判成静音。这一层会丢掉用户真实说的话，'
        '必须先把判据或解析器修好。');
  }
  if (leaked > 0) {
    stdout.writeln('   ★ 有"没有人在说话"的输入被放过。模型的失败形态是编一句话出来，'
        '所以这里放过就等于可能存下一条假梦。');
  }
  if (margins.isNotEmpty) {
    margins.sort();
    stdout.writeln('   原声距判据线的最小余量：'
        '${(margins.first * 100).toStringAsFixed(1)} 个百分点'
        '（${(margins.first + kPitchVoicedFloor).toStringAsFixed(3)} vs '
        '${kPitchVoicedFloor.toStringAsFixed(3)}）');
  }

  if (mismatched > 0 ||
      falselySilent > 0 ||
      leaked > 0 ||
      worstRatio < kPitchVoicedFloor) {
    exitCode = 1;
  }
}

/// 把 16-bit 采样整体乘一个增益（模拟"离得远 / 说得轻"）。
Int16List _attenuate(Int16List samples, double db) {
  if (db == 0) return samples;
  final g = math.pow(10, db / 20).toDouble();
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i] * g).round();
    out[i] = v > 32767 ? 32767 : (v < -32768 ? -32768 : v);
  }
  return out;
}

/// 从 WAV 字节里拿纯采样（解析本身在 `analyzePcm16Wav` 里，这里只要数据）。
class _Pcm {
  const _Pcm(this.samples, this.sampleRate);
  final Int16List samples;
  final int sampleRate;
}

_Pcm? _int16OfPcm16Wav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final bd = ByteData.sublistView(bytes);
  var offset = 12;
  int? dataOffset;
  var dataLength = 0;
  int? sampleRate;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = bd.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      sampleRate = bd.getUint32(body + 4, Endian.little);
    } else if (id == 'data') {
      if (body > bytes.length) return null;
      dataOffset = body;
      final available = bytes.length - body;
      dataLength = (size == 0 || size > available) ? available : size;
    }
    final advance = 8 + size + (size & 1);
    if (advance <= 8) break;
    offset += advance;
  }
  if (dataOffset == null || sampleRate == null || dataLength < 2) return null;
  final data = ByteData.sublistView(bytes, dataOffset, dataOffset + dataLength);
  final count = data.lengthInBytes ~/ 2;
  final samples = Int16List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little);
  }
  return _Pcm(samples, sampleRate);
}

/// 一类"没有人在说话"的合成输入。
class _NegativeCase {
  const _NegativeCase(this.name, this.samples);
  final String name;
  final Int16List samples;
}

/// 造几类**该被拦住**的输入。
///
/// 都是按真机上实际会发生的形态造的，不是随手写个数：
/// - 稳态噪声：空调、风扇——峰值可以很高，能量却是平的；
/// - 单次冲击：翻被子、碰到手机、以及**开录那一刻 App 自己发的震动**
///   （见 `record_page.dart` 里紧挨着 `_recorder.start()` 的那句触觉反馈）；
/// - 数字静音：模拟器 `-no-audio`。
List<_NegativeCase> _negativeCases() {
  const sr = 16000;
  final cases = <_NegativeCase>[];

  cases.add(_NegativeCase('纯数字静音 5s', Int16List(5 * sr)));
  cases.add(_NegativeCase('稳态噪声（空调/风扇）5s', _noise(sr * 5, -45, 7)));
  cases.add(_NegativeCase('稳态噪声更响 -30dB', _noise(sr * 5, -30, 7)));
  cases.add(_NegativeCase(
    '安静 + 一记震动 0.15s',
    _mix([
      _silence(sr * 2),
      _noise((sr * 0.15).round(), -20, 8),
      _silence(sr * 3),
    ]),
  ));
  cases.add(_NegativeCase(
    '安静 + 一次翻被子 0.05s',
    _mix([
      _noise(sr * 3, -55, 7),
      _noise((sr * 0.05).round(), -19, 8),
      _noise(sr * 2, -55, 7),
    ]),
  ));

  return cases;
}

Int16List _silence(int n) => Int16List(n);

/// 均匀噪声，峰值给到 [peakDbfs]。
Int16List _noise(int n, double peakDbfs, int seed) {
  final rnd = math.Random(seed);
  final amp = 32768 * math.pow(10, peakDbfs / 20).toDouble();
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = ((rnd.nextDouble() * 2 - 1) * amp).round().clamp(-32768, 32767);
  }
  return out;
}

Int16List _mix(List<Int16List> parts) {
  final total = parts.fold<int>(0, (a, b) => a + b.length);
  final out = Int16List(total);
  var at = 0;
  for (final p in parts) {
    out.setAll(at, p);
    at += p.length;
  }
  return out;
}

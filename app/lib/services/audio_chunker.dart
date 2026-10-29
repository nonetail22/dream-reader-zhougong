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

/// 长录音的分段解码规划（纯 Dart，不依赖 Flutter，可进 `dart test`）。
///
/// ## 为什么必须有这一层（2026-10-27，0.5.11）
///
/// 用户真机反馈「说了好多，能识别出来的很少」，而录音回放清晰完整——
/// 采集端没问题，问题在识别侧。Mac 上拿真实样本做的实验钉死了根因：
/// Paraformer 是**整段解码**，输入短于 ~34s 时几乎全对（同一段话重复 3 次、
/// 6 次、混两种句子都完整复原），但 **56.1s 时中段整段崩坏**——开头结尾
/// 正常，中间融化成「对我我的是是我我我如对我的究感绍大…」这种乱码。
/// 这正是「说几分钟 → 中段全烂 → 出字很少」的完整解释。
///
/// ## 修法
///
/// 把长录音在**停顿处**（帧能量最低的点）切成若干 ≤[kChunkMaxMs] 的短段，
/// 每段单独解码后拼接。分段器只负责「在哪里切」，解码循环留在调用方
/// （应用里的 `SherpaOnnxTranscriber` 和 Mac 端的 `offline_asr_smoke.dart`
/// 共用这一份规划，保证脚本里过关的就是应用里跑的那条路）。
///
/// 切点选在局部能量最低处而不是硬按时长切：硬切会把一个字劈成两半，
/// 两半各自解码都会错。找最低能量点 = 找最接近目标时长的自然停顿。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 分段的目标时长。远低于 ~40s 的崩坏线，也贴近 Paraformer 训练时的
/// 常见句长（短句为主）。
const int kChunkTargetMs = 12000;

/// 单段上限。超过它就必须继续切；[kChunkTargetMs] 是想要的值，
/// [kChunkMaxMs] 是兜住的值——目标点附近实在找不到停顿时，允许略微超出目标。
const int kChunkMaxMs = 20000;

/// 在目标切点前后多大的窗口里找「最低能量点」。
///
/// 太窄会错过目标点附近的自然停顿，太宽会让段长失控。±4s 配 12s 目标，
/// 最长 16s，仍在 20s 上限之内。
const int kChunkSearchWindowMs = 4000;

/// 一段音频的取样范围，`[start, end)`，单位是采样。
class AudioRange {
  const AudioRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  String toString() => '[$start,$end)';
}

/// 规划分段：返回覆盖 `[0, samples.length)`、彼此不重叠的段列表，
/// 每段 ≤ [kChunkMaxMs] 个采样；总长不足时返回单段（不复制、不改动）。
///
/// 输入用 [-1, 1] 浮点采样（与 `judgeSpeechFloat`、`sherpa.readWave` 同一
/// 口径），采样率任意（8k 的历史录音同样适用——帧长按采样率折算）。
List<AudioRange> planChunks(Float32List samples, int sampleRate) {
  if (sampleRate <= 0 || samples.isEmpty) {
    return samples.isEmpty ? const [] : const [AudioRange(0, 0)];
  }
  final maxLen = sampleRate * kChunkMaxMs ~/ 1000;
  if (maxLen <= 0 || samples.length <= maxLen) {
    return [AudioRange(0, samples.length)];
  }
  final targetLen = sampleRate * kChunkTargetMs ~/ 1000;
  final windowLen = sampleRate * kChunkSearchWindowMs ~/ 1000;
  final frameLen = math.max(1, sampleRate * 20 ~/ 1000); // 20ms 一帧，与判据同款

  final out = <AudioRange>[];
  var start = 0;
  while (samples.length - start > maxLen) {
    final split = _quietestSplitPoint(
      samples,
      from: start,
      target: start + targetLen,
      window: windowLen,
      frameLen: frameLen,
      limit: samples.length,
    );
    out.add(AudioRange(start, split));
    start = split;
  }
  out.add(AudioRange(start, samples.length));
  return out;
}

/// 在 `target` 附近（±window/2，且不越过 `from`/`limit`）找能量最低的一帧，
/// 返回该帧的起点采样。找不到更优位置时回落到 `target` 本身。
///
/// 保底约束：返回值严格大于 `from`——否则外层 while 会死循环。
int _quietestSplitPoint(
  Float32List samples, {
  required int from,
  required int target,
  required int window,
  required int frameLen,
  required int limit,
}) {
  var lo = math.max(from + frameLen, target - window ~/ 2);
  var hi = math.min(limit - 1, target + window ~/ 2);
  if (hi <= lo) {
    // 窗口被边界挤没了：硬按 target 切，但必须落在 (from, limit) 里。
    return math.min(math.max(from + frameLen, target), limit - 1);
  }
  var bestAt = -1;
  var bestEnergy = double.infinity;
  for (var at = lo; at < hi; at += frameLen) {
    var e = 0.0;
    final end = math.min(at + frameLen, limit);
    for (var i = at; i < end; i++) {
      final v = samples[i];
      e += v * v;
    }
    if (e < bestEnergy) {
      bestEnergy = e;
      bestAt = at;
    }
  }
  if (bestAt < 0) return target;
  return bestAt;
}

/// 拼接分段解码出的文字。
///
/// 中文段落直接相连；但若相邻两段在切点两侧都是 ASCII 字母/数字
/// （中英混说时切点可能落在英文句中间），补一个空格，避免把
/// `nightmare` 和 `about` 拼成 `nightmareabout`。空段丢弃。
String joinTranscripts(Iterable<String> parts) {
  final sb = StringBuffer();
  var lastIsAlnum = false;
  for (final raw in parts) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    final first = t.runes.first;
    final firstIsAlnum = _isAsciiAlnum(first);
    if (sb.isNotEmpty && lastIsAlnum && firstIsAlnum) sb.write(' ');
    sb.write(t);
    lastIsAlnum = _isAsciiAlnum(t.runes.last);
  }
  return sb.toString();
}

bool _isAsciiAlnum(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A);

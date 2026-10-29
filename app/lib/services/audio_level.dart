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

/// 「这段录音里到底有没有人说话」——**在送识别之前**先量输入。
///
/// 为什么必须有这一层：本项目的离线识别模型（Paraformer）遇到近乎静音的输入
/// **不会返回空字符串，而是会编出一句像模像样的话**。这个坑踩过两次：
/// 第一次在验证脚本里（模拟器 `-no-audio`，模型吐出「我的我的我的朋了」），
/// 第二次是 0.3.0 的录音按钮改成「点一下开始 / 再点一下结束」之后——
/// 点开、忘了说话、过几秒再点结束，**时长判据过得去**，于是那句编造的话
/// 被当成一条梦境记录存了下来。
///
/// 对一个卖点是「可查证性」的梦境应用来说，这是最坏的一类失败：
/// 用户会**把模型编的话当成自己的梦**。所以判据必须落在输入端。
///
/// 这正是 README 第九节第 22 条的落地：**模型的失败形态是"给出一份看似合理的
/// 错结果"时，验证必须比对输入端，而不是看"有没有结果"。**
///
/// ## 判据为什么在 0.4.4 换掉了
///
/// 0.3.1 起用的是**峰值**：整段最响的那一毫秒的电平，低于 -50 dBFS 就当静音。
/// 真机上这个判据是失效的，用户的反馈是「不说话也会识别出乱七八糟的内容」。
/// 三个原因叠在一起：
///
/// 1. 峰值是**最大值**，不是"这段像不像人说话"。录音里只要出现过一次瞬时冲击，
///    峰值就被顶得很高，而其余几秒全是安静的，闸门照样放过。冲击的来源很实在：
///    `record_page.dart` 在开录前调 `HapticFeedback.mediumImpact()` ——
///    **每一次录音的开头都带着 App 自己发的震动**，而震动是机械耦合进麦克风的。
/// 2. 阈值 -50 dBFS 的两个参照物是「真人语音 -0~-9」和「采集静音 -72」，
///    而后者是**模拟器 -no-audio 的数字静音**，不是真机环境噪声。
///    真机夜里录到的空调/风扇噪声峰值常在 -50~-35，正好压在线上——
///    也就是说这条线从来没在真机噪声上验证过。
/// 3. 判据只有一条绝对线，于是**轻声说话和稳态噪声落在同一段区间里**，
///    没有量能把它俩分开。
///
/// ## 换成什么
///
/// 切成 20ms 一帧，逐帧算能量，拿这段**自己的**低分位帧当噪声底，
/// 数有多少帧比噪声底高出 10 dB，占比过 5% 才认为有人在说话。
///
/// 这个量回答的是"这段里有没有**结构**"——人说话是断断续续的爆发，
/// 稳态噪声的能量是平的。于是：
/// - 真人语音（实测 7 段样本）：占比 70%~91%，**且逐级衰减到 -50dB 后最差仍有
///   53%**，因为判据只看相对这段自己的噪声底，**说得轻和说得响判出来一样**；
/// - 空调/风扇噪声（峰值 -45 甚至 -30）：占比 0%；
/// - 一次翻被子（峰值 -19）：1.2%；开头一记震动（0.15s）：3.2%；
/// - 纯数字静音：0%。
///
/// 一句话：**不该放过的拦住了，而真人说话（包括凌晨压着嗓子说的那句）
/// 一步都没被挤到**。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';


/// 帧长（毫秒）。
///
/// 20ms 是语音处理的常规取值：短到能贴住一个音节的起落，长到一帧里有几百个
/// 采样、能量估计足够稳。再短的话单帧 RMS 会被个别采样带跑。
const int kSpeechFrameMs = 20;

/// 噪声底取帧能量的第几百分位。
///
/// 不取最小值：万一段里混进一小段数字静音，最小值会被拉到 -120，
/// 噪声底就没了。5% 既躲得开个别异常帧，又足够贴近真实底噪。
const double kNoiseFloorPercentile = 0.05;

/// 一帧要高出噪声底多少 dB，才算"这一帧里有人在说话"。
///
/// 10 dB 的依据：稳态噪声的帧间波动在 1 dB 以内（20ms、几百个采样取平均，
/// 方差极小），而语音的帧间起伏动辄 30~40 dB。10 dB 离两边都很远。
const double kSpeechOverFloorDb = 10.0;

/// ★ 以下两个是**能量占比**口径，仅作诊断留档，**已不是判据**。
///
/// 0.4.4 起判定就看"帧能量的结构（相对噪声底高出多少）"，0.5.9 把这道能量闸的
/// 拦截线从 0.05 提到 0.10。但它有个根治不了的病：呼气 / 稳态噪声这些**非语音**
/// 输入，时间占比也很低，和"轻声、稀疏的真人语音"在能量占比这个维度上**分不清**——
/// 于是 0.5.9 把线提到 0.10 后，用户"正常说话（尤其凌晨压着嗓子、说得轻、停顿多）"
/// 反而被误判成静音，这是一次回退。真正把两者分开的是**有没有人声基音**，见
/// [kPitchVoicedFloor] 与 2026-10-01 的修订。
const double kVoiceRatioFloor = 0.10;

/// 同上，能量口径的低置信线，仅诊断。真正生效的是 [kPitchVoicedConfident]。
const double kVoiceRatioConfident = 0.25;

/// 浊音（有基音）帧占比低于这个就**直接判为"没人在说话"，不送识别**。
///
/// **为什么从能量占比换到基音**：能量占比只回答"这段里有多少帧比噪声底响 10dB"，
/// 它**分不清**「轻声、稀疏的真人语音」和「呼气 / 一记环境噪声」——两者时间占比都低，
/// 于是 0.5.9 把拦截线提到 0.10 后，用户"正常说话"反而被误杀（一次回退）。
/// 基音检测只看"这段里有没有 70~400Hz 的周期性"：人声元音有强周期性（自相关峰 >0.4），
/// 呼气 / 稳态噪声 / 一记咔哒几乎没有（峰≈0），而且**与音量无关**——轻声软语照样
/// 测得到基音。于是轻声短句的真话（有基音 → 占比>0）能过，呼气噪声（无基音 → 占比≈0）
/// 照样拦死，两个目标同时达成，0.5.9 修好的"呼气被拦"也没被退回去。
///
/// 数值 0.03 很松：真实语音的浊音占比普遍 0.7+，即便稀疏到"5% 的时间是说话"也远高于此；
/// 而一切非语音的浊音占比都是 0，拦得死死的。[audio_level_check.dart] 拿真实样本与
/// 合成负样本双向守住，且 0.5.9 那条"0.4s 呼气 ≈7.4%"的负样本改用宽带噪声复测仍=0。
const double kPitchVoicedFloor = 0.03;

/// 浊音帧占比低于这个、又不算"静音"的，标为**低置信**：仍送识别、仍落盘，
/// 但调用方应提示用户"几乎没听到人声，结果可能不准"。
///
/// 划在 0.12：真实语音（0.7+）远在其上，这条线以下几乎只是"极稀疏的真话
/// （比如 5%~12% 的时间是说话）"这类边缘，既不丢话、又给一句警示。
const double kPitchVoicedConfident = 0.12;

/// 判据的绝对下限，只用来挡病态输入，**不是主判据**。
///
/// 主判据是相对的（噪声底 + 10 dB），这样才不受录音整体音量影响。
/// 这一条的存在只是为了防止"整段低到没有意义"的输入被算成有人声——
/// 低于这个电平的帧，就算相对抬升够了也不作数。
///
/// **不要为了调松/调紧去动这个数**：它一旦抬高到人声区间，就会重新犯
/// 0.4.4 之前那个错——把凌晨轻声说的话判掉。要调就调 [kVoiceRatioFloor]。
const double kAbsoluteDbfsFloor = -90.0;

/// 帧数少于这个值就**不判**（返回 null = 放过）。
///
/// 5 帧 = 100ms。要估"这段自己的噪声底"至少得有这么多帧，否则那几个数
/// 里凑不出一个低分位。真机上录音有 800ms 的最短时长兜着（见 record_page），
/// 走不到这里。
const int kMinFramesForJudgement = 5;

/// 全 0 采样时用它代替 `-inf`，免得下游格式化出一个 `-Infinity`。
const double kDigitalSilenceDbfs = -120.0;

/// 一份音频的「有没有人声」结论。
class SpeechPresence {
  const SpeechPresence({
    required this.peakDbfs,
    required this.noiseFloorDbfs,
    required this.voicedRatio,
    required this.voicedPitchRatio,
    required this.sampleCount,
    required this.sampleRate,
  });

  /// 峰值电平（dBFS），越大越响。
  ///
  /// 0.4.4 起**不再参与判定**，只作诊断留档：排查"是不是一记冲击把这段
  /// 顶出来的"时，峰值和噪声底放在一起看最直接。
  final double peakDbfs;

  /// 这段自己的噪声底（帧能量的低分位），单位 dBFS。
  final double noiseFloorDbfs;

  /// 高出「噪声底 + [kSpeechOverFloorDb] dB」的帧占全部帧的比例，0~1。
  ///
  /// **能量口径，仅供诊断**（2026-10-01 起判据改用基音，见下）。
  final double voicedRatio;

  /// 有**基音（浊音）**的帧占全部帧的比例，0~1。
  ///
  /// 这是判定真正依赖的量：人声元音有基音，呼气 / 稳态噪声 / 一记咔哒没有，
  /// 且与音量无关（轻声软语照样测得到）。详见 [kPitchVoicedFloor]。
  final double voicedPitchRatio;

  final int sampleCount;
  final int sampleRate;

  /// 没有检测到人声（没有基音）→ 不要送去识别。
  bool get seemsSilent => voicedPitchRatio < kPitchVoicedFloor;

  /// 听到了一些声音、但离"可靠的人声"还差得远：仍送识别、仍落盘，
  /// 但调用方应提示用户核对（见 [kPitchVoicedConfident]）。
  ///
  /// 既不"静音拦截"（那会丢真实但很短的语音），也不"当成正常结果"——
  /// 给用户一句"可能不准"的提醒，把判断权交回去。
  bool get lowConfidence =>
      !seemsSilent && voicedPitchRatio < kPitchVoicedConfident;

  double get durationSeconds =>
      sampleRate <= 0 ? 0 : sampleCount / sampleRate;

  /// 给日志/诊断用的一行摘要（**不直接给用户看**，dBFS 对用户没有意义）。
  String get summary => '峰值 ${peakDbfs.toStringAsFixed(1)} / '
      '噪声底 ${noiseFloorDbfs.toStringAsFixed(1)} dBFS，'
      '有声帧 ${(voicedRatio * 100).toStringAsFixed(1)}%（能量） / '
      '浊音 ${(voicedPitchRatio * 100).toStringAsFixed(1)}%（基音），'
      '共 ${durationSeconds.toStringAsFixed(1)}s @ ${sampleRate}Hz';
}

/// 峰值 dBFS（输入是 [-1, 1] 的浮点采样）。
///
/// 供 `tool/offline_asr_smoke.dart` 复用——那里拿到的已经是 sherpa 解好的
/// `Float32List`，不必再走一遍 WAV 解析。**判据只有一份实现**，
/// 否则脚本里过关、应用里失灵（或反过来）这种漂移迟早发生。
double peakDbfsOf(Float32List samples) {
  var peak = 0.0;
  for (final s in samples) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  return _dbfsOfNormalizedPeak(peak);
}

/// 从 16-bit 定点采样算峰值 dBFS（满量程 32768）。
double peakDbfsOfInt16(Int16List samples) {
  var peak = 0;
  for (final s in samples) {
    final a = s < 0 ? -s : s;
    if (a > peak) peak = a;
  }
  return _dbfsOfNormalizedPeak(peak / 32768.0);
}

double _dbfsOfNormalizedPeak(double peak) {
  if (peak <= 0) return kDigitalSilenceDbfs;
  return 20.0 * (math.log(peak) / math.ln10);
}

/// 判据核心（唯一一份实现）：给一段 16-bit 采样，判断里面有没有人声。
///
/// 单独暴露出来（而不是只在 [analyzePcm16Wav] 里）是为了两件事：
/// - `tool/audio_level_check.dart` 要做**逐级衰减**的检验，
///   那是拿同一段采样乘系数再判一次，不该为此把 WAV 重新拼一遍；
/// - 单测可以直接喂"自己造的波形"，不必绕 WAV 解析——但反过来，
///   `audio_level_check` 会拿**真实文件**的结果与 sherpa 的独立解码器对齐，
///   防止"造的数据验证造的实现"这种自洽的骗法。
///
/// 一帧是否"有基音（浊音）"：在 70~400Hz 区间找归一化自相关峰。
///
/// 人声元音有强周期性 → 峰 >0.4；呼气 / 稳态噪声 / 一记咔哒几乎没有 → 峰≈0。
/// 与音量无关（轻声软语照样测得到），于是能把"轻声的真话"和"呼气噪声"分开。
/// 极低能量（< ≈-80dBFS）直接判无基音，顺带排除微弱的周期嗡鸣。
bool _frameHasPitch(Float64List frame, int sampleRate) {
  final n = frame.length;
  final lo = (sampleRate / 400).round(); // 400Hz 的最短周期（采样数）
  var hi = (sampleRate / 70).round(); // 70Hz 的最长周期
  if (hi > n ~/ 2) hi = n ~/ 2;
  if (lo < 1 || hi <= lo) return false;
  double e = 0.0;
  for (var i = 0; i < n; i++) {
    final v = frame[i];
    e += v * v;
  }
  e = math.sqrt(e / n);
  // 极弱能量直接判无基音。门槛与能量口径的绝对下限 [kAbsoluteDbfsFloor](-90dBFS)
  // 对齐：这一层绝不比"能量该拦的下限"更紧，免得把极轻但真实的话语漏掉。
  if (e < 3.16e-5) return false; // ≈ -90 dBFS
  double best = 0.0;
  for (var lag = lo; lag <= hi; lag++) {
    double s = 0.0;
    for (var i = 0; i < n - lag; i++) {
      s += frame[i] * frame[i + lag];
    }
    s /= (n - lag);
    final norm = s / (e * e);
    if (norm > best) best = norm;
  }
  return best > 0.4;
}

/// 在一整段采样上统计"有基音的帧占比"。[toFloat] 把第 i 个采样取成 [-1,1] 浮点。
double _pitchVoicedRatio(
  int sampleCount,
  int frameLength,
  int frameCount,
  int sampleRate,
  double Function(int) toFloat,
) {
  final buf = Float64List(frameLength);
  var pitched = 0;
  for (var f = 0; f < frameCount; f++) {
    final base = f * frameLength;
    for (var i = 0; i < frameLength; i++) {
      buf[i] = toFloat(base + i);
    }
    if (_frameHasPitch(buf, sampleRate)) pitched++;
  }
  return pitched / frameCount;
}

/// 返回 `null` 表示**判不了**，调用方必须当作**放过**：帧数不够估噪声底。
SpeechPresence? judgeSpeech(Int16List samples, int sampleRate) {
  if (sampleRate <= 0) return null;

  final frameLength = sampleRate * kSpeechFrameMs ~/ 1000;
  if (frameLength < 2) return null;

  final frameCount = samples.length ~/ frameLength;
  if (frameCount < kMinFramesForJudgement) return null;

  final frames = List<double>.filled(frameCount, kDigitalSilenceDbfs);
  for (var f = 0; f < frameCount; f++) {
    final base = f * frameLength;
    var sum = 0.0;
    for (var i = 0; i < frameLength; i++) {
      final v = samples[base + i] / 32768.0;
      sum += v * v;
    }
    frames[f] = _dbfsOfNormalizedPeak(math.sqrt(sum / frameLength));
  }

  final pitchedRatio = _pitchVoicedRatio(
    samples.length,
    frameLength,
    frameCount,
    sampleRate,
    (i) => samples[i] / 32768.0,
  );

  return _conclude(
    frames,
    peakDbfs: peakDbfsOfInt16(samples),
    sampleCount: samples.length,
    sampleRate: sampleRate,
    voicedPitchRatio: pitchedRatio,
  );
}

/// 同上，但输入是 [-1, 1] 的浮点采样。
///
/// 给 `tool/offline_asr_smoke.dart` 用：那边拿到的已经是 sherpa 解好的
/// `Float32List`，再转回 int16 会有一次没必要的量化（还可能把超过 ±1 的
/// 采样截断）。判据本体仍是 [_conclude] 那一份。
SpeechPresence? judgeSpeechFloat(Float32List samples, int sampleRate) {
  if (sampleRate <= 0) return null;

  final frameLength = sampleRate * kSpeechFrameMs ~/ 1000;
  if (frameLength < 2) return null;

  final frameCount = samples.length ~/ frameLength;
  if (frameCount < kMinFramesForJudgement) return null;

  final frames = List<double>.filled(frameCount, kDigitalSilenceDbfs);
  var peak = 0.0;
  for (var f = 0; f < frameCount; f++) {
    final base = f * frameLength;
    var sum = 0.0;
    for (var i = 0; i < frameLength; i++) {
      final v = samples[base + i];
      final a = v.abs();
      if (a > peak) peak = a;
      sum += v * v;
    }
    frames[f] = _dbfsOfNormalizedPeak(math.sqrt(sum / frameLength));
  }
  // 尾部不足一帧的采样也算峰：峰值只作诊断，宁可比"参与判定那部分"更宽
  for (var i = frameCount * frameLength; i < samples.length; i++) {
    final a = samples[i].abs();
    if (a > peak) peak = a;
  }

  final pitchedRatio = _pitchVoicedRatio(
    samples.length,
    frameLength,
    frameCount,
    sampleRate,
    (i) => samples[i],
  );

  return _conclude(
    frames,
    peakDbfs: _dbfsOfNormalizedPeak(peak),
    sampleCount: samples.length,
    sampleRate: sampleRate,
    voicedPitchRatio: pitchedRatio,
  );
}

/// 逐帧能量 → 结论。判定规则只写在这里。
SpeechPresence? _conclude(
  List<double> frames, {
  required double peakDbfs,
  required int sampleCount,
  required int sampleRate,
  required double voicedPitchRatio,
}) {
  final frameCount = frames.length;
  if (frameCount < kMinFramesForJudgement) return null;

  final sorted = List<double>.of(frames)..sort();
  final floorIndex = (frameCount * kNoiseFloorPercentile).floor();
  final floor = sorted[floorIndex.clamp(0, frameCount - 1)];
  final threshold = math.max(floor + kSpeechOverFloorDb, kAbsoluteDbfsFloor);

  var voiced = 0;
  for (final v in frames) {
    if (v >= threshold) voiced++;
  }

  return SpeechPresence(
    peakDbfs: peakDbfs,
    noiseFloorDbfs: floor,
    voicedRatio: voiced / frameCount,
    voicedPitchRatio: voicedPitchRatio,
    sampleCount: sampleCount,
    sampleRate: sampleRate,
  );
}

/// 解析 **16-bit PCM WAV** 并给出电平结论。
///
/// **返回 `null` 的意思不是"静音"，而是"我判不了"**（不是 WAV、被截断、
/// 位深/编码不支持、短到估不出噪声底…）。调用方必须把 `null` 当作**放过**处理：
/// 宁可漏判一次静音，也不要因为解析器的一个 bug 把用户真实说的话丢掉。
SpeechPresence? analyzePcm16Wav(Uint8List bytes) {
  // RIFF 头：'RIFF' + size + 'WAVE'
  if (bytes.length < 12) return null;
  if (!_asciiIs(bytes, 0, 'RIFF') || !_asciiIs(bytes, 8, 'WAVE')) return null;

  final bd = ByteData.sublistView(bytes);
  int? bitsPerSample;
  int? sampleRate;
  int? audioFormat;
  int? dataOffset;
  var dataLength = 0;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _asciiAt(bytes, offset, 4);
    final size = bd.getUint32(offset + 4, Endian.little);
    final body = offset + 8;

    if (id == 'fmt ') {
      if (body + 16 > bytes.length) return null;
      audioFormat = bd.getUint16(body, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bitsPerSample = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (body > bytes.length) return null;
      dataOffset = body;
      final available = bytes.length - body;
      // 有些写入方在收尾时来不及回填长度（写成 0 或写成超大值），
      // 这时按"文件实际剩下的字节"算，别因此判成"读不了"。
      dataLength = (size == 0 || size > available) ? available : size;
      // 不 break：data 之后可能还有 chunk，但样本只需要 data 本身；
      // 这里继续循环是为了容忍 fmt 出现在 data 之后（少见但合法）。
    }

    // 块按偶数对齐（RIFF 规定），奇数长度后面补一个填充字节
    final advance = 8 + size + (size & 1);
    if (advance <= 8) break; // size 异常，避免死循环
    offset += advance;
  }

  if (audioFormat != 1) return null; // 只认未压缩 PCM
  if (bitsPerSample != 16) return null;
  if (dataOffset == null || dataLength < 2) return null;
  if (sampleRate == null) return null;

  final data = ByteData.sublistView(bytes, dataOffset, dataOffset + dataLength);
  final count = data.lengthInBytes ~/ 2;
  final samples = Int16List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little);
  }

  return judgeSpeech(samples, sampleRate);
}

/// 读文件版本。读不动（不存在 / 权限 / 正在写）也返回 `null` = 放过。
SpeechPresence? analyzeWavFile(String path) {
  try {
    return analyzePcm16Wav(File(path).readAsBytesSync());
  } catch (_) {
    return null;
  }
}

bool _asciiIs(Uint8List b, int at, String s) => _asciiAt(b, at, s.length) == s;

String _asciiAt(Uint8List b, int at, int len) {
  if (at + len > b.length) return '';
  final sb = StringBuffer();
  for (var i = 0; i < len; i++) {
    sb.writeCharCode(b[at + i]);
  }
  return sb.toString();
}

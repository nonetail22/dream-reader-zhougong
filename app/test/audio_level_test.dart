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

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dream_reader/services/audio_level.dart';
import 'package:test/test.dart';

/// 「送识别前先量输入」这一层的测试。
///
/// 为什么要专门测它：它是**唯一一道拦住"把模型编的话当成梦存下来"的闸**。
/// 而它有两个方向都会出事：
/// - **判松了**（该拦没拦）→ 用户存下一句模型编的假梦，最坏的一类失败；
/// - **判紧了**（不该拦却拦了）→ 把用户真实说的话丢掉，且**拿不回来**。
///
/// 所以下面两个方向都逐位钉住，尤其把「判不了就必须放过」这条语义钉死。
///
/// ## 0.4.4 判据换了，这份测试里有一组断言是**被故意反过来**的
///
/// 旧判据看峰值（最响那一瞬间），于是下面这几条当时是绿的：
///   - 「一个采样是巨响 → 有人声」
///   - 「恒定电平 104（刚过 -50）→ 有人声」
/// 它们钉住的恰恰是真机上的毛病：开录那一刻 App 自己发的震动、翻一下被子，
/// 都能把峰值顶上去，让一段没人说话的录音过关，然后模型编出一句话存下来。
/// 现在这几条连同新的「稳态噪声 / 单次冲击必须拦住」一起，
/// 反过来钉住"只看结构、不看最响那一瞬间"。
void main() {
  group('peakDbfsOf：浮点采样', () {
    test('全 0（数字静音）取兜底值，不返回 -Infinity', () {
      expect(peakDbfsOf(Float32List(1000)), kDigitalSilenceDbfs);
    });

    test('空输入也返回兜底值，不抛异常', () {
      expect(peakDbfsOf(Float32List(0)), kDigitalSilenceDbfs);
    });

    test('满量程 = 0 dBFS', () {
      expect(peakDbfsOf(Float32List.fromList([0.0, 1.0, -1.0, 0.2])), closeTo(0.0, 1e-9));
    });

    test('半量程 ≈ -6.02 dBFS', () {
      expect(peakDbfsOf(Float32List.fromList([0.5])), closeTo(-6.0206, 1e-3));
    });
  });

  group('peakDbfsOfInt16：16-bit 定点采样', () {
    test('全 0 → 兜底值', () {
      expect(peakDbfsOfInt16(Int16List(100)), kDigitalSilenceDbfs);
    });

    test('-32768（最小负值）归一化后取 0 dBFS，不因取绝对值溢出', () {
      // 绝对值 32768 > Int16.max，实现里刻意用 int 承接，不能让它溢出成负数
      expect(peakDbfsOfInt16(Int16List.fromList([-32768])), closeTo(0.0, 1e-9));
    });

    test('16384 ≈ -6.02 dBFS', () {
      expect(peakDbfsOfInt16(Int16List.fromList([16384])), closeTo(-6.0206, 1e-3));
    });
  });

  group('judgeSpeech：判定看的是"有没有结构"，不是"最响的那一瞬间"', () {
    test('数字静音 → 判为没有人声', () {
      final r = judgeSpeech(Int16List(_kOneSecond), 16000)!;
      expect(r.seemsSilent, isTrue);
      expect(r.voicedRatio, 0.0);
      expect(r.noiseFloorDbfs, kDigitalSilenceDbfs);
    });

    test('★ 稳态宽带噪声（电平高、但没有周期性）→ 判为没有人声', () {
      // 旧判据靠"整段能量是平的"拦它；新判据（基音）靠"没有周期性"拦它。
      // 真实负样本（空调 / 风扇 / 呼气）都是宽带、无基音，两种模型都能拦下。
      // 这里用峰值 -10dBFS 的宽带噪声：电平够高，但 70~400Hz 没有任何周期
      // → 基音闸不会把它误判成人声。
      final r = judgeSpeech(_noise(_kOneSecond, -10, 7), 16000)!;
      expect(r.peakDbfs, greaterThan(-15));
      expect(r.voicedRatio, lessThan(0.05), reason: '能量近似平的输入几乎没有"有声帧"');
      expect(r.voicedPitchRatio, 0.0, reason: '宽带噪声没有基音');
      expect(r.seemsSilent, isTrue);
    });

    test('★ 安静里的一记巨响（翻被子/开录震动）→ 判为没有人声', () {
      // 旧判据正是在这里失手的：峰值 -20 左右，闸门放过 → 模型编出一句话。
      final samples = _concat([
        _silent(_kOneSecond ~/ 2),
        _tone(2, 3000), // 只有 2 个采样是巨响
        _silent(_kOneSecond ~/ 2),
      ]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.peakDbfs, greaterThan(-25), reason: '峰值确实很高——这就是旧判据被骗的原因');
      expect(r.seemsSilent, isTrue, reason: '两声巨响不是人说话');
    });

    test('一半安静 + 一半说话 → 判为有人声', () {
      final samples = _concat([_silent(_kOneSecond ~/ 2), _vowel(_kOneSecond ~/ 2, 150, 9000)]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.seemsSilent, isFalse);
      expect(r.voicedRatio, closeTo(0.5, 0.05));
    });

    test('★ 说得再轻也一样：整体衰减 30dB，结论与占比都不变', () {
      // 这是"凌晨压着嗓子说话"那类用户的保障。判据是相对的
      // （比这段自己的噪声底高多少 dB），所以它本该与整体音量无关。
      // 哪天有人往判据里加一条抬到人声区间的绝对下限，这条会立刻红。
      final full = _concat([_silent(_kOneSecond ~/ 2), _vowel(_kOneSecond ~/ 2, 150, 9000)]);
      final quiet = _attenuate(full, -30);
      final a = judgeSpeech(full, 16000)!;
      final b = judgeSpeech(quiet, 16000)!;
      expect(b.peakDbfs, lessThan(a.peakDbfs - 25), reason: '衰减确实生效了');
      expect(b.voicedRatio, closeTo(a.voicedRatio, 0.02));
      expect(b.seemsSilent, isFalse, reason: '轻声说话绝不能被误拦');
    });

    test('★ 极轻的语音（峰值约 -58dBFS）也不被误拦', () {
      final samples = _concat([_silent(_kOneSecond ~/ 2), _vowel(_kOneSecond ~/ 2, 150, 40)]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.peakDbfs, lessThan(-55));
      expect(r.seemsSilent, isFalse, reason: '判据不能有一条落在人声区间的绝对下限');
    });

    test('帧数不够（短到估不出噪声底）→ 返回 null = 判不了', () {
      expect(judgeSpeech(Int16List(1600 - 1), 16000), isNull);
      expect(judgeSpeech(Int16List(0), 16000), isNull);
    });

    test('采样率不合法 → 返回 null，不抛异常', () {
      expect(judgeSpeech(Int16List(16000), 0), isNull);
      expect(judgeSpeech(Int16List(16000), -1), isNull);
    });

    test('尾部不足一帧的采样被丢弃，不影响结论', () {
      final samples = _concat([
        _silent(_kOneSecond ~/ 2),
        _vowel(_kOneSecond ~/ 2, 150, 8000),
        _vowel(100, 150, 8000), // 100 个采样凑不满一帧
      ]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.sampleCount, _kOneSecond + 100);
      expect(r.seemsSilent, isFalse);
    });
  });

  group('analyzePcm16Wav：能解析的都要解析对', () {
    test('纯静音 WAV：峰值 -120，时长按采样数算', () {
      final r = analyzePcm16Wav(wav16(samples: List.filled(16000, 0)))!;
      expect(r.seemsSilent, isTrue);
      expect(r.peakDbfs, kDigitalSilenceDbfs);
      expect(r.sampleRate, 16000);
      expect(r.durationSeconds, closeTo(1.0, 1e-9));
      expect(r.sampleCount, 16000);
    });

    test('★ 峰值出现在中间任何位置都**记录到**，但单靠它不足以判出人声', () {
      // 峰值仍然留着（诊断时"是不是一记冲击把这段顶出来的"一看就知道），
      // 但它不再是判据——判定看的是 20ms 帧的结构。
      final samples = List.filled(16000, 0);
      samples[5000] = 20000; // 只有一瞬间的声音
      final r = analyzePcm16Wav(wav16(samples: samples))!;
      expect(r.peakDbfs, greaterThan(-5), reason: '峰值这一项照旧要量准');
      expect(r.seemsSilent, isTrue, reason: '一声巨响不是人说话');
    });

    test('data 之前有别的块（LIST）也能跳过并正确解析', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody()),
        _chunk('LIST', List.filled(10, 7)), // 长度为奇数 → 后面带填充字节
        _chunk('data', _pcmBody(_concat([_silent(8000), _vowel(8000, 150, 9000)]))),
      ]);
      final r = analyzePcm16Wav(bytes)!;
      expect(r.seemsSilent, isFalse);
      expect(r.sampleCount, 16000);
    });

    test('data 的 size 字段没回填（写成 0）时，按文件剩余字节算', () {
      // 有些写入方收尾时来不及回填长度。这时若照 size=0 去读，
      // 会得出"0 个采样 → 静音"，把一段真实语音误判掉。
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody()),
        _rawChunkHeader('data', 0), // 长度谎报为 0
        _pcmBody(_concat([_silent(8000), _vowel(8000, 150, 12000)])),
      ]);
      final r = analyzePcm16Wav(bytes)!;
      expect(r.sampleCount, 16000);
      expect(r.seemsSilent, isFalse, reason: '不能因为对方没回填长度就判成静音');
    });

    test('44.1kHz 等别的采样率也能判（帧长按采样率折算）', () {
      final silent = analyzePcm16Wav(
        wav16(samples: List.filled(4410, 0), sampleRate: 44100),
      )!;
      expect(silent.sampleRate, 44100);
      expect(silent.seemsSilent, isTrue);

      final spoken = analyzePcm16Wav(
        wav16(
          samples: _concat([_silent(2205), _vowel(2205, 150, 9000, sampleRate: 44100)]),
          sampleRate: 44100,
        ),
      )!;
      expect(spoken.seemsSilent, isFalse);
    });

    test('双声道也能读（交错采样按同一份帧能量算）', () {
      final r = analyzePcm16Wav(
        wav16(samples: _concat([_silent(8000), _vowel(8000, 150, 20000)]), channels: 2),
      )!;
      expect(r.seemsSilent, isFalse);
    });
  });

  group('★ 判不了就必须放过（返回 null，调用方会照常送去识别）', () {
    test('不是 WAV（比如 m4a / 随机字节）', () {
      expect(analyzePcm16Wav(Uint8List.fromList(List.filled(4096, 0xAB))), isNull);
    });

    test('文件太短，连 RIFF 头都不完整', () {
      expect(analyzePcm16Wav(Uint8List.fromList('RIFF'.codeUnits)), isNull);
      expect(analyzePcm16Wav(Uint8List(0)), isNull);
    });

    test('RIFF 头对但 WAVE 标识不对', () {
      final b = wav16(samples: List.filled(10, 5000));
      b.setAll(8, 'AVI '.codeUnits);
      expect(analyzePcm16Wav(b), isNull);
    });

    test('8-bit PCM → 判不了（位深不是 16）', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody(bits: 8)),
        _chunk('data', List.filled(100, 128)),
      ]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('压缩编码（audioFormat != 1，比如 ADPCM）→ 判不了', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody(audioFormat: 17)),
        _chunk('data', _pcmBody(List.filled(100, 9000))),
      ]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('没有 fmt 块 → 判不了', () {
      final bytes = wavWithChunks([
        _chunk('data', _pcmBody(List.filled(100, 9000))),
      ]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('没有 data 块 → 判不了', () {
      final bytes = wavWithChunks([_chunk('fmt ', _fmtBody())]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('data 只有一个字节（凑不出一个采样）→ 判不了', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody()),
        _chunk('data', [0x10]),
      ]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('★ 短到估不出噪声底 → 判不了（而不是拿几帧硬判成静音）', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody()),
        _chunk('data', _pcmBody(List.filled(1000, 9000))), // 1000 采样 = 3 帧
      ]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('fmt 块被截断 → 判不了，而不是读到越界内存', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody().sublist(0, 10)),
        _chunk('data', _pcmBody(List.filled(100, 9000))),
      ]);
      expect(analyzePcm16Wav(bytes), isNull);
    });

    test('data 长度字段谎报得比文件还大 → 按实际剩余字节处理，不越界', () {
      final bytes = wavWithChunks([
        _chunk('fmt ', _fmtBody()),
        _rawChunkHeader('data', 1 << 30), // 谎报 1GB
        _pcmBody(_concat([_silent(8000), _vowel(8000, 150, 15000)])),
      ]);
      final r = analyzePcm16Wav(bytes)!;
      expect(r.sampleCount, 16000);
      expect(r.seemsSilent, isFalse);
    });
  });

  group('analyzeWavFile：读不动一律放过，绝不抛', () {
    test('文件不存在 → null', () {
      expect(analyzeWavFile('/definitely/not/here.wav'), isNull);
    });

    test('真实文件读得动时能给出结论（写一个临时静音 WAV）', () {
      final dir = Directory.systemTemp.createTempSync('dr_audio_level');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/silent.wav')
        ..writeAsBytesSync(wav16(samples: List.filled(16000, 0)));
      final r = analyzeWavFile(f.path)!;
      expect(r.seemsSilent, isTrue);
      expect(r.durationSeconds, closeTo(1.0, 1e-9));
    });

    test('真实文件里的语音不会被误拦', () {
      final dir = Directory.systemTemp.createTempSync('dr_audio_level');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/spoken.wav')
        ..writeAsBytesSync(wav16(
          samples: _concat([_silent(8000), _vowel(8000, 150, 9000)]),
        ));
      final r = analyzeWavFile(f.path)!;
      expect(r.seemsSilent, isFalse);
    });
  });

  group('0.5.10 基音闸：轻声/稀疏真语音能过，呼气/噪声照样拦死', () {
    // 关键修订（2026-10-01）：判据从「能量占比」换成「基音(浊音)占比」。
    // 浊音帧 = 低频周期信号（模拟人声元音，有基音）；噪声帧 = 宽带噪声（无基音，
    // 模拟呼气/稳态环境噪声）。基音与音量无关，于是能把"轻声的真话"和"呼气噪声"
    // 分开——而纯能量占比做不到（两者时间占比都低，0.5.9 把线提到 0.10 后把轻声
    // 真语音也误杀了，这是一次回退）。
    const int frameLen = 320; // 16kHz 下 20ms 一帧

    Int16List voiced(int frames) {
      final parts = <Int16List>[];
      for (var i = 0; i < frames; i++) {
        parts.add(_vowel(frameLen, 150, 9000));
      }
      return _concat(parts);
    }

    Int16List noise(int frames) {
      final parts = <Int16List>[];
      for (var i = 0; i < frames; i++) {
        parts.add(_noise(frameLen, -20, i + 1));
      }
      return _concat(parts);
    }

    test('★ 8% 宽带噪声（≈一次 0.4s 呼气）无基音 → 判为静音，不送识别', () {
      // 这是用户报的"不说话也识别出乱七八糟内容"的直接来源：呼气被放过，
      // 离线模型编出一句话存成了梦。噪声没有基音，浊音占比=0 → 拦死。
      final samples = _concat([noise(8), _silent(92 * frameLen)]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.voicedPitchRatio, 0.0);
      expect(r.seemsSilent, isTrue, reason: '呼气/噪声无基音，必须拦下');
    });

    test('10% 真人语音（极稀疏短句）→ 不判静音，但标 lowConfidence', () {
      // 10%（0.10）落在静音下限 0.03 之上、低置信线 0.12 之下：
      // 有基音、能过闸，但提示用户核对。
      final samples = _concat([voiced(10), _silent(90 * frameLen)]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.voicedPitchRatio, closeTo(0.10, 0.01));
      expect(r.seemsSilent, isFalse);
      expect(r.lowConfidence, isTrue, reason: '极稀疏真话仍要有基音、能过，但提示核对');
    });

    test('30% 真人语音 → 正常有人声（不标低置信）', () {
      final samples = _concat([voiced(30), _silent(70 * frameLen)]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.seemsSilent, isFalse);
      expect(r.lowConfidence, isFalse);
    });

    test('★ 关键回归：极轻的真人语音（峰值≈-58dBFS）照样不误杀', () {
      // 0.5.9 把能量闸提到 0.10，轻声软语（尤其凌晨说梦）被误判静音。
      // 基音与音量无关：放大到 -58dBFS 仍有基音 → 不误杀。
      final samples = _concat([
        _silent(_kOneSecond ~/ 2),
        _vowel(_kOneSecond ~/ 2, 150, 40), // 极轻
      ]);
      final r = judgeSpeech(samples, 16000)!;
      expect(r.peakDbfs, lessThan(-55));
      expect(r.seemsSilent, isFalse, reason: '轻声说话绝不能被误拦');
    });

    test('分档在真实 WAV 路径上同样成立（8% 噪声 → 静音）', () {
      final dir = Directory.systemTemp.createTempSync('dr_audio_level_band');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/breath.wav')
        ..writeAsBytesSync(wav16(samples: _concat([noise(8), _silent(92 * frameLen)])));
      final r = analyzeWavFile(f.path)!;
      expect(r.seemsSilent, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// 造测试波形的小工具
//
// 刻意做成"有结构"的波形（安静 + 一段有电平的声音），而不是随手填一串数：
// 判定看的就是帧能量的结构，拿平的波形去测等于什么都没测。
// ---------------------------------------------------------------------------

const int _kOneSecond = 16000;

/// 注意这三个助手都返回 [Int16List] 而不是 `List<int>`：
/// `judgeSpeech` 收的就是 `Int16List`（真正的录音路径也是从 16-bit PCM 来的），
/// 拿 `List<int>` 喂它等于测了一条应用里不存在的路径。
Int16List _silent(int n) => Int16List(n);

/// 一段恒定电平的声音（[amp] 是 16-bit 幅度）。
///
/// 它是周期信号（方波），**基音闸会把它认成"有基音"**——所以不要拿它来
/// 模拟"没有人在说话的稳态输入"（那要用 [_noise]）。它现在只适合模拟
/// "一记巨响 / 单次冲击"这种短到构不成一个完整音节的瞬态（见同名测试）。
Int16List _tone(int n, int amp) {
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = i.isEven ? amp : -amp;
  }
  return out;
}

/// 一段**有基音**的声音（默认 150Hz 方波）：模拟人声元音。
///
/// 这是"有人说话"的替身——它和 [_tone] 一样有电平、有结构，但**基音落在
/// 70~400Hz 区间里**，于是基音闸（自相关峰）能把它认成"有声音"。
/// [_tone] 是 8kHz（周期 2 采样，落在基音区间之外），只适合模拟"纯音/稳态信号"，
/// 不能当语音用——这也是 2026-10-01 把判据换成基音后，测试必须区分两者的原因。
Int16List _vowel(int n, int hz, int amp, {int sampleRate = 16000}) {
  final period = (sampleRate / hz).round();
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (i % period) < (period ~/ 2) ? amp : -amp;
  }
  return out;
}

/// 一段**宽带噪声**（无基音）：模拟呼气 / 稳态环境噪声。
///
/// 它和"说话"一样可能占据不少时间、甚至峰值不低，但**没有周期性**，
/// 于是基音闸认不出基音 → 判为没人声。这正是"呼气被拦、真话说得轻也能过"的关键。
Int16List _noise(int n, double peakDbfs, int seed) {
  final rnd = math.Random(seed);
  final amp = 32768 * math.pow(10, peakDbfs / 20);
  final out = Int16List(n);
  for (var i = 0; i < n; i++) {
    out[i] = ((rnd.nextDouble() * 2 - 1) * amp).round().clamp(-32768, 32767);
  }
  return out;
}

Int16List _concat(List<List<int>> parts) {
  final total = parts.fold<int>(0, (a, b) => a + b.length);
  final out = Int16List(total);
  var at = 0;
  for (final p in parts) {
    out.setAll(at, p);
    at += p.length;
  }
  return out;
}

/// 整体调轻（模拟"离得远 / 说得轻"）。
Int16List _attenuate(Int16List samples, double db) {
  final g = math.pow(10, db / 20).toDouble();
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = (samples[i] * g).round().clamp(-32768, 32767);
  }
  return out;
}

// ---------------------------------------------------------------------------
// 构造测试用 WAV 的小工具
// ---------------------------------------------------------------------------

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

/// fmt 块的**内容**（16 字节的经典 PCM 版）
List<int> _fmtBody({
  int audioFormat = 1,
  int channels = 1,
  int sampleRate = 16000,
  int bits = 16,
}) {
  final blockAlign = channels * bits ~/ 8;
  final byteRate = sampleRate * blockAlign;
  return [
    ..._u16(audioFormat),
    ..._u16(channels),
    ..._u32(sampleRate),
    ..._u32(byteRate),
    ..._u16(blockAlign),
    ..._u16(bits),
  ];
}

/// 把 int 采样编成 16-bit 小端字节（负数走补码）
List<int> _pcmBody(List<int> samples) {
  final out = <int>[];
  for (final s in samples) {
    out.addAll(_u16(s & 0xFFFF));
  }
  return out;
}

/// 一个完整的块：id + 长度 + 内容（奇数长度补一个填充字节）
List<int> _chunk(String id, List<int> body) => [
      ...id.codeUnits,
      ..._u32(body.length),
      ...body,
      if (body.length.isOdd) 0,
    ];

/// 只写块头、长度随手填（用于构造"长度字段不可信"的坏文件）
List<int> _rawChunkHeader(String id, int declaredSize) => [
      ...id.codeUnits,
      ..._u32(declaredSize),
    ];

/// 拼一个标准 WAV
Uint8List wavWithChunks(List<List<int>> chunks) {
  final body = <int>[];
  for (final c in chunks) {
    body.addAll(c);
  }
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._u32(4 + body.length),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
}

/// 最常用的形式：16-bit PCM 单/双声道
Uint8List wav16({
  required List<int> samples,
  int sampleRate = 16000,
  int channels = 1,
}) =>
    wavWithChunks([
      _chunk('fmt ', _fmtBody(channels: channels, sampleRate: sampleRate)),
      _chunk('data', _pcmBody(samples)),
    ]);

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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

import '../l10n/messages.dart';
import 'app_dirs.dart';

/// 录音产出的格式。
///
/// 为什么要有两种：离线识别（sherpa-onnx）**只吃 WAV/PCM**，喂 m4a 给它
/// 是解不出波形的；而"只想留一份回听"的场景下，WAV 又太占地方
/// （16kHz 单声道约 32KB/秒，三分钟就 5.7MB，m4a 只有它的四分之一）。
/// 所以格式由调用方按用途选，不在这里替它猜。
enum AudioCaptureFormat {
  /// AAC-LC / m4a：体积小，只用于"留一份回听"
  m4a,

  /// 16kHz 单声道 PCM / wav：识别用，零解码依赖
  wav16k;

  String get extension => this == AudioCaptureFormat.wav16k ? 'wav' : 'm4a';

  /// 给用户看的说明（跟随当前界面语言）
  String get note => this == AudioCaptureFormat.wav16k
      ? AppL10n.current.tr('audio_format_wav_note')
      : AppL10n.current.tr('audio_format_m4a_note');
}

/// 录音服务：按住说话期间录音，松开后落盘。
/// 音频只存本机（web 端不落盘，仅会话内可用）——隐私架构要求音频不上云。
abstract class RecorderService {
  Future<void> start(String id, {AudioCaptureFormat format});

  /// 返回音频路径；web 端返回 null（浏览器不提供持久文件路径）
  Future<String?> stop();

  Future<void> dispose();
}

class RealRecorderService implements RecorderService {
  final AudioRecorder _rec = AudioRecorder();

  @override
  Future<void> start(
    String id, {
    AudioCaptureFormat format = AudioCaptureFormat.m4a,
  }) async {
    if (await _rec.hasPermission() != true) {
      throw StateError(AppL10n.current.tr('err_recorder_permission'));
    }
    if (kIsWeb) {
      await _rec.start(const RecordConfig(encoder: AudioEncoder.opus), path: '');
      return;
    }
    final path = '${(await appAudioDir()).path}/$id.${format.extension}';
    switch (format) {
      case AudioCaptureFormat.m4a:
        await _rec.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
          path: path,
        );
      case AudioCaptureFormat.wav16k:
        // 采样率必须是 16000、单声道：Paraformer 就是按 16k 训练的，
        // 交给 sherpa-onnx 的是 8k 或双声道虽然也能跑，但要多一次重采样，
        // 而且手机上重采样是最容易出杂音的一步——干脆在采集端就对齐。
        //
        // 0.4.4 起另外两个开关是**为"凌晨压着嗓子说话"开的**。用户反馈
        // "说话声音也不大"，而这一路的默认值一个增益都不带：
        //
        // - `autoGain`：默认 false。打开后走 Android 的 AutomaticGainControl，
        //   小声说话也能录到足够电平。（插件会先查 `isAvailable()`，
        //   机型不支持时静默跳过，不会因此起不来。）
        // - `audioSource`：默认是 `MediaRecorder.AudioSource.DEFAULT`，
        //   走的是普通录音链路。Android 专门为"喂给识别引擎"准备的音源是
        //   `VOICE_RECOGNITION`，它带厂商调过的增益链路，正是这一路的用途。
        //
        // **`noiseSuppress` 刻意保持关**。它会把安静时的小声音一起吃掉——
        // 而"安静时的小声音"恰恰是本应用唯一在意的输入。降噪换来的干净底噪
        // 对判据没什么用（判据本来就是相对的，看的是比这段自己的噪声底高多少），
        // 但被吃掉的轻声是拿不回来的。
        await _rec.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            autoGain: true,
            androidConfig: AndroidRecordConfig(
              audioSource: AndroidAudioSource.voiceRecognition,
            ),
          ),
          path: path,
        );
    }
  }

  @override
  Future<String?> stop() async {
    final path = await _rec.stop();
    return kIsWeb ? null : path;
  }

  @override
  Future<void> dispose() async => _rec.dispose();
}

/// 测试/无麦克风环境使用
class FakeRecorderService implements RecorderService {
  bool started = false;
  AudioCaptureFormat? lastFormat;

  /// 可以让测试指定"录出来的文件"在哪
  String fakePath = '/fake/audio.m4a';

  @override
  Future<void> start(
    String id, {
    AudioCaptureFormat format = AudioCaptureFormat.m4a,
  }) async {
    started = true;
    lastFormat = format;
  }

  @override
  Future<String?> stop() async {
    started = false;
    return fakePath;
  }

  @override
  Future<void> dispose() async {}
}

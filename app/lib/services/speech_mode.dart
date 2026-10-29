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

// 转写方式的选择与「差别说明」。
//
// 这个文件刻意**不依赖 Flutter**，因为里面绝大部分是给用户看的文字，
// 而文字最容易在改动里悄悄失真（比如某天有人把「音频不出设备」改成通用话术，
// 而云端那条其实会上传）。把文案放这里、用 `dart test` 钉住关键事实，
// 才能在重构时守住隐私承诺。
//
// 背景：三条路子的取舍差别非常大，没有一条能在所有设备上既好用又免费又私密。
// 所以这里的立场是**让用户自己选，并把代价写在明处**，而不是替用户默认一个
// 然后在他失败时才发现。
//
// 文案本身搬去了 `lib/l10n/messages.dart`（三语），这里只保留**结构**：
// 维度顺序、id、以及「谁占麦克风 / 音频去哪」这些 Bool。这样纯 Dart 测试仍能
// 钉住关键事实（见 `test/speech_modes_test.dart`），界面又能跟着语言切换。
import '../l10n/messages.dart';

/// 一条「维度 → 取值」的说明。用 list 而不是散字段，
/// 是为了让设置页能原样铺成一张小对照表，避免文案在多处重复。
class SpeechFact {
  const SpeechFact(this.label, this.value);

  /// 维度名，如「音频去向」
  final String label;

  /// 该维度下这个方式的实际取值
  final String value;
}

/// 转写方式。
enum SpeechMode {
  /// 系统语音识别（Android SpeechRecognizer / iOS Speech / Web Speech）。
  ///
  /// 体验最好（边说边出字）、零占用，但**能不能用取决于设备**：
  /// Android 的识别服务在国内基本只有 Google 语音服务实现，华为这类
  /// 没有 GMS 的机型就没有可用的识别服务。
  system(id: 'system'),

  /// 端侧离线识别（sherpa-onnx + Paraformer 中文大模型，按需下载）。
  ///
  /// 唯一一条**任何设备都能用、且音频绝不出设备**的路。
  /// 代价是首次使用要联网下载模型（约 243MB，0.6.0 起不预装进安装包），
  /// 且不是边说边出字。
  offline(id: 'offline'),

  /// 云端转写（BYOK，用户自带服务商的 Key）。
  ///
  /// 准确率最高、支持长音频，但**音频会离开设备**——这一条必须在界面上说清楚，
  /// 不能藏在隐私政策的角落里。
  cloud(id: 'cloud');

  const SpeechMode({required this.id});

  /// 落盘用的稳定标识——**不要改**，改了老用户的设置会丢。
  final String id;

  /// 对照表的维度顺序。**必须与三语文案表里的 key 一一对应**，
  /// 且顺序就是界面上的呈现顺序（先问出字、再问隐私、最后问成本与前提）。
  static const List<String> _dims = ['timing', 'audio', 'network', 'cost', 'prereq'];

  /// 设置页里的名字（跟随当前界面语言）
  String get label => AppL10n.current.tr('speech_${id}_label');

  /// 一句话概括（跟随当前界面语言）
  String get tagline => AppL10n.current.tr('speech_${id}_tagline');

  /// 逐维度对照（跟随当前界面语言；固定 5 项，顺序见 [_dims]）
  List<SpeechFact> get facts => [
        for (final d in _dims)
          SpeechFact(
            AppL10n.current.tr('speech_dim_$d'),
            AppL10n.current.tr('speech_${id}_$d'),
          ),
      ];

  /// 这条路的代价 / 最容易踩的坑（跟随当前界面语言）
  String get caveat => AppL10n.current.tr('speech_${id}_caveat');

  /// 是否需要 App 自己先录下一整段音频。
  ///
  /// true 的路子（离线 / 云端）走「先录 WAV，松手后再识别」；
  /// false 的路子（系统识别）由识别服务自己开麦克风，见 transcriber.dart
  /// 里关于麦克风独占性的说明。
  bool get needsRecording => this != SpeechMode.system;

  /// 音频是否会离开这台设备。设置页据此显示提醒——这是隐私承诺的核心事实。
  bool get audioLeavesDevice => this == SpeechMode.cloud;

  /// 是否依赖外部网络才能工作
  bool get needsNetwork => this == SpeechMode.cloud;

  static const SpeechMode fallback = SpeechMode.offline;

  /// 从落盘的 id 还原。认不出来就回到默认值——**不能抛异常**，
  /// 否则用户换了版本、老设置读不出来，App 会直接起不来。
  static SpeechMode fromId(String? id) {
    for (final m in SpeechMode.values) {
      if (m.id == id) return m;
    }
    return fallback;
  }
}

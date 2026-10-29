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

/// 录音文件的**占用统计与清理**。
///
/// 为什么值得单独一层：从 0.3.3 起「识别完保留录音」默认打开（离线/云端模式下
/// 音频本来就要录，保留它只是留存策略，没有额外代价）。于是磁盘上会长期躺着
/// 一堆 16kHz WAV（**32KB/秒 ≈ 1.9MB/分钟**，每天一条梦约 60~115MB/月），
/// 必须有人负责回答三个问题：占了多少、哪些是没用的、删的时候要连带做什么。
///
/// 本文件**只 import `dart:io`**（不碰 Flutter / path_provider），
/// 所以能用 `dart test` 直接跑真实文件系统。目录从哪来由调用方给
/// （见 `app_dirs.dart`），这样测试能塞临时目录。
///
/// `library;` 必须写在 import **之前**——它声明的是本文件的库级文档，
/// 放在 import 后面会被判成 `library_directive_not_first` 编译错误。
library;

import 'dart:io';

/// 超过这个占用就在界面上提醒清理。
///
/// 500MB ≈ 260 分钟的录音 ≈ 每天一条、每条两分钟的话，约 4 个月。
/// 选这个量级是**故意不敏感**：提醒本身是噪音，一年响一两次才有人看；
/// 而且本项目**绝不自动删任何东西**——音频是用户的原话，删掉就拿不回来了，
/// 清不清只能由用户点确认。
const int kAudioWarnBytes = 500 * 1024 * 1024;

/// 只认这几种后缀。WAV 是本项目识别用的格式；m4a/aac/opus 是"同时录一份"
/// 或将来压缩留存的格式——留着口子，免得改格式时这里的白名单把人绊一跤。
const List<String> kAudioExtensions = ['.wav', '.m4a', '.aac', '.opus'];

/// 刚写没多久的文件不算"无主"。
///
/// 必须要有这一条：正在录、或刚录完还没存成记录的那段音频，**还没有任何记录
/// 引用它**，按"没被引用就是垃圾"去清会直接把用户正在说的话删掉。
const Duration kAudioFreshWindow = Duration(minutes: 10);

/// 录音占用的快照。
class AudioUsage {
  const AudioUsage({
    required this.fileCount,
    required this.totalBytes,
    required this.orphanCount,
    required this.orphanBytes,
  });

  static const empty =
      AudioUsage(fileCount: 0, totalBytes: 0, orphanCount: 0, orphanBytes: 0);

  final int fileCount;
  final int totalBytes;

  /// 没有任何记录引用的文件（记录被删了、录完没存成记录、上次崩在半路…）。
  final int orphanCount;
  final int orphanBytes;

  bool get isEmpty => fileCount == 0;
  bool get hasOrphans => orphanCount > 0;
  bool get overWarnLine => totalBytes >= kAudioWarnBytes;

  /// 距提醒线的进度（0~1，超过 1 也按 1 算），给进度条用。
  double get warnRatio =>
      (totalBytes / kAudioWarnBytes).clamp(0.0, 1.0).toDouble();

  String get humanTotal => formatBytes(totalBytes);
  String get humanOrphans => formatBytes(orphanBytes);
}

/// 统计 [dir] 里的录音占用。
///
/// [referenced] 是所有记录里存着的音频路径集合（`entry.audioPath` 的并集）。
/// 不在里面、且不是最近刚写过的文件，视为**无主**。
AudioUsage measureAudioUsage(
  Directory dir, {
  required Set<String> referenced,
  Duration freshWindow = kAudioFreshWindow,
  DateTime? now,
}) {
  if (!dir.existsSync()) return AudioUsage.empty;
  final nowTime = now ?? DateTime.now();

  var count = 0;
  var bytes = 0;
  var orphanCount = 0;
  var orphanBytes = 0;

  for (final f in _audioFiles(dir)) {
    final len = f.lengthSync();
    count++;
    bytes += len;
    if (referenced.contains(f.path)) continue;
    // 够"新"就不算无主：它可能是正在录的那一段
    if (nowTime.difference(f.statSync().modified) < freshWindow) continue;
    orphanCount++;
    orphanBytes += len;
  }

  return AudioUsage(
    fileCount: count,
    totalBytes: bytes,
    orphanCount: orphanCount,
    orphanBytes: orphanBytes,
  );
}

/// 列出无主音频的路径（清理前要能告诉用户"将要删掉哪些、多少"）。
List<String> listOrphanAudio(
  Directory dir, {
  required Set<String> referenced,
  Duration freshWindow = kAudioFreshWindow,
  DateTime? now,
}) {
  if (!dir.existsSync()) return const [];
  final nowTime = now ?? DateTime.now();
  final out = <String>[];
  for (final f in _audioFiles(dir)) {
    if (referenced.contains(f.path)) continue;
    if (nowTime.difference(f.statSync().modified) < freshWindow) continue;
    out.add(f.path);
  }
  return out;
}

/// 删一个音频文件。返回是否真的删掉了。
///
/// **失败不抛异常**：删音频是清理动作，不该因为一个删不掉的坏文件
/// 把"删记录"这种主流程带崩（`deleteEntry` 会连带调它）。
Future<bool> deleteAudioFile(String? path) async {
  if (path == null || path.isEmpty) return false;
  try {
    final f = File(path);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// 列出目录里**全部**音频文件（不做无主判定）。"删掉全部录音"用它。
Future<List<String>> listAudioFiles(Directory dir) async {
  if (!dir.existsSync()) return const [];
  return _audioFiles(dir).map((f) => f.path).toList();
}

/// 按路径批量删除，返回成功删掉的个数。
Future<int> deleteAudioFiles(Iterable<String> paths) async {
  var n = 0;
  for (final p in paths) {
    if (await deleteAudioFile(p)) n++;
  }
  return n;
}

/// 清掉无主文件，返回成功删掉的个数。
///
/// [now] 与 [listOrphanAudio] 的同名参数是一回事，但这里更关键：它同时决定了
/// "哪些算无主"和"实际删哪些"，两者必须用**同一个**时间点。
/// 少了它，调用方就没法在测试里固定时间，而新鲜窗口的判据依赖绝对时间 ——
/// 用 `DateTime.now()` 的版本会因为跑测试的时刻不同而忽删忽不删（真踩过）。
Future<int> purgeOrphanAudio(
  Directory dir, {
  required Set<String> referenced,
  Duration freshWindow = kAudioFreshWindow,
  DateTime? now,
}) =>
    deleteAudioFiles(
      listOrphanAudio(
        dir,
        referenced: referenced,
        freshWindow: freshWindow,
        now: now,
      ),
    );

/// 人类可读的体积。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const kb = 1024.0;
  if (bytes < kb * kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  if (bytes < kb * kb * kb) return '${(bytes / (kb * kb)).toStringAsFixed(1)} MB';
  return '${(bytes / (kb * kb * kb)).toStringAsFixed(2)} GB';
}

Iterable<File> _audioFiles(Directory dir) {
  try {
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => kAudioExtensions.any((e) => f.path.toLowerCase().endsWith(e)));
  } catch (_) {
    // 目录读不动（权限/被删）时当作没有音频，而不是让界面崩
    return const <File>[];
  }
}

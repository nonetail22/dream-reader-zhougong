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

/// 离线识别模型（paraformer-zh-large）的元数据、完整性校验与按需下载。
///
/// ## 0.6.0 为什么改成「按需下载」
///
/// 识别模型从 78MB 的小模型换成了 243MB 的大模型（Mac 实验与用户真机反馈：
/// 小模型整段解码长音频中段崩坏，大模型无此病且明显更稳，见
/// `audio_chunker.dart` 头注与 2026-10-27 日志）。243MB 再预装会让 APK 破
/// 300MB，所以改为：**安装包不带模型**，用户选择离线识别时弹窗确认、联网
/// 下载一次，之后识别全程离线。
///
/// 下载源是 hf-mirror（国内可达，2026-10-27 实测）。完整性用「期望字节数 +
/// sha256」双重校验：只看"文件存在"会把半截文件当成好的（0.4.x 时代踩过的
/// 坑），下载中途被杀、CDN 截断都必须挡在门外。
///
/// ## 0.7.0 追加标点模型
///
/// Paraformer 原始输出没有标点（用户反馈"识别准确了但没标点"），追加
/// CT-Transformer 标点模型（int8 约 75MB）进同一份下载清单——老用户升级后
/// `isModelInstalledIn` 会判缺文件，走同一条引导把缺的那份补下即可（已存在
/// 的文件按字节跳过，不会重下 243MB）。
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// 模型里单个文件的规格：叫什么、该多大、指纹是什么、从哪儿下。
class OfflineModelFileSpec {
  const OfflineModelFileSpec({
    required this.fileName,
    required this.expectedBytes,
    required this.sha256,
    required this.urls,
  });

  final String fileName;

  /// 期望的确切字节数。少了 = 截断，多了 = 拿错文件，都不能用。
  final int expectedBytes;

  /// 文件内容的 sha256（十六进制小写）。下载完必须对上，对不上删掉重来。
  final String sha256;

  /// 依次尝试的下载地址。第一个不可达/报错时落到下一个。
  final List<String> urls;
}

/// 模型总规格。目录名同时是模型标识——换模型时连 sha256 一起换。
class OfflineModelSpec {
  const OfflineModelSpec._();

  static const String dirName = 'paraformer-zh-large';
  static const String modelFile = 'model.int8.onnx';
  static const String tokensFile = 'tokens.txt';

  /// 标点模型（0.7.0 起随识别模型一起下载）：CT-Transformer 中英标点，
  /// int8 量化版约 75MB。Paraformer 原始输出**没有标点**，识别结果可读性差；
  /// 标点模型在 Mac 上实测每段 5~10ms，成本可忽略。
  static const String punctFile = 'punct_model.int8.onnx';

  static const int modelBytes = 243371218;
  static const int tokensBytes = 75756;

  /// int8 标点模型的字节数与 sha256（2026-10-27 从两个独立镜像各下一份、
  /// 哈希一致后钉死：ranger810 / lorneluo，均为同一文件的转载）。
  static const int punctBytes = 75519198;

  /// 展示用体积。i18n 文案不要从这里拼（走 messages 的 `offline_model_size`）。
  /// 243 + 0.07 + 75 ≈ 319MB，文案按 320MB 口径。
  static const String approxSize = '320MB';

  /// sha256 取自 2026-10-27 实际下载并跑通识别的副本（hf-mirror；sherpa 加载
  /// 成功 + 56s 长音频全对），以此为准。上游重新发模型时这两个数会变。
  static const List<OfflineModelFileSpec> files = [
    OfflineModelFileSpec(
      fileName: modelFile,
      expectedBytes: modelBytes,
      sha256:
          'f36a0433bcf096bd6d6f11b80a3ac8bed110bdca632fe0d731df8d1a84475945',
      urls: [
        'https://hf-mirror.com/csukuangfj/sherpa-onnx-paraformer-zh-2023-09-14/resolve/main/model.int8.onnx',
        'https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-2023-09-14/resolve/main/model.int8.onnx',
      ],
    ),
    OfflineModelFileSpec(
      fileName: tokensFile,
      expectedBytes: tokensBytes,
      sha256:
          '59aba8873a2ed1e122c25fee421e25f283b63290efbde85c1f01a853d83cb6e6',
      urls: [
        'https://hf-mirror.com/csukuangfj/sherpa-onnx-paraformer-zh-2023-09-14/resolve/main/tokens.txt',
        'https://huggingface.co/csukuangfj/sherpa-onnx-paraformer-zh-2023-09-14/resolve/main/tokens.txt',
      ],
    ),
    OfflineModelFileSpec(
      fileName: punctFile,
      expectedBytes: punctBytes,
      sha256:
          '65a3fb9f5ad7bfb96bf69e0dc4481df97f6ee60513c1d94ce981ba6effd524b1',
      urls: [
        'https://hf-mirror.com/ranger810/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8/resolve/main/model.int8.onnx',
        'https://hf-mirror.com/lorneluo/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8/resolve/main/model.int8.onnx',
      ],
    ),
  ];
}

/// 模型是否已经下载完整。
///
/// 判定用**期望字节数**（快速路径，打开设置页时也要调，不能每次都算 243MB
/// 的哈希）；sha256 在下载完成后当场校验过，之后文件只被读取不会变。
/// 文件被外部动过的极端情况由 sherpa 加载失败兜底报错。
///
/// [files] 供测试注入小规格（否则每个测试都要扛 243MB 的假想文件）。
bool isModelInstalledIn(
  Directory dir, {
  List<OfflineModelFileSpec> files = OfflineModelSpec.files,
}) {
  for (final f in files) {
    final file = File('${dir.path}/${f.fileName}');
    try {
      if (!file.existsSync() || file.lengthSync() != f.expectedBytes) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }
  return true;
}

/// 用户主动取消下载时抛出。界面捕获后给一句「已取消」，别当失败处理。
class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();

  @override
  String toString() => 'ModelDownloadCancelled';
}

/// 下载全部模型文件到 [dir]。已完整存在的文件跳过。
///
/// - 先写 `*.part`，字节数 + sha256 双重校验通过后才改名转正——
///   下到一半被杀不会留下一个"看起来能用"的坏文件；
/// - [onProgress] 收 `(已收字节, 总字节)`，按当前文件计；
/// - [isCancelled] 返回 true 时尽快停止并抛 [ModelDownloadCancelled]；
/// - [clientFactory] 供测试注入（默认新建 [HttpClient]）。
Future<void> downloadOfflineModel(
  Directory dir, {
  List<OfflineModelFileSpec> files = OfflineModelSpec.files,
  void Function(int received, int total)? onProgress,
  bool Function()? isCancelled,
  HttpClient Function()? clientFactory,
}) async {
  if (!await dir.exists()) await dir.create(recursive: true);
  for (final spec in files) {
    final dest = File('${dir.path}/${spec.fileName}');
    if (await dest.exists() && await dest.length() == spec.expectedBytes) {
      continue;
    }
    await _downloadOne(
      spec,
      dest,
      onProgress: onProgress,
      isCancelled: isCancelled,
      clientFactory: clientFactory,
    );
  }
}

Future<void> _downloadOne(
  OfflineModelFileSpec spec,
  File dest, {
  void Function(int received, int total)? onProgress,
  bool Function()? isCancelled,
  HttpClient Function()? clientFactory,
}) async {
  final part = File('${dest.path}.part');
  Object? lastError;
  for (final url in spec.urls) {
    if (isCancelled?.call() ?? false) throw const ModelDownloadCancelled();
    try {
      final client = clientFactory?.call() ?? HttpClient();
      try {
        client.connectionTimeout = const Duration(seconds: 20);
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}（$url）';
          continue;
        }
        // 服务器没给长度时退回期望值，进度条至少不会除零
        final total =
            response.contentLength > 0 ? response.contentLength : spec.expectedBytes;
        final sink = part.openWrite();
        var received = 0;
        try {
          await for (final chunk in response) {
            if (isCancelled?.call() ?? false) {
              throw const ModelDownloadCancelled();
            }
            sink.add(chunk); // add() 是同步入队（void），不是 Future
            received += chunk.length;
            onProgress?.call(received, total);
          }
          await sink.flush();
          sink.close(); // IOSink.close() 返回 void，不是 Future
        } catch (_) {
          try {
            sink.close();
          } catch (_) {}
          rethrow;
        }

        // 双重校验，过了才准转正。
        final actual = await part.length();
        if (actual != spec.expectedBytes) {
          lastError = '字节数不符（$actual / ${spec.expectedBytes}）';
          continue;
        }
        final digest = await _sha256Of(part);
        if (digest != spec.sha256) {
          lastError = 'sha256 校验不符（$url）';
          continue;
        }
        await part.rename(dest.path);
        return;
      } finally {
        client.close(force: true);
      }
    } on ModelDownloadCancelled {
      await _deleteQuietly(part);
      rethrow;
    } catch (e) {
      lastError = e;
      await _deleteQuietly(part);
    }
  }
  await _deleteQuietly(part);
  throw StateError('模型下载失败（$lastError）');
}

Future<String> _sha256Of(File f) async {
  final digest = await crypto.sha256.bind(f.openRead()).first;
  return digest.toString();
}

Future<void> _deleteQuietly(File f) async {
  try {
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 删不掉就留着（下次 openWrite 会截断重写），不阻塞主流程
  }
}

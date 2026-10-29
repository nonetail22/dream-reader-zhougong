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
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dream_reader/services/offline_model.dart';
import 'package:test/test.dart';

/// 模型按需下载的端到端测试：起一个**真实的本地 HTTP 服务器**当下载源，
/// 用小规格（几 KB）代替 243MB 的真模型，钉住下载器的四条硬性质：
/// 校验通过才转正、指纹不符不落盘、可取消、坏源能落到备用源。
void main() {
  late HttpServer server;
  late Directory dir;
  late Uri base;

  // 一段几 KB 的"模型"内容（内容本身无所谓，关键是 sha256 一致性）
  final payload = Uint8List.fromList(
    List.generate(8192, (i) => (i * 31 + 7) % 256),
  );
  final payloadSha = crypto.sha256.convert(payload).toString();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dr_offline_model');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/good/m.bin') {
        req.response.add(payload);
        await req.response.close();
      } else if (path == '/bad/m.bin') {
        // 同样大小、内容不对（模拟 CDN 截断/篡改）
        req.response.add(Uint8List.fromList(List.filled(payload.length, 1)));
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  OfflineModelFileSpec spec({required List<String> urls}) =>
      OfflineModelFileSpec(
        fileName: 'm.bin',
        expectedBytes: payload.length,
        sha256: payloadSha,
        urls: urls,
      );

  test('正常下载：字节数 + sha256 通过后转正，isModelInstalledIn 判就绪', () async {
    await downloadOfflineModel(
      dir,
      files: [spec(urls: ['$base/good/m.bin'])],
    );
    final f = File('${dir.path}/m.bin');
    expect(await f.exists(), isTrue);
    expect(await f.length(), payload.length);
    expect(await f.readAsBytes(), payload);
    expect(isModelInstalledIn(dir, files: [spec(urls: [])]), isTrue);
    // .part 临时文件不应残留
    expect(File('${dir.path}/m.bin.part').existsSync(), isFalse);
  });

  test('sha256 不符：不落盘、抛错、.part 清掉', () async {
    await expectLater(
      downloadOfflineModel(
        dir,
        files: [spec(urls: ['$base/bad/m.bin'])],
      ),
      throwsA(isA<StateError>()),
    );
    expect(File('${dir.path}/m.bin').existsSync(), isFalse);
    expect(File('${dir.path}/m.bin.part').existsSync(), isFalse);
  });

  test('立即取消：抛 ModelDownloadCancelled，不落盘', () async {
    await expectLater(
      downloadOfflineModel(
        dir,
        files: [spec(urls: ['$base/good/m.bin'])],
        isCancelled: () => true,
      ),
      throwsA(isA<ModelDownloadCancelled>()),
    );
    expect(File('${dir.path}/m.bin').existsSync(), isFalse);
  });

  test('第一个源 404 → 落到第二个源成功', () async {
    await downloadOfflineModel(
      dir,
      files: [spec(urls: ['$base/missing/m.bin', '$base/good/m.bin'])],
    );
    expect(File('${dir.path}/m.bin').existsSync(), isTrue);
  });

  test('已完整存在的文件跳过（不再请求网络）', () async {
    final f = File('${dir.path}/m.bin')..writeAsBytesSync(payload);
    await downloadOfflineModel(
      dir,
      files: [spec(urls: ['$base/missing/m.bin'])], // 若请求了会 404 抛错
    );
    expect(await f.length(), payload.length);
  });

  test('进度回调单调不减，最终到达总字节数', () async {
    var last = 0;
    await downloadOfflineModel(
      dir,
      files: [spec(urls: ['$base/good/m.bin'])],
      onProgress: (received, total) {
        expect(total, payload.length);
        expect(received, greaterThanOrEqualTo(last));
        last = received;
      },
    );
    expect(last, payload.length);
  });
}

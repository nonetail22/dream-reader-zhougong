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

// 离线识别 **worker isolate** 冒烟测试（纯 Dart，Mac 端跑）。
//
// 0.7.1 把整条识别管线（读波形/分段/解码/标点）搬进了后台 isolate
// （`lib/services/offline_asr_worker.dart`），理由：管线是同步大块头，
// 跑在 UI isolate 上会把界面冻住（用户真机反馈"点重新识别后卡住，
// 百分比只闪一下"）。isolate 里跑 FFI 是否真的可行、协议是否通、
// 进度事件是否按序到达、结果是否与直跑一致——只有真跑才知道。
//
// 注意：ReceivePort 的流**只能 listen 一次**（第二次 listen 会抛
// "Stream has already been listened to"），所以这里与 app 的 _Runtime
// 同款：单监听 + 当前请求路由，而不是每个请求挂一次监听。
//
// 跑法：
//   ./tool/f.sh dart run tool/offline_worker_smoke.dart \
//     assets/models/paraformer-zh-large <wav...>
// 不传 wav 时默认跑 ../validation/asr_samples 下全部样本。
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dream_reader/services/offline_asr_worker.dart';

Future<void> main(List<String> args) async {
  final modelDir = args.isNotEmpty
      ? args[0]
      : 'assets/models/paraformer-zh-large';
  final wavs = args.length > 1
      ? args.sublist(1)
      : Directory('../validation/asr_samples')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.wav'))
          .toList()
        ..sort();

  final handshake = ReceivePort();
  final isolate = await Isolate.spawn(offlineAsrWorkerMain, handshake.sendPort);
  final spawned = await handshake.first as Map;
  handshake.close();
  final workerPort = spawned['port'] as SendPort;
  stdout.writeln('== worker 已启动 ==');

  final replies = ReceivePort();
  // 单监听路由：当前请求的终结事件通过 completer 交付，中间事件直接打印。
  Completer<Map>? pending;
  void Function(Map event)? onEvent;
  replies.listen((m) {
    m as Map;
    switch (m['event']) {
      case 'phase':
      case 'progress':
        final ms = m['ms'];
        stdout.writeln(
            '   [${m['phase'] ?? '${m['pct']}%'}]${ms != null ? ' ${ms}ms' : ''}');
        onEvent?.call(m);
      case 'released':
        onEvent?.call(m);
      default:
        final c = pending;
        pending = null;
        onEvent = null;
        c?.complete(m);
    }
  });

  Future<Map> request(Map<String, Object?> msg) {
    final c = Completer<Map>();
    pending = c;
    workerPort.send({...msg, 'reply': replies.sendPort});
    return c.future;
  }

  var ok = 0;
  var fail = 0;
  for (final wav in wavs) {
    stdout.writeln('\n${wav.split(Platform.pathSeparator).last}');
    final result = await request({
      'cmd': 'transcribe',
      'dir': modelDir,
      'path': wav,
      'threads': 2,
    }).timeout(const Duration(minutes: 5));
    if (result['event'] == 'done') {
      stdout.writeln('   → ${result['text']}');
      stdout.writeln('   (${result['log']})');
      ok++;
    } else {
      stdout.writeln('   !! 失败: $result');
      fail++;
    }
  }

  // 闲置释放协议验证
  final released = Completer<void>();
  onEvent = (m) {
    if (m['event'] == 'released') {
      released.complete();
      onEvent = null;
    }
  };
  request({'cmd': 'release'});
  await released.future.timeout(const Duration(seconds: 10));
  stdout.writeln('\n== release 协议 OK ==');

  isolate.kill(priority: Isolate.immediate);
  replies.close();
  stdout.writeln('== 结果：$ok 成功 / $fail 失败 ==');
  exitCode = fail == 0 ? 0 : 1;
}

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

import 'package:dream_reader/services/audio_store.dart';
import 'package:test/test.dart';

/// 录音占用统计与清理的纯逻辑测试。
///
/// 这一层值得认真测，是因为它有两个**不能靠直觉**的判据：
/// 1. "没有记录引用"不等于垃圾 —— 正在录、或刚录完还没存成记录的那段音频同样
///    符合"没有记录引用"，按它去清会直接把用户正在说的话删掉（所以有 10 分钟
///    新鲜窗口）；
/// 2. 删音频是**不可逆**动作，删的是用户自己的声音。每个删除入口都得先被证明
///    "只动该动的文件" —— 这类 bug 在界面上完全看不出来（记录照常显示，
///    只是回听时文件没了），只能靠测试挡。
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dream_reader_audio_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 造一个指定字节数的假音频。
  ///
  /// 用 `writeAsBytesSync` 而不是 `truncate`：这里要的是**真实长度**参与求和，
  /// 稀疏文件在 APFS 上 lengthSync() 也正确，但换到别的文件系统上就未必。
  /// 测试体积都很小（几十字节），不值得为省这点空间引入平台差异。
  File makeAudio(String name, int bytes, {DateTime? modified}) {
    final f = File('${dir.path}/$name');
    f.writeAsBytesSync(List<int>.filled(bytes, 0));
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  /// 固定的"现在"。用固定值而不是 `DateTime.now()`，是为了让新鲜窗口的边界
  /// 判断可复现 —— 靠 now() 的版本会随机抖动，失败时还查不出原因。
  final now = DateTime(2026, 9, 21, 14, 0);
  final old = now.subtract(const Duration(days: 1));

  group('measureAudioUsage · 总量', () {
    test('目录不存在时返回空占用，不抛异常', () {
      final missing = Directory('${dir.path}/nope');
      final u = measureAudioUsage(missing, referenced: const {}, now: now);
      expect(u.isEmpty, isTrue);
      expect(u.totalBytes, 0);
      expect(u.hasOrphans, isFalse);
    });

    test('空目录 → 空占用', () {
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.fileCount, 0);
      expect(u.totalBytes, 0);
    });

    test('多个文件的体积是逐个相加', () {
      makeAudio('a.wav', 1000, modified: old);
      makeAudio('b.wav', 2500, modified: old);
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.fileCount, 2);
      expect(u.totalBytes, 3500);
    });

    test('非音频文件完全不参与统计', () {
      makeAudio('a.wav', 100, modified: old);
      File('${dir.path}/notes.txt').writeAsStringSync('x' * 5000);
      File('${dir.path}/20260921-1400.json').writeAsStringSync('{}');
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.fileCount, 1);
      expect(u.totalBytes, 100);
    });

    test('后缀大小写都认，m4a/aac/opus 也在白名单里', () {
      makeAudio('A.WAV', 10, modified: old);
      makeAudio('b.M4a', 10, modified: old);
      makeAudio('c.aac', 10, modified: old);
      makeAudio('d.opus', 10, modified: old);
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.fileCount, 4);
      expect(u.totalBytes, 40);
    });
  });

  group('measureAudioUsage · 无主判定', () {
    test('被记录引用的音频只计入总量，不算无主', () {
      final a = makeAudio('a.wav', 100, modified: old);
      final u = measureAudioUsage(dir, referenced: {a.path}, now: now);
      expect(u.fileCount, 1);
      expect(u.totalBytes, 100);
      expect(u.orphanCount, 0);
      expect(u.orphanBytes, 0);
    });

    test('没被引用的旧音频算无主', () {
      makeAudio('a.wav', 100, modified: old);
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.fileCount, 1);
      expect(u.orphanCount, 1);
      expect(u.orphanBytes, 100);
      expect(u.hasOrphans, isTrue);
    });

    test('★ 刚写过的无主音频**不算**无主 —— 它可能是正在录的那一段', () {
      // 整个文件里最要紧的一条：少了新鲜窗口，"清理无主录音"会删掉用户正在说的话。
      makeAudio('rec.wav', 100, modified: now.subtract(const Duration(minutes: 1)));
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.fileCount, 1, reason: '仍然计入占用（它确实占了地方）');
      expect(u.orphanCount, 0, reason: '但不该被判成垃圾');
      expect(u.hasOrphans, isFalse);
    });

    test('新鲜窗口的边界：10 分钟内不算无主，超过才算', () {
      // 取 9:30 / 10:30 而不是卡在 10:00 整：setLastModifiedSync 在部分文件系统上
      // 只有秒级（甚至更粗）精度，贴着边界写会让这条测试随机失败。
      makeAudio('just_in.wav', 10, modified: now.subtract(const Duration(minutes: 9, seconds: 30)));
      makeAudio('just_out.wav', 10, modified: now.subtract(const Duration(minutes: 10, seconds: 30)));
      final u = measureAudioUsage(dir, referenced: const {}, now: now);
      expect(u.orphanCount, 1);
      expect(u.orphanBytes, 10);
    });

    test('新鲜窗口可以按调用方给的时长覆盖', () {
      makeAudio('rec.wav', 10, modified: now);
      final u = measureAudioUsage(
        dir,
        referenced: const {},
        freshWindow: Duration.zero,
        now: now,
      );
      expect(u.orphanCount, 1);
    });
  });

  group('到达提醒线', () {
    test('刚好到线就算到（判据是 >= 而不是 >）', () {
      const u = AudioUsage(
        fileCount: 1,
        totalBytes: kAudioWarnBytes,
        orphanCount: 0,
        orphanBytes: 0,
      );
      expect(u.overWarnLine, isTrue);
      expect(u.warnRatio, 1.0);
    });

    test('差 1 字节不到线', () {
      const u = AudioUsage(
        fileCount: 1,
        totalBytes: kAudioWarnBytes - 1,
        orphanCount: 0,
        orphanBytes: 0,
      );
      expect(u.overWarnLine, isFalse);
      expect(u.warnRatio, lessThan(1.0));
    });

    test('远超线时进度不溢出（进度条要的是 0~1）', () {
      const u = AudioUsage(
        fileCount: 9,
        totalBytes: kAudioWarnBytes * 3,
        orphanCount: 0,
        orphanBytes: 0,
      );
      expect(u.overWarnLine, isTrue);
      expect(u.warnRatio, 1.0);
    });

    test('空占用时进度为 0，也不会被判成到线', () {
      expect(AudioUsage.empty.overWarnLine, isFalse);
      expect(AudioUsage.empty.warnRatio, 0.0);
    });
  });

  group('listOrphanAudio / purgeOrphanAudio', () {
    test('只列出没被引用的旧文件', () {
      final keep = makeAudio('keep.wav', 10, modified: old);
      final junk = makeAudio('junk.wav', 10, modified: old);
      makeAudio('fresh.wav', 10, modified: now);
      final list = listOrphanAudio(dir, referenced: {keep.path}, now: now);
      expect(list, hasLength(1));
      expect(list.single, junk.path, reason: 'fresh.wav 还在新鲜窗口里，不能列进待删');
    });

    test('清理只删无主的，被引用的原地不动', () async {
      final keep = makeAudio('keep.wav', 10, modified: old);
      final junk = makeAudio('junk.wav', 10, modified: old);
      final n = await purgeOrphanAudio(dir, referenced: {keep.path});
      expect(n, 1);
      expect(keep.existsSync(), isTrue);
      expect(junk.existsSync(), isFalse);
    });

    test('没有无主文件时返回 0，且一个都不误删', () async {
      final keep = makeAudio('keep.wav', 10, modified: old);
      makeAudio('fresh.wav', 10, modified: now);
      // 必须把 now 传进去：新鲜窗口的判据依赖**绝对时间**，
      // 不传的话函数会用真实的 wall clock，而本测试里的 now 是个固定值，
      // fresh.wav 就会被当成"很久以前的残留"删掉（第一版就是这么挂的）。
      final n = await purgeOrphanAudio(dir, referenced: {keep.path}, now: now);
      expect(n, 0);
      expect(keep.existsSync(), isTrue);
      expect(File('${dir.path}/fresh.wav').existsSync(), isTrue);
    });

    test('目录不存在时列出空列表、清理返回 0', () async {
      final missing = Directory('${dir.path}/nope');
      expect(listOrphanAudio(missing, referenced: const {}), isEmpty);
      expect(await purgeOrphanAudio(missing, referenced: const {}), 0);
    });
  });

  group('删除', () {
    test('deleteAudioFile 对 null / 空串 / 不存在的路径都返回 false，且不抛', () async {
      expect(await deleteAudioFile(null), isFalse);
      expect(await deleteAudioFile(''), isFalse);
      expect(await deleteAudioFile('${dir.path}/ghost.wav'), isFalse);
    });

    test('deleteAudioFile 删得掉真文件', () async {
      final f = makeAudio('a.wav', 10);
      expect(await deleteAudioFile(f.path), isTrue);
      expect(f.existsSync(), isFalse);
    });

    test('deleteAudioFiles 返回成功个数；个别坏路径不拖垮整批', () async {
      // 这条对应 `deleteEntry` 那条路：删记录时连带删音频，**不能**因为
      // 一个删不掉的坏文件就把"删记录"这个主流程带崩。
      final a = makeAudio('a.wav', 10);
      final b = makeAudio('b.wav', 10);
      final n = await deleteAudioFiles([a.path, '${dir.path}/ghost.wav', b.path]);
      expect(n, 2);
      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
    });

    test('listAudioFiles 列出全部（含被引用的）—— "删掉本机全部录音"要用它', () async {
      makeAudio('a.wav', 10);
      makeAudio('b.m4a', 10);
      File('${dir.path}/x.txt').writeAsStringSync('x');
      final all = await listAudioFiles(dir);
      expect(all, hasLength(2));
    });

    test('目录不存在时 listAudioFiles 返回空列表', () async {
      expect(await listAudioFiles(Directory('${dir.path}/nope')), isEmpty);
    });
  });

  group('formatBytes', () {
    test('各量级落到对应单位', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(500 * 1024 * 1024), '500.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });

    test('提醒线的文案是给人看的（500MB 而不是一长串字节）', () {
      expect(formatBytes(kAudioWarnBytes), '500.0 MB');
    });
  });
}

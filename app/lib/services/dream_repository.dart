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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dream_entry.dart';

/// 梦境记录的本地存储。
///
/// 设计原则（与项目隐私架构一致）：**记录只存本机**，MVP 阶段无云端同步。
/// 原生平台写应用文档目录下的 JSON 文件；web 目标写 localStorage（见 [WebDreamRepository]）。
abstract class DreamRepository {
  Future<List<DreamEntry>> listAll(); // 按时间倒序
  Future<DreamEntry?> getById(String id);
  Future<void> save(DreamEntry entry);
  Future<void> delete(String id);
  /// 最近 N 天的记录摘要文本（供解析时作为「历史梦境摘要」注入）
  Future<String> recentDigest({int days = 14, String? excludeId});
}

/// 按平台选择存储实现。
///
/// 这个工厂存在的直接原因：`main()` 在 `runApp()` **之前**就会初始化仓库，
/// 而 `FileDreamRepository` 依赖 `dart:io` + `path_provider`（应用文档目录），
/// 在 web 上必然抛异常 —— 异常发生在 runApp 前，release 构建下表现为**整页白屏**、
/// 没有任何提示。所以不能无条件用文件实现。
DreamRepository defaultDreamRepository() =>
    kIsWeb ? WebDreamRepository() : FileDreamRepository();

/// 「最近 N 天梦境摘要」的统一实现（三种仓储共用，避免逻辑分叉）。
///
/// ★ 按**日历日**分组：同一天的多条梦境归到同一个日期标题下。否则逐条单列、只带
/// 日期的写法会让模型把"同一天录的多段梦境"误判成"不同日期的梦"，再叠加框架的
/// 「连续性 / 跨梦」口径，解析结论就错写成"连续多天的梦境"（0.5.7 修复）。
String buildDigest(
  List<DreamEntry> entries, {
  int days = 14,
  String? excludeId,
  bool rich = true,
  DateTime? now,
}) {
  // 「今天」必须可注入：测试用写死日期时，过 14 天这条线就会把它们全部
  // 过滤成空串——0.5.7 的同日分组测试就是这样在 2026-10-12 后集体变红的
  // （定时炸弹）。与 audio_store 的新鲜窗口同一惯例：now 参数可注入。
  final cutoff =
      (now ?? DateTime.now()).subtract(Duration(days: days));
  final all = entries
      .where((e) => e.recordedAt.isAfter(cutoff) && e.id != excludeId)
      .toList();
  if (all.isEmpty) return '';
  if (!rich) {
    // 测试/调试用最简格式（不分组，id 已含日期时分）
    final sb = StringBuffer();
    for (final e in all.take(20)) {
      sb.writeln('- ${e.id}：${e.transcript}');
    }
    return sb.toString().trim();
  }
  // 按日历日归组（保留时间倒序：新的一天在前）。
  final byDay = <DateTime, List<DreamEntry>>{};
  for (final e in all.take(20)) {
    final key = DateTime(e.recordedAt.year, e.recordedAt.month, e.recordedAt.day);
    byDay.putIfAbsent(key, () => []).add(e);
  }
  final dayKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  final sb = StringBuffer();
  sb.writeln('（以下按日历日分组；同一日期下的多条记录是同一天记录的多段梦境，'
      '请勿当作不同日期。）');
  for (final key in dayKeys) {
    final dayEntries = byDay[key]!;
    sb.writeln('【${_d(key)}】当日 ${dayEntries.length} 段梦境：');
    for (final e in dayEntries) {
      final text = e.transcript.length > 80
          ? '${e.transcript.substring(0, 80)}…'
          : e.transcript;
      final imgs = e.analysis?['coding_layer']?['imagery'];
      final imgText = imgs is List && imgs.isNotEmpty
          ? '｜意象：${imgs.take(3).map((i) => (i is Map ? i['token'] : i)).join('、')}'
          : '';
      sb.writeln('  - $text$imgText');
    }
  }
  return sb.toString().trim();
}

String _d(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// 原生平台：每台设备一个目录，每条记录一个 JSON 文件——纯文本、可导出、可手工修复。
class FileDreamRepository implements DreamRepository {
  final Future<Directory> Function() dirProvider;

  FileDreamRepository({Future<Directory> Function()? dirProvider})
      : dirProvider = dirProvider ?? _defaultDir;

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/dreams');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<List<DreamEntry>> listAll() async {
    final dir = await dirProvider();
    if (!await dir.exists()) return [];
    final entries = <DreamEntry>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        entries.add(DreamEntry.fromJsonString(await f.readAsString()));
      } catch (_) {
        // 损坏文件跳过，不阻塞列表
      }
    }
    entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return entries;
  }

  @override
  Future<DreamEntry?> getById(String id) async {
    final dir = await dirProvider();
    final f = File('${dir.path}/$id.json');
    if (!await f.exists()) return null;
    return DreamEntry.fromJsonString(await f.readAsString());
  }

  @override
  Future<void> save(DreamEntry entry) async {
    final dir = await dirProvider();
    await File('${dir.path}/${entry.id}.json').writeAsString(entry.toJsonString());
  }

  @override
  Future<void> delete(String id) async {
    final dir = await dirProvider();
    final f = File('${dir.path}/$id.json');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<String> recentDigest({int days = 14, String? excludeId}) async =>
      buildDigest(await listAll(), days: days, excludeId: excludeId);
}

/// web 目标：浏览器没有「应用文档目录」，改用 shared_preferences
/// （web 上即 localStorage）承载，整表存一个 JSON 字符串。
///
/// 定位说明：web 只是**开发/验证目标**，不是产品主战场（主战场是 iOS/Android）。
/// 但它必须是真能用的——所以选择能持久化的 localStorage，而不是刷新即丢的内存实现。
class WebDreamRepository implements DreamRepository {
  static const _kKey = 'dream_entries_v1';

  Future<Map<String, dynamic>> _readAll() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 存储损坏时不让列表整体失败；原值仍留在 key 上，便于事后人工捞出
    }
    return <String, dynamic>{};
  }

  Future<void> _writeAll(Map<String, dynamic> all) async {
    await (await SharedPreferences.getInstance())
        .setString(_kKey, jsonEncode(all));
  }

  @override
  Future<List<DreamEntry>> listAll() async {
    final all = await _readAll();
    final list = <DreamEntry>[];
    for (final v in all.values) {
      if (v is! Map) continue;
      try {
        list.add(DreamEntry.fromJson(Map<String, dynamic>.from(v)));
      } catch (_) {
        // 单条损坏跳过
      }
    }
    list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return list;
  }

  @override
  Future<DreamEntry?> getById(String id) async {
    final v = (await _readAll())[id];
    if (v is! Map) return null;
    return DreamEntry.fromJson(Map<String, dynamic>.from(v));
  }

  @override
  Future<void> save(DreamEntry entry) async {
    final all = await _readAll();
    all[entry.id] = entry.toJson();
    await _writeAll(all);
  }

  @override
  Future<void> delete(String id) async {
    final all = await _readAll();
    all.remove(id);
    await _writeAll(all);
  }

  @override
  Future<String> recentDigest({int days = 14, String? excludeId}) async =>
      buildDigest(await listAll(), days: days, excludeId: excludeId);
}

/// 内存实现：单元测试使用。
class InMemoryDreamRepository implements DreamRepository {
  final Map<String, DreamEntry> _store = {};

  @override
  Future<List<DreamEntry>> listAll() async {
    final list = _store.values.toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return list;
  }

  @override
  Future<DreamEntry?> getById(String id) async => _store[id];

  @override
  Future<void> save(DreamEntry entry) async => _store[entry.id] = entry;

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<String> recentDigest({int days = 14, String? excludeId}) async =>
      buildDigest(await listAll(),
          days: days, excludeId: excludeId, rich: false);

  String exportJson() => jsonEncode(_store.values.map((e) => e.toJson()).toList());
}

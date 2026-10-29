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

/// 一条记录的**轻量结构化标签**——纯逻辑，只依赖纯 Dart 的文案表。
///
/// 文案本身放在 `lib/l10n/messages.dart`（三语），这里只保留结构（id / 顺序 /
/// 规范化规则）；界面上的中文/英文都从 [AppL10n.current] 取。
///
/// 为什么不引 Flutter：本工程的单测走 `tool/f.sh test`（dart test，不拉
/// flutter_tester），凡是 import Flutter 的文件都进不了测试面（README 第九节第 33 条）。
/// 标签的取选项、规范化、拼进 prompt 的格式，全是"改了会静默出错"的地方，
/// 必须能被测钉住。
///
/// ## 这东西为谁服务（防止功能漂移）
///
/// 本产品的唯一承诺是**解析用户醒来后还记得住的那些梦**（README 第一节硬边界）。
/// 所以标签只做两件事，多一件都不做：
///
/// 1. **为解析抢救素材**。[mood] 是"醒来第一感觉"——画面丢得最快，而情绪残留
///    比画面持久得多；半梦半醒时"心里是慌的还是松的"答得上来，
///    "你的梦讲了什么"答不上来。情绪本身就是梦境内容的一个维度
///    （HVdC 编码体系里就有情绪维度），所以它**是解析的输入**，不是装饰。
/// 2. **回答模型反复在问的问题**。[DreamFlag.recurring] 对应框架的"梦系列分析"，
///    多轮闭环实测里两个模型都主动追问过"这是不是反复出现的梦"——
///    与其让它每轮都问，不如把这答案一次拿到手（与 `recentContext` 同一套思路）。
///
/// **明确不做**：不打分、不做"梦境质量/灵性指数"、不做连续天数。
library;

import '../l10n/messages.dart';

class DreamTags {
  /// 落盘与比较用的**稳定 ASCII id**，不是界面上的中文。
  ///
  /// 用 ASCII 而不是中文标签有两个实际理由：① 中文标签将来改文案
  /// （"不安"→"焦虑"）不会让历史记录变成读不懂的脏数据；② 纯 ASCII 字符串在
  /// Dart AOT 快照里按单字节存，进包验证可以直接搜到（见 README 第 39 条的编码分派）。
  static const moods = <TagOption>[
    TagOption(id: 'calm', keyPrefix: 'mood'),
    TagOption(id: 'uneasy', keyPrefix: 'mood'),
    TagOption(id: 'joyful', keyPrefix: 'mood'),
    TagOption(id: 'sad', keyPrefix: 'mood'),
    TagOption(id: 'tired', keyPrefix: 'mood'),
    TagOption(id: 'unclear', keyPrefix: 'mood'),
  ];

  static const flags = <TagOption>[
    TagOption(id: 'nightmare', keyPrefix: 'flag'),
    TagOption(id: 'recurring', keyPrefix: 'flag'),
    TagOption(id: 'deceased', keyPrefix: 'flag'),
  ];

  static String? moodLabel(String? id) => _labelOf(moods, id);

  static String? flagLabel(String? id) => _labelOf(flags, id);

  /// 界面显示用的标签文案列表（未知 id 一律丢掉）。
  ///
  /// 丢掉而不是原样显示：id 认不出来只可能是数据被手改过或被降级写过，
  /// 把 `zzz_unknown` 这种东西显示给用户毫无意义。
  static List<String> flagLabels(Iterable<String> ids) =>
      ids.map(flagLabel).whereType<String>().toList();

  static String? _labelOf(List<TagOption> options, String? id) {
    final key = (id ?? '').trim();
    if (key.isEmpty) return null;
    for (final o in options) {
      if (o.id == key) return o.label;
    }
    return null;
  }

  /// 把一个候选 id 规范化成**已知 id 或 null**。
  ///
  /// 反序列化老数据/脏数据时统一走它，界面与 prompt 就只会看到合法取值。
  static String? normalizeMood(Object? raw) {
    final key = (raw ?? '').toString().trim();
    if (key.isEmpty) return null;
    for (final o in moods) {
      if (o.id == key) return o.id;
    }
    return null;
  }

  /// flags 规范化：过滤未知 id、去重、并**按 [flags] 的声明顺序排序**。
  ///
  /// 排序的意义是让"同一组标签"只有一种落盘形态——否则用户先点 A 后点 B
  /// 与先点 B 后点 A 会存成两个不同的 JSON，而它们对解析而言完全等价。
  static List<String> normalizeFlags(Object? raw) {
    if (raw is! List) return const [];
    final picked = <String>{};
    for (final e in raw) {
      final key = (e ?? '').toString().trim();
      for (final o in flags) {
        if (o.id == key) picked.add(o.id);
      }
    }
    return [
      for (final o in flags)
        if (picked.contains(o.id)) o.id,
    ];
  }

  /// 有没有真打过标签（决定界面要不要显示标签区、prompt 要不要加那一行）。
  static bool isEmpty({String? mood, Iterable<String> flags = const []}) =>
      (mood ?? '').trim().isEmpty && normalizeFlags(flags.toList()).isEmpty;

  /// 拼成给模型读的一行（人话形态，不是 id）。
  ///
  /// 返回空串表示没有标签 → 调用方**整行都不输出**。
  /// 为什么要显式说明"这是用户自己打的、不是模型推断的"：这两个来源在解析里的
  /// 分量不同。用户填的是事实（"我当时就是发慌"），模型推的是假设；
  /// 不写清楚，模型可能把"用户说他不安"当成"我从文本里读出他不安"，
  /// 于是拿它去当 `evidence` 的替身——而 `evidence` 必须逐字来自原文。
  static String promptLine({String? mood, Iterable<String> flags = const []}) {
    final l10n = AppL10n.current;
    final parts = <String>[];
    final m = moodLabel(mood);
    if (m != null) parts.add(l10n.tr('prompt_mood_prefix', {'m': m}));
    final fs = flagLabels(normalizeFlags(flags.toList()));
    if (fs.isNotEmpty) {
      parts.add(l10n.tr('prompt_flags_prefix', {'fs': fs.join('、')}));
    }
    if (parts.isEmpty) return '';
    return '${l10n.tr('prompt_tags_wrapper')}${parts.join('；')}';
  }
}

/// 一个可选的标签取值。
class TagOption {
  /// 稳定 ASCII id（落盘、进指纹、进包验证都用它）
  final String id;

  /// 文案 key 前缀：`mood` / `flag`。决定去查 `mood_<id>` 还是 `flag_<id>`。
  final String keyPrefix;

  const TagOption({required this.id, required this.keyPrefix});

  /// 界面显示文案——跟随当前界面语言（chip、时间线、详情页都读它）。
  String get label => AppL10n.current.tr('${keyPrefix}_$id');
}

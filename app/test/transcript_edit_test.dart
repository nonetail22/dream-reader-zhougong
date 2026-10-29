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

import 'package:dream_reader/models/dream_entry.dart';
import 'package:test/test.dart';

/// 「用户改了原文」这件事的两个判据测试。
///
/// 这两个判据看着简单，但它们是整个修正链路的开关：
/// - `transcriptWasEdited` 决定要不要给「还原识别结果」这个退路；
/// - `analysisIsStale` 决定要不要提示「旧结论已经对不上」。
/// 判错任一方向都有代价：判早了是噪音（每条手输记录都弹提示），
/// 判晚了是**静默的谎言**（拿改之前的结论去对应改之后的原文）。所以逐个钉死。
void main() {
  DreamEntry entry({
    String transcript = '我梦到在很高的楼顶，风很大。',
    String? rawTranscript,
    Map<String, dynamic>? analysis,
    String? analyzedTranscript,
  }) =>
      DreamEntry(
        id: '20260920-0712',
        recordedAt: DateTime(2026, 9, 20, 7, 12),
        transcript: transcript,
        rawTranscript: rawTranscript,
        analysis: analysis,
        analyzedTranscript: analyzedTranscript,
      );

  const fakeAnalysis = <String, dynamic>{
    'analysis_layer': [
      {'theory': '弗洛伊德', 'confidence': 'A', 'content': '高处常与掌控感相关。', 'evidence': '很高的楼顶'},
    ],
    'advice_layer': ['留意最近是否有悬而未决的决定。'],
    'limitations_note': '仅凭单次记录无法定论。',
    'safety_flag': 'none',
  };

  group('transcriptWasEdited：与识别器原始输出比', () {
    test('手输记录没有机器版本 → 不算改过（否则手输记录会平白多出还原按钮）', () {
      expect(entry().transcriptWasEdited, isFalse);
    });

    test('识别结果原样保存 → 没改过', () {
      final e = entry(
        transcript: '我梦到在很高的楼顶。',
        rawTranscript: '我梦到在很高的楼顶。',
      );
      expect(e.transcriptWasEdited, isFalse);
    });

    test('原文与识别输出不一致 → 改过', () {
      final e = entry(
        transcript: '我梦到在很高的楼顶上。', // 用户补了「上」
        rawTranscript: '我梦到在很高的楼顶。',
      );
      expect(e.transcriptWasEdited, isTrue);
    });

    test('改回与识别输出完全一致 → 又变回没改过（还原按钮该消失）', () {
      final e = entry(
        transcript: '我梦到在很高的楼顶。',
        rawTranscript: '我梦到在很高的楼顶。',
      );
      expect(e.transcriptWasEdited, isFalse);
    });

    test('识别输出为空串也是"有机器版本"，与空原文相比仍算改过', () {
      final e = entry(transcript: '什么都没听清，我自己补的。', rawTranscript: '');
      expect(e.transcriptWasEdited, isTrue);
    });
  });

  group('analysisIsStale：与"当初拿去解析的那份原文"比', () {
    test('从没解析过 → 不算过期（新记录/手输记录的常见态）', () {
      final e = entry(transcript: '随便改了什么', analyzedTranscript: '原文');
      expect(e.analysisIsStale, isFalse);
    });

    test('解析过但老记录没有 analyzed_transcript → 当作没过期，不凭空提示', () {
      final e = entry(transcript: '改过了', analysis: fakeAnalysis);
      expect(e.analysisIsStale, isFalse);
    });

    test('解析后原文没动 → 不过期', () {
      final e = entry(
        transcript: '我梦到在很高的楼顶。',
        analysis: fakeAnalysis,
        analyzedTranscript: '我梦到在很高的楼顶。',
      );
      expect(e.analysisIsStale, isFalse);
    });

    test('解析后原文被改 → 过期（这正是要提示的核心场景）', () {
      final e = entry(
        transcript: '我梦到在很高的楼顶上，风很大。', // 改之后
        analysis: fakeAnalysis,
        analyzedTranscript: '我梦到在很高的楼顶。', // 解析时用的
      );
      expect(e.analysisIsStale, isTrue);
    });

    test('改回解析时那一版 → 结论重新对上，不再过期', () {
      final e = entry(
        transcript: '我梦到在很高的楼顶。',
        analysis: fakeAnalysis,
        analyzedTranscript: '我梦到在很高的楼顶。',
      );
      expect(e.analysisIsStale, isFalse);
    });

    test('解析失败（analysis 为 null）时改原文 → 不算过期，该走的是"重试解析"', () {
      final e = entry(
        transcript: '改过的原文',
        analyzedTranscript: '失败时的原文',
      );
      expect(e.analysisIsStale, isFalse);
    });
  });

  group('落盘 / 读盘：这两个字段跨重启必须还在', () {
    test('JSON 往返保留 raw_transcript 与 analyzed_transcript', () {
      final e = entry(
        transcript: '改之后的原文',
        rawTranscript: '识别器输出的原文',
        analysis: fakeAnalysis,
        analyzedTranscript: '识别器输出的原文',
      );
      final back = DreamEntry.fromJsonString(e.toJsonString());
      expect(back.rawTranscript, '识别器输出的原文');
      expect(back.analyzedTranscript, '识别器输出的原文');
      expect(back.transcriptWasEdited, isTrue);
      expect(back.analysisIsStale, isTrue);
    });

    test('老版本 JSON（没有这两个键）读进来是 null，且语义为"没改过、没过期"', () {
      final legacy = <String, dynamic>{
        'id': '20260901-0700',
        'recorded_at': DateTime(2026, 9, 1, 7).toIso8601String(),
        'transcript': '我梦见自己在飞。',
        'status': 'analyzed',
        'analysis': fakeAnalysis,
        // 刻意不含 raw_transcript / analyzed_transcript
      };
      final back = DreamEntry.fromJson(legacy);
      expect(back.rawTranscript, isNull);
      expect(back.analyzedTranscript, isNull);
      expect(back.transcriptWasEdited, isFalse);
      expect(back.analysisIsStale, isFalse);
      // 解析结果本身必须完好，不能因为缺新字段就把老结论弄丢
      expect(back.analysisItems, hasLength(1));
    });

    test('copyWith 改原文不会顺手清掉 rawTranscript / analyzedTranscript', () {
      final e = entry(
        transcript: '旧原文',
        rawTranscript: '识别器输出',
        analysis: fakeAnalysis,
        analyzedTranscript: '旧原文',
      );
      final edited = e.copyWith(transcript: '新原文');
      expect(edited.rawTranscript, '识别器输出');
      expect(edited.analyzedTranscript, '旧原文');
      expect(edited.analysisIsStale, isTrue);
    });
  });

  group('完整链路：识别 → 解析 → 手改 → 重解析 → 还原', () {
    test('每一步的状态都符合预期', () {
      // 1) 识别完，尚未解析：改没改过要有数，但不存在"过期"
      var e = entry(
        transcript: '我梦到在很高的楼顶。',
        rawTranscript: '我梦到在很高的楼顶。',
      );
      expect(e.transcriptWasEdited, isFalse);
      expect(e.analysisIsStale, isFalse);

      // 2) 解析成功：记下用的是哪份原文
      e = e.copyWith(
        status: 'analyzed',
        analysis: fakeAnalysis,
        analyzedTranscript: e.transcript,
      );
      expect(e.analysisIsStale, isFalse);

      // 3) 用户手动修正识别错误 → 结论过期，且能还原
      e = e.copyWith(transcript: '我梦到在很高的楼顶上，风很大。');
      expect(e.transcriptWasEdited, isTrue);
      expect(e.analysisIsStale, isTrue);

      // 4) 用户决定用新原文重新解析 → 重新对上
      e = e.copyWith(analyzedTranscript: e.transcript);
      expect(e.analysisIsStale, isFalse);
      // 但"改过"这件事仍然成立 —— 还原的退路不能断
      expect(e.transcriptWasEdited, isTrue);
      expect(e.rawTranscript, '我梦到在很高的楼顶。');

      // 5) 用户觉得改得还不如机器那版 → 还原，此时结论也重新对上了
      e = e.copyWith(transcript: e.rawTranscript!);
      expect(e.transcriptWasEdited, isFalse);
      expect(e.analysisIsStale, isTrue, reason: '还原后原文回到了"解析时那一版之前"，结论确实对不上');
    });
  });
}

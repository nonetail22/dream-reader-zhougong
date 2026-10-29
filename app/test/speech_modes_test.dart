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

// 转写方式的「差别说明」回归测试。
//
// 这些文字是给用户做决定用的，最容易在某次重构里被顺手改成一句正确但
// 没信息量的通用话术——尤其是隐私那两条（"音频不出设备" / "录音会上传"）。
// 所以这里不只检查"非空"，而是钉住**关键事实本身**。
import 'package:dream_reader/services/speech_mode.dart';
import 'package:test/test.dart';

SpeechFact factOf(SpeechMode m, String label) =>
    m.facts.firstWhere((f) => f.label == label);

void main() {
  group('SpeechMode 基本约定', () {
    test('id 唯一且稳定', () {
      final ids = SpeechMode.values.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'id 重复会让设置互相覆盖');
      expect(ids, containsAll(['system', 'offline', 'cloud']));
    });

    test('fromId 能来回', () {
      for (final m in SpeechMode.values) {
        expect(SpeechMode.fromId(m.id), m);
      }
    });

    test('认不出来的 id 回落默认值，而不是抛异常', () {
      // 用户跨版本升级时，老设置里可能有已经删掉的 id；
      // 这里抛异常会让 App 直接起不来。
      expect(SpeechMode.fromId(null), SpeechMode.fallback);
      expect(SpeechMode.fromId(''), SpeechMode.fallback);
      expect(SpeechMode.fromId('这是上个版本的东西'), SpeechMode.fallback);
    });

    test('默认是离线：只有它不依赖设备、不联网、不上传', () {
      expect(SpeechMode.fallback, SpeechMode.offline);
    });
  });

  group('「谁占麦克风 / 音频去哪」——两条最要命的区别', () {
    test('只有云端会让音频离开设备', () {
      expect(SpeechMode.cloud.audioLeavesDevice, isTrue);
      expect(SpeechMode.system.audioLeavesDevice, isFalse);
      expect(SpeechMode.offline.audioLeavesDevice, isFalse);
    });

    test('只有云端必须联网', () {
      expect(SpeechMode.cloud.needsNetwork, isTrue);
      expect(SpeechMode.offline.needsNetwork, isFalse);
      expect(SpeechMode.system.needsNetwork, isFalse);
    });

    test('离线与云端要自己录音，系统识别不要（它自己开麦克风）', () {
      expect(SpeechMode.offline.needsRecording, isTrue);
      expect(SpeechMode.cloud.needsRecording, isTrue);
      expect(SpeechMode.system.needsRecording, isFalse);
    });

    test('云端那一条的说明必须写明"会上传"', () {
      final v = factOf(SpeechMode.cloud, '音频去向').value;
      expect(v, contains('上传'), reason: '这是隐私承诺的核心事实，不能被弱化成"交给服务商处理"之类');
    });

    test('离线那一条的说明必须写明"不出设备"', () {
      final v = factOf(SpeechMode.offline, '音频去向').value;
      expect(v, contains('不出设备'));
    });

    test('离线那一条必须写明不需要联网', () {
      final v = factOf(SpeechMode.offline, '要不要联网').value;
      expect(v, contains('不需要'), reason: '凌晨可能没网，这条是选它的主要理由');
    });

    test('离线的代价（首次要下载模型 + 不是实时）必须写出来', () {
      final c = SpeechMode.offline.caveat;
      // 0.6.0 起模型不预装进安装包，改为首次使用联网下载；0.7.0 起含标点模型（合计约 320MB）。
      // 判据钉「要下载」与量级，不钉措辞——量级变了说明模型换人了，
      // 界面文案必须跟着改，不能拿旧数字骗用户。
      expect(c, contains('320MB'));
      // 判据刻意不钉具体措辞，只钉"有没有把'不是实时'说出来"。
      // （曾钉过「松手」——那是按住式录音时代的词；录音改成点击式后它就变成了
      // 一个会误导用户的假事实，说明"拿旧措辞当判据"本身会过期。见 MEMORY 判据一节。）
      expect(c, contains('说完'), reason: '"不是边说边出字"是用户能感觉到的差别，不能瞒着');
    });

    test('系统识别必须写明依赖设备自带服务', () {
      final v = factOf(SpeechMode.system, '前提').value;
      final c = SpeechMode.system.caveat;
      expect('$v$c', contains('设备'));
      expect(c, contains('离线'), reason: '用不了时要给出去哪条路，不能只报错');
    });
  });

  group('每条说明本身要完整、可读', () {
    for (final m in SpeechMode.values) {
      test('${m.id}：文案齐全', () {
        expect(m.label.trim(), isNotEmpty);
        expect(m.tagline.trim(), isNotEmpty);
        expect(m.caveat.trim().length, greaterThan(8));
      });

      test('${m.id}：对照维度至少覆盖 5 项且不重复', () {
        expect(m.facts.length, greaterThanOrEqualTo(5));
        final labels = m.facts.map((f) => f.label).toList();
        expect(labels.toSet().length, labels.length, reason: '同一维度写两遍会互相矛盾');
      });

      test('${m.id}：每个维度都有实打实的取值', () {
        for (final f in m.facts) {
          expect(f.label.trim(), isNotEmpty);
          expect(f.value.trim().length, greaterThan(3),
              reason: '「${f.label}」的说明太短，等于没说');
        }
      });

      test('${m.id}：必须回答"出字时机 / 音频去向 / 要不要联网 / 花钱吗"', () {
        final labels = m.facts.map((f) => f.label).toSet();
        expect(labels, containsAll(<String>['出字时机', '音频去向', '要不要联网', '花钱吗']));
      });
    }
  });
}

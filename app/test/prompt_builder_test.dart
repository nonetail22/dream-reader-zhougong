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

import 'package:dream_reader/l10n/app_locale.dart';
import 'package:dream_reader/services/fingerprint.dart';
import 'package:dream_reader/services/prompt_core.dart';
import 'package:test/test.dart';

/// Prompt 装配层的契约测试：保证「框架文档 → system message」这条路不会悄悄退化。
///
/// 只依赖纯逻辑（prompt_core.dart）+ dart:io 读文件，因此用 `dart test` 即可运行，
/// 不需要 flutter_tester 或浏览器。测试同时确认 assets/framework_prompt.md 已生成。
void main() {
  late PromptBuilder builder;
  late String doc;

  setUpAll(() {
    doc = File(PromptBuilder.assetPath).readAsStringSync();
    builder = PromptBuilder(doc);
  });

  test('能提取 System Prompt 与 JSON Schema', () {
    expect(builder.systemPromptBody, contains('你是一名以古传周公解梦体系为依据'));
    expect(builder.jsonSchema, contains('limitations_note'));
    expect(builder.jsonSchema, contains('coding_layer'));
  });

  test('输出契约完整：第五部分输出格式必须在 system prompt 内（第0步验证教训）', () {
    final sys = builder.buildSystemPrompt();
    expect(sys, contains('第五部分：输出格式'));
    expect(sys, contains('不得输出 JSON 以外的任何文字'));
  });

  test('Z4 硬性规则必须在 prompt 内（上游 v1.0.3 教训：硬约束写在执行点）', () {
    expect(builder.systemPromptBody, contains('凡 theory 引用 Z4 的条目'));
  });

  test('碎片化处理与威胁未形象化规则必须存在（v1.0.2 固化的护栏）', () {
    final sys = builder.buildSystemPrompt();
    expect(sys, contains('碎片化口述处理'));
    expect(sys, contains('威胁未形象化不推测'));
  });

  test('buildSystemPrompt = Prompt 全文 + Schema（装配说明要求）', () {
    final sys = builder.buildSystemPrompt();
    expect(sys.startsWith(builder.systemPromptBody), isTrue);
    expect(sys.endsWith(builder.jsonSchema), isTrue);
  });

  test('User Prompt 模板字段齐全，空值有显式占位', () {
    final user = builder.buildUserPrompt(
      date: '2026-09-20',
      wakeTime: '07:12',
      recentContext: '',
      dreamHistoryDigest: '',
      transcript: '我梦见一条很长的走廊。',
    );
    expect(user, contains('【日期】2026-09-20'));
    expect(user, contains('（未填写）'));
    expect(user, contains('（无）'));
    expect(user, contains('我梦见一条很长的走廊。'));
  });

  test('框架文档缺块时明确报错，而不是静默降级', () {
    expect(() => PromptBuilder('没有代码块').systemPromptBody, throwsStateError);
    expect(() => PromptBuilder('没有第四节').jsonSchema, throwsStateError);
  });

  // ---- v1.1.0「让人看懂」的可读性契约 ----
  //
  // 这一组钉住的是那次真机反馈（"我没看懂解析写的是什么"）的修复不被回退。
  // 契约测试只能保证**文档里有这些约束**，保证不了模型遵守——那是另一回事
  // （需要真实模型跑回归集）。但没有这一组，约束会在某次改 Prompt 时静悄悄消失。
  group('v1.1.0 可读性契约', () {
    // 周公版差异：assets/framework_prompt.md 是**单真源**（上游的「assets 与 docs 双份
    // 逐字节一致」哨兵在本工程不适用——周公版没有 docs 源文档与同步脚本）。

    test('版本号与版本记录同步到 vZ1.0（上游 v1.1.x 的护栏标注仍保留）', () {
      expect(doc, contains('当前版本 vZ1.0'));
      expect(doc, contains('- **vZ1.0（2026-10-29）**'));
      // 周公版不是孤立发明：它显式声明继承自上游 v1.1.2
      expect(doc, contains('v1.1.2'));
    });

    test('第 6 条原则「让人看懂」及其两条禁令必须在文档里', () {
      expect(doc, contains('不可妥协的六条'));
      expect(doc, contains('让人看懂'));
      // 两条禁令：不许把"看不懂"当专业、不许把"无法判定"当结论交付
      expect(doc, contains('不许把"看不懂"当专业'));
      expect(doc, contains('信息缺口是提问的机会，不是结论'));
    });

    test('Schema 必须含 v1.1.0 的四个新字段', () {
      expect(builder.jsonSchema, contains('"reading"'));
      expect(builder.jsonSchema, contains('"headline"'));
      expect(builder.jsonSchema, contains('"point"'));
      expect(builder.jsonSchema, contains('"terms"'));
      expect(builder.jsonSchema, contains('"open_questions"'));
    });

    test('工作流程里白话层在解析层之前、提问层在解析层之后', () {
      final sys = builder.systemPromptBody;
      expect(sys, contains('第二步：白话解读层'));
      expect(sys, contains('第三步：解析层'));
      expect(sys, contains('第四步：提问层'));
      final plain = sys.indexOf('第二步：白话解读层');
      final analysis = sys.indexOf('第三步：解析层');
      final questions = sys.indexOf('第四步：提问层');
      // 顺序很要紧：先编（编码）→ 再说人话（结论）→ 再给依据 → 最后才追问
      expect(plain, lessThan(analysis));
      expect(analysis, lessThan(questions));
    });

    test('禁止术语进 point、禁止把"无法判定"当结论（两条硬护栏）', () {
      final sys = builder.systemPromptBody;
      expect(sys, contains('禁止出现任何专业术语'));
      expect(sys, contains('禁止把"无法判定"'));
    });

    test('解析层加了排序与条数约束（不许为覆盖典籍类目清单凑数）', () {
      final sys = builder.systemPromptBody;
      expect(sys, contains('按「对理解这个梦的重要性」从高到低排'));
      expect(sys, contains('不要按理论体系或机制归类排序'));
      expect(sys, contains('2~5 条'));
      expect(sys, contains('禁止为了覆盖典籍类目清单而凑条数'));
    });

    test('置信度必须与人话结论一起展示（可读性不得以牺牲可信度为代价）', () {
      expect(doc, contains('界面必须把置信度与人话结论放在一起展示'));
    });

    test('校验清单新增了可读性与提问质量的检查项', () {
      expect(doc, contains('可读性（v1.1.0 新增）'));
      expect(doc, contains('"无法判定"归位（v1.1.0 新增）'));
      // v1.1.1 起这一条的标题带上了扩范围说明，断言随之更新
      expect(doc, contains('术语桥（v1.1.0；v1.1.1 扩范围）'));
      expect(doc, contains('提问质量（v1.1.0 新增）'));
    });

    test('User Prompt 的近期状态一栏已说明它可能承载「对提问的回答」', () {
      final user = builder.buildUserPrompt(
        date: '2026-09-22',
        wakeTime: '07:12',
        recentContext: '最近在等一个工作结果。',
        dreamHistoryDigest: '',
        transcript: '我梦见一条很长的走廊。',
      );
      expect(user, contains('对上次解析所提问题的回答'));
      expect(user, contains('最近在等一个工作结果。'));
    });
  });

  // ---------------------------------------------------------------------------
  // v1.1.1：evidence 的"可核对性"契约。
  //
  // 这一组直接来自首轮真实模型实测（validation/preview/）：11 条硬护栏里唯一 FAIL 的就是
  // evidence —— glm-5.3 用 `……` 省略、用 `；` 拼接，于是界面上的 `原文："…"` 用户搜不到。
  // 所以这组不只是"文档里有没有这句话"，最后一条会把**真实失败样本**当夹具跑一遍判定。
  // ---------------------------------------------------------------------------
  group('v1.1.1 证据可核对契约', () {
    test('第三步 evidence 定义含三条硬性要求（连续 / 禁省略 / 禁拼接）', () {
      final sys = builder.systemPromptBody;
      expect(sys, contains('原文里连续的一段，逐字复制'));
      expect(sys, contains('必须连续'));
      expect(sys, contains('禁止省略'));
      expect(sys, contains('禁止拼接'));
      // 正向做法也要给：光说"不许"模型会不知道该怎么办
      expect(sys, contains('优先选其中最有代表性、且最短的那一段'));
    });

    test('硬性禁止事项新增 #12：禁止伪造或拼接原文引用', () {
      final sys = builder.systemPromptBody;
      expect(sys, contains('12. 禁止伪造或拼接原文引用'));
      // 要说清"为什么"——伪装成证据比写"无法判定"更有害
      expect(sys, contains('因为它伪装成了证据'));
    });

    test('第五部分输出格式也带 evidence 约束（契约要被读到两遍）', () {
      final sys = builder.systemPromptBody;
      expect(sys, contains('evidence 必须是原文里连续的一段、逐字复制'));
    });

    test('Schema 的 evidence 不再是含糊的「原文引用」', () {
      expect(builder.jsonSchema, contains('必须是原文里连续的一段、逐字复制'));
      expect(builder.jsonSchema, contains('用「；」「，」「、」把不相邻的片段拼接成一句'));
      // 旧措辞必须消失，否则等于没改
      expect(builder.jsonSchema, isNot(contains('"evidence": "string（原文引用）"')));
    });

    test('terms 的覆盖范围从 content 扩到「content 或 theory」（Backlog #11 落地）', () {
      expect(doc, contains('content **或 theory** 里用到的专业术语'));
      expect(builder.systemPromptBody, contains('content **或 theory** 里出现的术语'));
      // v1.1.2 起 Schema 里那句同时写了"逐字出现过"（同一条规则的反向要求）
      expect(builder.jsonSchema, contains('content 或 theory 里**逐字出现过**的专业术语'));
      // 常见病根：模型会拿 theory 里的机制名（如 T2-放大法）去问，界面又看得见它
      expect(doc, contains('theory 也要算进来'));
    });

    test('校验清单新增「原文引用可搜」，且写明不许用"意思到了"放过', () {
      expect(doc, contains('原文引用可搜（v1.1.1 新增'));
      expect(doc, contains('子串匹配'));
      expect(doc, contains('不得用"内容基本一致"'));
    });

    test('字段职责说明点明 evidence 是唯一可被外部验证的字段', () {
      expect(doc, contains('`evidence` 的特殊地位（v1.1.1）'));
      expect(doc, contains('只有 `evidence` 是**可被外部验证的锚点**'));
    });

    // 这一条才是这组的重点：拿真实模型的真实失败输出当回归夹具。
    // 判定方式与校验清单里写的那条一致——子串匹配，全命中。
    test('回归夹具：真实失败样本必须被判为不合规、真实合格样本必须通过', () {
      const transcript =
          '昨晚梦见我回到小时候住的那个老房子，房子比记忆里小很多，客厅里有一张很长的桌子，桌上摆满了别人的东西。'
          '我妈妈在厨房里，但一直背对着我，我怎么喊她都不转过来。后来我从窗户爬出去，外面是一片水，'
          '水面上漂着一只很大的白鸟，我骑上去，它飞得很高，飞到一半我发现自己在往下掉，'
          '但一点也不害怕，反而是很轻松的感觉。落地的地方是一片没有人的海滩，沙滩上有很多钟表，指针都在倒着走。';

      // 校验清单里那条判据的 Dart 实现：原文引用必须能在 transcript 里搜到。
      bool isTraceable(String evidence) => transcript.contains(evidence);

      // ✗ glm-5.3 的真实输出（4 条里 3 条不合规）——省略号截断、标点拼接
      const glmBad = [
        '我从窗户爬出去……我骑上去，它飞得很高，飞到一半我发现自己在往下掉，但一点也不害怕，反而是很轻松的感觉',
        '房子比记忆里小很多……沙滩上有很多钟表，指针都在倒着走',
        '我怎么喊她都不转过来；我从窗户爬出去；反而是很轻松的感觉',
      ];
      for (final e in glmBad) {
        expect(isTraceable(e), isFalse,
            reason: '这条引用被省略号截断/标点拼接了，判定必须为"搜不到"，否则闸门形同虚设');
      }

      // ✓ deepseek-v4-pro 的真实输出（5/5 命中）
      const dsGood = [
        '我妈妈在厨房里，但一直背对着我，我怎么喊她都不转过来',
        '我发现自己在往下掉，但一点也不害怕，反而是很轻松的感觉',
        '客厅里有一张很长的桌子，桌上摆满了别人的东西',
        '沙滩上有很多钟表，指针都在倒着走',
        '水面上漂着一只很大的白鸟，我骑上去，它飞得很高',
      ];
      for (final e in dsGood) {
        expect(isTraceable(e), isTrue, reason: '逐字引用应当能被搜到');
      }
    });
  });

  // ---- v1.1.2「输出可解析 + 提问有出口」契约 ----
  //
  // 这一组钉住第四轮多轮闭环实测（validation/preview/ 的 R2~R5）暴露的四件事。
  // 其中最严重的一条不是"某个字段写得不好"，而是**整份输出作废**：
  // 用户输入里的半角引号被模型原样搬进 JSON 值 → 前端解析失败 → 用户等 12 分钟
  // 什么都拿不到，而服务端不报错。这类约束一旦从文档里掉出去，代价是静默的。
  group('v1.1.2 输出可解析与提问出口契约', () {
    test('硬性禁止事项 #13：字符串值里不得有未转义的双引号', () {
      final sys = builder.buildSystemPrompt();
      expect(sys, contains('禁止在 JSON 字符串值里留下**未转义的双引号**'));
      // 必须同时给出"不许改用全角绕过"的理由——否则模型会用另一个错误换掉这个错误
      expect(sys, contains('不许改用全角引号'), reason: 'evidence 要求逐字，换字符会让"原文引用可搜"失败');
      // 以及唯一自检标准
      expect(sys, contains('丢进 JSON 解析器'));
    });

    test('Schema 新增 no_more_questions，且与 open_questions 严格联动', () {
      final schema = builder.jsonSchema;
      expect(schema, contains('no_more_questions'));
      final sys = builder.buildSystemPrompt();
      // 双向都要写清：空数组 ⇔ true；非空 ⇔ false
      expect(sys, contains('当且仅当'));
      expect(sys, contains('就必须是'));
    });

    test('"问完了"是个正当结论，不是需要遮掩的空白', () {
      final sys = builder.buildSystemPrompt();
      // 这条的理由必须留在文档里：护栏"必须有提问"在结构上惩罚诚实
      expect(sys, contains('没有新问题"是一个正当的结论'));
      // 同时不许变成"可以不问"的借口
      expect(sys, contains('不是"可以不问"的借口'));
    });

    test('analysis_layer 5 条上限写成硬约束（实测曾在信息耗尽轮出到 6 条）', () {
      final sys = builder.buildSystemPrompt();
      expect(sys, contains('2~5 条，上限是硬的'));
      expect(sys, contains('把每条写得更准'));
    });

    test('terms 规则是双向的（上游实测反例：正文只写"隐意"却列了"隐梦"；周公版反例同构）', () {
      final sys = builder.buildSystemPrompt();
      expect(sys, contains('逐字出现过'));
      expect(sys, contains('得财'), reason: '把同构反例写进文档（正文"主财"/terms"得财"），模型才有具体的负面样本');
    });

    test('周公版流派护栏：吉凶不定命、多解并陈、睡瘫不按凶兆解必须在 prompt 里', () {
      final sys = builder.systemPromptBody;
      // 定命断言是传统解梦最容易滑向的坑，护栏要出现在模型执行点
      expect(sys, contains('禁止定命断言'));
      // 多解并陈是本流派的立身要求（对应上游「象征至少两种可能」）
      expect(sys, contains('多解并陈'));
      // 睡瘫禁止按凶兆/灵异解读——防止传统释义制造恐惧
      expect(sys, contains('禁止按"鬼压床"'));
    });

    test('校验清单第 0 条是"输出可被解析"——它能一票否决其余全部检查', () {
      final doc = File(PromptBuilder.assetPath).readAsStringSync();
      expect(doc, contains('输出可被解析（v1.1.2 新增，第 0 条'));
      expect(doc, contains('一票否决'));
      expect(doc, contains('含半角双引号/换行/反斜杠的用户输入'));
    });

    test('重试指令也要点名引号转义（App 侧兜底那次调用）', () {
      expect(PromptBuilder.jsonRetryInstruction, contains('转义'));
      expect(PromptBuilder.jsonRetryInstruction, contains('不要改成全角'));
    });
  });

  group('结构化标签契约（0.4.6）', () {
    /// **加标签之前**的 user prompt 形态。逐字抄自 0.4.5 的实现，
    /// 专门用来做"空标签必须不改变任何东西"的对照。
    String legacyPrompt({
      required String date,
      required String wakeTime,
      required String recentContext,
      required String dreamHistoryDigest,
      required String transcript,
    }) {
      final ctx = recentContext.trim().isEmpty ? '（未填写）' : recentContext.trim();
      final history =
          dreamHistoryDigest.trim().isEmpty ? '（无）' : dreamHistoryDigest.trim();
      return '【日期】$date　【醒来时间】$wakeTime（推测 REM 窗口，仅供备注）\n'
          '【近期状态与补充说明（用户可选填写；也可能是对上次解析所提问题的回答）】$ctx\n'
          '【历史梦境摘要（系统自动附最近 14 天，无则省略）】$history\n'
          '【梦境口述原文】\n$transcript';
    }

    String build({String? mood, List<String> flags = const []}) =>
        builder.buildUserPrompt(
          date: '2026-09-23',
          wakeTime: '07:12',
          recentContext: '',
          dreamHistoryDigest: '',
          transcript: '我梦见自己在飞。',
          mood: mood,
          flags: flags,
        );

    test('★ 没有标签时，user prompt 与加标签之前**逐字相同**', () {
      // 这条钉的不是"格式好看"，而是**已经落盘的指纹还能不能用**：
      // analyzedFingerprint 是按旧形态算出来的，空标签只要多出一个换行符，
      // 所有历史记录都会在用户点「重新解析」时被误报成"输入变了"、
      // 而模型看到的其实一字未改——那正是 0.3.5 花一整版修掉的那个谎。
      expect(
        build(),
        legacyPrompt(
          date: '2026-09-23',
          wakeTime: '07:12',
          recentContext: '',
          dreamHistoryDigest: '',
          transcript: '我梦见自己在飞。',
        ),
      );
    });

    test('空标签与"未知 id"都不该在 prompt 里留下任何痕迹', () {
      // 未知 id 在反序列化时就已经被挡掉了（见 dream_tags_test），
      // 这里再钉一次：即便有人绕过那一层直接塞进来，也不能污染 prompt。
      expect(build(mood: 'zzz'), build());
      expect(build(flags: const ['zzz']), build());
    });

    test('有标签时新增一段，且说的是中文而不是内部 id', () {
      final p = build(mood: 'uneasy', flags: const ['recurring']);
      expect(p, contains('【本次记录的标签'));
      expect(p, contains('醒来第一感觉：不安'));
      expect(p, contains('反复出现的梦'));
      expect(p, isNot(contains('uneasy')));
      // 原文与其它栏必须原样保留，标签只是"插入一段"而不是替换
      expect(p, contains('【梦境口述原文】\n我梦见自己在飞。'));
      expect(p, contains('【日期】2026-09-23'));
    });

    test('标签这一段排在原文**之前**（模型读原文前刚看过它）', () {
      final p = build(mood: 'calm');
      expect(
        p.indexOf('【本次记录的标签'),
        lessThan(p.indexOf('【梦境口述原文】')),
      );
    });

    test('★ 标签变了 → user prompt 变了 → 输入指纹必然跟着变', () {
      // 指纹就是 joinFingerprint([system, user, model])。这里直接按同一口径算，
      // 证明"用户改标签后点重新解析"不会被 0.3.5 那道「输入没变」的闸门拦下来。
      final sys = builder.buildSystemPrompt();
      String fp(String user) => joinFingerprint([sys, user, 'gpt-x']);

      final base = build(mood: 'calm');
      expect(fp(base), isNot(fp(build(mood: 'uneasy'))));
      expect(fp(base), isNot(fp(build(mood: 'calm', flags: const ['nightmare']))));
      // 反过来：标签没动，指纹就必须一模一样（否则重解析会被误判成"有意义"）
      expect(fp(base), fp(build(mood: 'calm')));
    });

    test('标签写进 prompt 时声明了"不得当作原文引用"（evidence 必须逐字）', () {
      // 这是本产品"结论挂在可追溯原文片段上"的立身之本：标签是用户说的话，
      // 但不是**梦的口述原文**，模型一旦拿它当 evidence，
      // 用户回原文里就搜不到这句话（与 v1.1.1 修的省略号/拼接是同一类失效）。
      expect(build(mood: 'sad'), contains('不得当作梦境原文引用'));
    });

    test('标签这一段没有动 system prompt（历史记录的 system 侧指纹不受影响）', () {
      // 刻意的取舍：把约束写在 user prompt 里而不是加进框架文档，
      // 这样 system prompt 一个字符都不变 —— 已落盘的指纹里 system 那一半仍然有效，
      // 没打过标签的记录整体指纹与旧版完全一致。
      expect(builder.buildSystemPrompt(), isNot(contains('本次记录的标签')));
    });
  });

  // ---------------------------------------------------------------------------
  // v1.1.4：输出语言指令的**位置**契约。
  //
  // 来历（2026-09-24 真实模型实测，validation/preview/check_language_directive.mjs）：
  // 0.5.0 把「请用界面语言回答」追加在 system prompt 末尾 → deepseek-v4-pro 完全无视
  // （要求英文却交简体中文），而且**静默**——护栏脚本拿英文词表去查中文文本会空过，
  // 测试全绿、报告全绿，功能其实没生效。同一句措辞挪到 user prompt 末尾后立刻生效。
  // 所以这组钉的不是"有没有这句指令"，而是**它在哪**：位置一错，功能死掉还看不出来。
  // ---------------------------------------------------------------------------
  group('v1.1.4 输出语言指令的位置契约', () {
    String withDirective(String? d) => builder.buildUserPrompt(
          date: '2026-09-23',
          wakeTime: '07:12',
          recentContext: '',
          dreamHistoryDigest: '',
          transcript: '我梦见自己在飞。',
          languageDirective: d,
        );

    test('★ 语言指令必须排在**最末尾**（原文之后）', () {
      final d = AppLocale.en.analysisLanguageDirective!;
      final p = withDirective(d);
      expect(p.indexOf(d), greaterThan(p.indexOf('我梦见自己在飞。')));
      expect(p.trimRight().endsWith(d), isTrue);
    });

    test('★ system prompt 里绝不能出现语言指令（防止有人把它挪回去）', () {
      final sys = builder.buildSystemPrompt();
      for (final l in AppLocale.values) {
        final d = l.analysisLanguageDirective;
        if (d != null) {
          expect(sys, isNot(contains(d)), reason: '放回 system prompt 会被模型静默忽略');
        }
      }
    });

    test('zhCN 不带指令，且 user prompt 与加此功能之前**逐字相同**', () {
      // 与标签那一条同理：只要多出一个换行，所有已落盘记录的指纹都会在用户点
      // 「重新解析」时被误报成"输入变了"，而模型看到的一字未改。
      expect(AppLocale.zhCN.analysisLanguageDirective, isNull);
      expect(
        withDirective(AppLocale.zhCN.analysisLanguageDirective),
        '【日期】2026-09-23　【醒来时间】07:12（推测 REM 窗口，仅供备注）\n'
        '【近期状态与补充说明（用户可选填写；也可能是对上次解析所提问题的回答）】（未填写）\n'
        '【历史梦境摘要（系统自动附最近 14 天，无则省略）】（无）\n'
        '【梦境口述原文】\n我梦见自己在飞。',
      );
    });

    test('空串/纯空白 directive 与 null 等价，不留多余空行', () {
      expect(withDirective('   '), withDirective(null));
    });

    test('★ 换界面语言 → user prompt 变 → 输入指纹必然跟着变', () {
      // 否则会出现"界面是英文、结论还是中文，而程序认为输入没变"这种静默的错配。
      final sys = builder.buildSystemPrompt();
      String fp(String? d) => joinFingerprint([sys, withDirective(d), 'gpt-x']);

      final zh = AppLocale.zhCN.analysisLanguageDirective;
      final en = AppLocale.en.analysisLanguageDirective;
      final tw = AppLocale.zhTW.analysisLanguageDirective;
      expect(fp(zh), isNot(fp(en)));
      expect(fp(zh), isNot(fp(tw)));
      expect(fp(en), isNot(fp(tw)));
      expect(fp(en), fp(en)); // 同一语言重复算必须一致
    });

    test('★ 指令必须显式豁免「引用原文」的字段（否则引用会被一起翻译/转形）', () {
      // 来历（2026-09-24 第二轮实测，deepseek-v4-pro、zhTW）：第一版措辞写的是
      // 「本次回答的**所有字段**一律只使用繁體中文」——模型真的照做了，
      // 连 `evidence` 这种**必须逐字复制原文**的字段也一并从简体转成了繁体，
      // 于是用户拿这句"原文"回原文里**搜不到**（本产品立身之本被静默破坏）；
      // `imagery[].token` 同样被转形（当时**没有判据**，所以完全隐形）；
      // `emotions_explicit` 干脆被清空成 []。整个界面看起来完全正常。
      // 所以：论述性字段跟随界面语言，引用型字段必须**逐字保留原文原样**。
      for (final l in [AppLocale.zhTW, AppLocale.en]) {
        final d = l.analysisLanguageDirective!;
        for (final field in ['evidence', 'imagery', 'emotions_explicit']) {
          expect(d, contains(field), reason: '$l 的指令必须点名豁免字段 $field');
        }
        // 必须同时保留"跟随界面语言"的强措辞，否则会退回"半生效"
        // （headline 换了语言、正文还是中文——比完全失败更阴险）。
        expect(d, anyOf(contains('一律只使用'), contains('highest priority'), contains('最高優先級'),
            contains('最高优先级')));
      }
    });
  });
}

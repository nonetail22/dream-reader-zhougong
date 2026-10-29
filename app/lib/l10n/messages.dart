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

import 'app_locale.dart';

/// 应用文案表。
///
/// 纯 Dart（只依赖 [AppLocale]），不 import 任何 Flutter 包，
/// 这样 `dart test` 也能直接测（见 `test/l10n_test.dart`）。
///
/// 用法：
/// ```dart
/// final s = AppL10n(AppLocale.en);
/// s.tr('save');                       // 'Save'
/// s.tr('usage_files', {'total':'10MB','count':'3'}); // 占位符 {total}/{count}
/// ```
///
/// 约定：
/// - key 用 snake_case，全小写；缺失 key 会回退到简体中文，仍缺失则**原样返回 key**
///   （避免界面出现空白，但也意味着漏翻会在 UI 上露出 key 名——`l10n_test` 负责兜底）。
/// - 占位符用 `{name}`，替换时按名匹配。
class AppL10n {
  const AppL10n(this.locale);

  final AppLocale locale;

  /// 无 BuildContext 处（如 [AppController] 里的错误文案）用的当前语言单例。
  /// 切换语言时由 [setLocale 路径] 与 [AppL10nDelegate.load] 同步更新。
  static AppL10n current = const AppL10n(AppLocale.zhCN);

  String tr(String key, [Map<String, String>? args]) {
    final table = _bundle[locale] ?? _bundle[AppLocale.zhCN]!;
    var s = table[key] ?? _bundle[AppLocale.zhCN]![key] ?? key;
    if (args != null) {
      for (final e in args.entries) {
        s = s.replaceAll('{${e.key}}', e.value);
      }
    }
    return s;
  }
}

/// 三语文案表。顺序：简体中文 / 繁體中文 / English。
///
/// **新增任何用户可见字符串都必须在这里补三条**，否则 `l10n_test` 红灯。
const Map<AppLocale, Map<String, String>> _bundle = {
  AppLocale.zhCN: _zhCN,
  AppLocale.zhTW: _zhTW,
  AppLocale.en: _en,
};

/// 某语言下已定义的全部 key（仅供 `test/l10n_test.dart` 校验三语完整性）。
///
/// 三张表必须**键集完全相同**：漏一条，那个语言下就会在界面上直接露出 key 名。
Set<String> l10nKeysOf(AppLocale locale) =>
    (_bundle[locale] ?? const <String, String>{}).keys.toSet();

const Map<String, String> _zhCN = {
  // ── 底部导航 ──
  'nav_record': '记录',
  'nav_dreams': '梦境',
  'nav_settings': '设置',

  // ── 设置页：分组与状态 ──
  'grp_speech': '语音识别方式',
  'grp_cloud': '云端转写（BYOK）',
  'grp_recordings': '录音文件',
  'grp_model': '模型 API · 解析用',
  'grp_palette': '夜间配色',
  'grp_about': '关于与说明',
  'status_about': '社区版 · AGPL-3.0 开源',
  'status_not_configured': '未配置 · 解析不可用',
  'asr_badge_needed_fail': '未配置 · 当前识别会失败',
  'asr_badge_not_needed': '未配置 · 当前不需要',

  // ── 设置页：模型 API ──
  'llm_intro_native':
      '自带 API Key 使用解析功能：你的梦境文本只发送给你自己配置的服务商，本应用不转发、不留存。'
      'Key 只保存在本机的系统安全存储（iOS Keychain / Android Keystore）。',
  'llm_intro_web':
      '自带 API Key 使用解析功能：你的梦境文本只发送给你自己配置的服务商，本应用不转发、不留存。'
      'Key 只保存在本机（网页版为浏览器 localStorage，安全性弱于手机端）。',
  'label_api_key': 'API Key（本地 Ollama 可留空）',
  'label_model': '模型名',
  'stream_title': '使用流式接口',
  'stream_sub': '部分通道（如内测官方通道）仅支持流式返回',
  'saved_snack': '已保存（仅存本机）',

  // ── 设置页：关于 ──
  'about_version': '版本',
  'about_text':
      'Dream Reader · 周公解梦版 · 开源（AGPL-3.0）\n'
      '解析引擎：以古传周公解梦体系（周公解梦流传本 / 梦林玄解 / 敦煌本梦书）取义，'
      '每条结论标注典籍出处与置信度（A 文本可见 / B 典籍明载 / C 权且一说），'
      '多解并陈、吉凶不定命。\n\n'
      '所有解析结果均由 AI 生成，仅供娱乐参考，不构成任何预言、占卜、医学或心理学建议，'
      '不能替代专业心理帮助。若梦境长期困扰你，请寻求专业人士支持。',

  // ── 设置页：识别方式 ──
  'speech_intro':
      '把口述变成文字有三条路。它们没有哪条绝对更好，取舍不一样——'
      '下面把每条路的实际情况逐项列出来，你挑一条自己愿意接受代价的。'
      '随时可以改，改完立刻生效。',
  'checking': '正在检查…',
  'ready_cloud': '已就绪：录音会发往 {endpoint}',
  'system_unknown':
      '要真正按一次才知道——这条路依赖设备自带服务，无法事先探测。',

  // ── 设置页：录音文件 ──
  'recordings_intro':
      '录音是转录文字唯一的原始证据：识别把哪句听错了，回听一下就知道。'
      '所有录音都只存在这台设备上，不上传、也不参与解析。',
  'keep_rec_title': '识别完保留录音',
  'keep_rec_sub_needed':
      '当前方式本来就要先录一段音频（识别需要它），这里决定识别完留不留。'
      '默认保留 —— 想核对识别听错了哪里时，它是唯一的依据。关掉则识别完立刻删掉，不占地方。',
  'keep_rec_sub_system':
      '当前是系统识别，音频不由本应用产生，所以这一项现在不起作用；'
      '想在这种方式下也留一份录音，用下面那一项。',
  'also_rec_title': '系统识别时同时录一份',
  'also_rec_sub_system':
      '默认关闭。打开后本应用会占住麦克风，系统语音识别可能一个字都收不到，'
      '而且不会报错 —— 这是「说了话却什么都没识别出来」的根因。'
      '只有在你更看重回听、愿意拿转写换的时候才打开。',
  'also_rec_sub_other':
      '默认关闭。这一项只在「系统识别」方式下起作用，当前方式用不到它。'
      '它会让本应用占住麦克风、把系统识别静音，所以不能默认打开。',
  'usage_empty': '本机还没有留下录音',
  'usage_files': '已占 {total} · {count} 个文件',
  'usage_over_line':
      '已经超过 {bytes} 的提醒线。清不清由你决定，本应用不会自动删任何录音。',
  'usage_warn_line':
      '提醒线 {bytes}（约 {span} 的录音）。到线只提醒，不自动删。',
  'usage_orphans':
      '其中 {count} 个（{size}）没有任何记录引用，多半是上次没识别成功的残留。',
  'manage_recordings': '管理录音',
  'manager_title': '管理录音',
  'manager_count': '共 {count} 个文件，合计 {total}。',
  'manager_no_orphans': '没有记录引用的录音：一个都没有。',
  'manager_orphans_title': '没有记录引用的录音（{count} 个，{size}）',
  'manager_orphans_intro':
      '这些音频没有任何记录指向它们，多半是上次识别失败留下的。'
      '删之前可以先听一遍 —— 万一是你话说到一半被打断的那段。',
  'confirm_purge_title': '清掉这 {count} 个录音？',
  'confirm_purge_body':
      '它们不会被任何记录用到，删掉不影响任何梦境。但删了就找不回来 —— '
      '本应用里没有回收站，这些音频也没有别处的备份。',
  'confirm_purge_label': '清掉',
  'purge_all_section': '全部录音',
  'purge_all_intro': '删掉全部录音不会动任何文字和解析结论，只是以后不能再回听。这一步不可撤销。',
  'purge_all_title': '删掉本机全部录音？',
  'purge_all_body': '共 {count} 个文件、{total}。梦的文字和解析会全部保留，但录音删掉就找不回来了。',
  'purge_all_label': '全部删掉',
  'deleted_n': '已删掉 {n} 个录音文件',

  // ── 设置页：云端转写 ──
  'asr_enabled_intro':
      '录音会「上传」到你填的这家服务商换取文字。这是三条路里唯一会让录音离开设备的一条。'
      '本应用不做中转、不落档：音频直接从这台设备发往下面这个地址。',
  'asr_disabled_intro':
      '当前没在用云端转写。填好下面三项后，到上面的「语音识别方式」里选「云端转写」即可启用。',
  'asr_warn_upload': '注意：这段梦的录音会离开这台设备。只有你自己填的那家服务商能看到它。',
  'asr_safe_key': 'Key 只存在本机安全存储里，不会上传到任何地方。',
  'asr_only_two':
      '只列了两家我确认过接口形状的（读官方文档核对过地址与模型名）。'
      '其他家只要兼容 OpenAI 的 POST /v1/audio/transcriptions 也能用，'
      '地址照它的填——注意填到 /v1 为止，后面的路径由 App 补。',
  'label_asr_model': '转写模型名',
  'asr_actual': '实际请求：POST {endpoint}',

  // ── 设置页：夜间配色 ──
  'palette_intro': '凌晨醒来时看这个界面，亮色会刺眼。选一套自己最舒服的，点一下立刻生效。',
  'palette_current': '当前：{label} · {note}',

  // ── 记录页 ──
  'rec_title': '点一下开始，说完再点一下',
  'rec_title_broken': '写下刚才的梦',
  'rec_hint':
      '醒来后尽快开口，细节流失很快。说错、说乱都没关系，中间想停多久都行。\n{mode}',
  'rec_hint_broken':
      '这台设备没有可用的系统语音识别服务。可以点大按钮写下来，'
      '或换成离线识别——它不依赖设备自带能力，也不需要联网。',
  'mood_label': '醒来第一感觉',
  'editing_bar_text': '正在改原文，改完点右边「完成」',
  'editing_done': '完成',
  'box_editable': '识别结果（可直接修改）',
  'box_listening': '你口述的内容',
  'box_hint': '（这里会显示你口述的内容，识别完还能直接改）',
  'restore_raw': '还原成识别结果',
  'stale_title': '原文已经改过了，下面那条解析结论是按改之前的原文得出的，已经对不上。',
  'stale_reparse': '用新原文重新解析',
  'caption_working': '正在识别…',
  'caption_broken': '点一下写下来',
  'caption_recording': '正在录音 {clock} — 再点一下结束',
  'caption_idle': '点一下开始说话',
  'box_working': '正在识别…',
  'box_recording_offline': '正在录音 {clock}…\n说完再点一下按钮，中间可以慢慢想。',
  'box_recording_system': '正在聆听 {clock}…\n说完再点一下按钮。',
  'saved_no_model': '已保存。配置模型 API 后即可解析（设置 → 模型 API）',
  'offline_switched': '已改成离线识别：不联网、录音不出设备',
  'manual_input_title': '手动输入梦境',
  'manual_input_hint': '趁还记得，把梦写下来。写得乱、写得跳都没关系。',
  'retry_recognize': '重试识别（录音还在，不用重说）',
  'view_analysis': '查看解析',
  'analyze_confirm_title': '是否解析这段梦境？',
  'analyze_confirm_body': '解析会调用你配置的模型，可能需要几分钟，且会消耗 API 额度。若想先修改文本，可点空白处关闭，改完后再在「查看解析」里解析。',
  'analyze_confirm_yes': '是，立即解析',
  'analyze_confirm_no': '否，去梦境列表',
  'analyze_started': '已开始解析，可在梦境列表查看进度',
  'switch_offline': '改用离线识别（不依赖设备，不联网）',
  'retry_system': '再试一次系统识别',
  'manual_input_btn': '手动输入',
  'transcript_edit_hint': '（识别听错的地方，改成你真正的意思）',
  'mic_error': '开不了麦克风：{e}',
  'stop_rec_fail': '结束录音失败：{e}',
  'no_file': '这段录音没有落成文件，没法识别。可以再说一次。',
  'too_short': '这段只有 {secs} 秒，太短了，没听到内容。点一下按钮重新说一次就好。',
  'no_content': '没有识别到内容，麦克风可能没收到声音。',
  'no_content_tip': '可以再说一次，或用下面的「手动输入」。',
  'silent_error_main':
      '这段录音里没听到你说话，就没送去识别。\n'
      '识别模型遇到没人说话的录音不会返回空，而是会编出像模一样的一句话 —— '
      '与其给你一句编的，不如直说没听到。\n点一下按钮重新说一次就好。',
  'silent_error_kept':
      '（这段录音已经留下来了，到「设置 → 录音文件」里可以回听）',
  'lowconf_warn':
      '这段音频里几乎听不到人声，上面的内容可能是识别错误 —— 请核对，不对就删掉重录或手写。',
  'recognize_empty':
      '没有识别出内容。可能是刚才声音太轻、离麦克风太远。可以点「重试识别」，或再说一次。',
  'recognize_failed': '识别失败：{e}',
  'transcriber_not_ready': '「{label}」还不能用。',

  // ── 时间线页 ──
    'timeline_empty': '还没有记录。\n回到「记录」页，点一下按钮说一句就行。',
  'timeline_search_hint': '搜索梦境内容…',
  'timeline_filter_all': '全部',
  'timeline_filter_unanalyzed': '未解析',
  'timeline_filter_analyzed': '已解析',
  'timeline_filter_stale': '结论过期',
  'timeline_filter_failed': '解析失败',
  'timeline_no_match': '没有符合条件的记录。\n换个关键字或筛选条件试试。',
  'warn_banner_main': '录音已经占了 {total}（{count} 个文件）。',
  'warn_banner_tip':
      '想腾点空间就到「设置 → 录音文件 → 管理录音」里清。本应用不会自动删你的录音。',
  'warn_dismiss': '知道了',
  'status_analyzed': '已解析',
  'status_failed': '解析失败',
  'status_stale': '需重新解析',
  'status_only_record': '仅记录',
  'edit_original': '修改原文',
  'delete_record_title': '删除这条记录？',
  'delete_record_body_has_audio':
      '删除后不可恢复（记录只存在本机）。这条记录的录音文件会一起删掉。',
  'delete_record_body': '删除后不可恢复（记录只存在本机）。',

  // ── 详情页 ──
  'not_found': '记录已不存在',
  'section_transcript': '梦境原文',
  'edited_note': '这段原文你手动改过（识别器原本听成的是另一段）。',
  'audio_evidence': '录音 · 原文的原始证据',
  'audio_note': '录音只存在这台设备上，也不参与解析。删掉它不影响下面的文字与结论。',
  'tags_title': '标签 · 会一起送给解析',
  'mood_label_dtl': '醒来第一感觉',
  'flag_label_dtl': '这条梦还有什么特点（可多选）',
  'flag_note':
      '「反复出现的梦」解析会专门用上。多轮闭环实测里两个模型都主动追问过'
      '“这是不是反复出现的梦”——与其让它每轮都问，不如一次把答案给它。',
  'reanalyze_tooltip': '重新解析（会覆盖当前结论）',
  'analyze_cta_btn': '开始解析',
  'analyze_cta_supplement': '补充近期状态（可选，会更准）',
  'analyze_cta_note': '解析会把你口述的文本发送到你配置的模型服务商（BYOK）。',
  'supplement_title': '补充说明',
  'supplement_intro':
      '可以回答上面的提问，也可以随手写写最近的状态。这些内容会跟梦一起发给模型，'
      '用来判断哪些是最近的事、哪些是长期的议题。',
  'supplement_hint': '例如：最近在等一个工作结果，睡得不太踏实。',
  'supplement_save_only': '只保存',
  'supplement_save_analyze': '保存并解析',
  'tag_saved': '标签已保存。当前这条解析用的是改动前的输入。',
  'reanalyze_same_title': '这条已经解析过了',
  'reanalyze_diff_title': '重新解析这条梦？',
  'reanalyze_same_body':
      '这条梦解析用到的输入——原文、标签、近期状态、模型、解析框架、最近梦境摘要——'
      '都和上次一模一样，重新解析大概率得到与现在相同的结论。\n\n'
      '继续会覆盖当前这条结论，并再消耗一次模型调用（BYOK 用你自己的额度）。',
  'reanalyze_diff_body':
      '重新解析会覆盖当前这条结论，并再消耗一次模型调用（BYOK 用你自己的额度）。\n\n'
      '解析用到的某一份输入（原文、标签、近期状态、模型、解析框架，或最近梦境摘要）'
      '和上次不一样了，所以这次结论会变化。',
  'reanalyze_confirm_same': '仍然重新解析',
  'reanalyze_confirm_diff': '重新解析',
  'parsing_title': '正在解析…',
  'parsing_hint':
      '正在调用你配置的模型生成解析，可能需要 1 到 15 分钟（推理型模型更慢）。'
      '你可以先返回梦境列表，解析完成后回到这里就能看到结果。',
  'reparse_failed_banner':
      '本次重新解析失败：{reason}（上一次的解析结果没有被覆盖，下面仍显示之前得出的结论）',
  'reparse_failed_unknown': '原因未记录',
  'status_parsing': '解析中',
  'delete_audio_title': '删除这条录音？',
  'delete_audio_body':
      '删掉就找不回来了。这条梦的文字和解析不受影响，只是以后不能再回听，'
      '也没法拿原话去核对识别错在哪。',
  'delete_audio_btn': '删除录音',
  'trauma_note':
      '本次梦境呈现值得关注的重复/创伤性特征。若持续出现并影响白天状态，'
      '建议咨询专业心理人士。本应用不提供诊断，也不替代专业帮助。',
  'reading_title': '这个梦可能在说',
  'mood_overall': '整体情绪：{mood}',
  'section_itemized': '逐条解读',
  'fragment_note': '本条为碎片记录，解析引擎按规则降级处理（不做强行解读）。',
  'section_terms': '术语白话对照（{n} 个）',
  'section_questions': '想更准一点，可以补这几件事',
  'no_questions_title': '这次没有需要你补充的',
  'no_questions_body':
      '现有的材料已经够支撑上面的结论，暂时没有需要你回答的问题。'
      '如果你自己又想起什么，随时可以点「补充说明」再解析一次。',
  'section_advice': '建议',
  'disclaimer':
      '所有解析结果均由 AI 依古传解梦体系生成，仅供娱乐参考，不构成任何预言、占卜、医学或心理学建议，不能替代专业心理帮助。',
  'conf_A': 'A·文本可见',
  'conf_B': 'B·典籍明载',
  'conf_C': 'C·权且一说',
  'evidence': '原文："{ev}"',
  'fold_basis': '这一条的依据',

  // ── 修改原文对话框 ──
  'edit_title': '修改梦境原文',
  'edit_intro': '语音识别难免有错字、漏字。改完以你写的为准。',
  'edit_hint': '把这段梦改准确。写得乱、写得跳都没关系。',
  'edit_will_reanalyze':
      '这条已经有解析结论了。原文改动之后，旧结论就对不上原文了，建议保存后重新解析一次。',
  'restore': '还原识别结果',

  // ── 录音播放条 ──
  'audio_missing': '录音文件已经不在本机了（可能被清理过）。',
  'remove_from_record': '从记录里去掉',
  'play_tooltip': '播放',
  'pause_tooltip': '暂停',
  'delete_audio_tooltip': '删除这条录音',
  'play_failed': '播放失败：{e}',

  // ── 通用 ──
  'cancel': '取消',
  'delete': '删除',
  'save': '保存',

  // ── 补全的遗漏键（转换时新发现、原表未覆盖）──
  'usage_local_status': '本机占用 {total}',
  'mgr_empty': '本机还没有留下任何录音。',
  'purge_orphans_btn': '清掉这 {count} 个',
  'purge_all_btn': '删掉本机全部录音',
  'status_folding': '正在收起录音…',
  'rec_stop_label': '结束录音',
  'rec_start_label': '开始录音',
  'write_down_label': '写下来',
  'reanswer_reanalyze': '补充说明并重新解析',
  'grp_language': '界面语言',
  'language_intro': '选择 App 显示的语言。梦境解析的内容也会跟随这里的选择。',
  'tag_saved_hint': '标签已保存。这条的解析用的是改动前的输入，可在「查看解析」里用新标签重新解析。',
  'span_minutes': '{n} 分钟',
  'span_hours': '{n} 小时',
  'preset_zhipu': '智谱 GLM',
  'preset_deepseek': 'DeepSeek',
  'preset_qwen': '通义千问（百炼）',
  'preset_kimi': 'Kimi（月之暗面）',
  'preset_siliconflow_llm': '硅基流动',
  'preset_openai': 'OpenAI',
  'preset_gemini': 'Google Gemini',
  'preset_openrouter': 'OpenRouter',
  'preset_custom': '自定义',
  'preset_label': '供应商预设',
  'preset_ollama_local': '本地 Ollama',
  'preset_siliconflow': '硅基流动 SenseVoice',

  // ── 语音识别方式（service 层文案）──
  'speech_system_label': '系统语音识别',
  'speech_system_tagline': '边说边出字，不多占安装包',
  'speech_system_caveat':
      '国产 ROM（华为鸿蒙等）通常没带可用的识别服务，点下去不会有任何反应。'
      '真用不了时，App 会提示你换成「离线识别」。',
  'speech_offline_label': '离线识别（推荐）',
  'speech_offline_tagline': '说完后出字，全程不联网，音频不出设备',
  'speech_offline_caveat': '首次使用需联网下载模型（约 320MB，只此一次），以及不是边说边出字——说完了才出。',
  'speech_cloud_label': '云端转写（自带 Key）',
  'speech_cloud_tagline': '准确率最高，但录音要上传到你自己配置的服务商',
  'speech_cloud_caveat':
      '选它就意味着这段梦的录音会被上传。App 不做任何中转，'
      'Key 与音频都只发给你自己填的那家服务商。',

  'speech_dim_timing': '出字时机',
  'speech_dim_audio': '音频去向',
  'speech_dim_network': '要不要联网',
  'speech_dim_cost': '花钱吗',
  'speech_dim_prereq': '前提',

  'speech_system_timing': '说话时逐字出现，说完时就已经是一整段',
  'speech_system_audio': '不出设备。由系统自带的识别服务在本机处理',
  'speech_system_network': '看机型。不少机型其实是把音频交给云端识别，断网就不出字',
  'speech_system_cost': '不花钱，也不消耗任何额度',
  'speech_system_prereq': '这台设备自带可用的语音识别服务',

  'speech_offline_timing': '说完后等一会儿再整段出现；长录音会按段提示进度，耗时与设备有关',
  'speech_offline_audio': '不出设备。识别在本机内存里算完，不留档、不上传',
  'speech_offline_network': '完全不需要。飞行模式、地下室、没信号都能用',
  'speech_offline_cost': '不花钱，也不消耗任何额度',
  'speech_offline_prereq': '需先联网下载模型（约 320MB，下载一次后离线可用）',

  'speech_cloud_timing': '说完后等一小会儿（看网速，通常 1~3 秒）',
  'speech_cloud_audio': '会上传到你填的服务商。这是唯一一条音频离开设备的路',
  'speech_cloud_network': '必须联网，没网就一定失败',
  'speech_cloud_cost': '按你服务商的计费走，一般每分钟几分钱到几毛钱',
  'speech_cloud_prereq': '要填服务商的 Base URL、API Key 和转写模型名',

  // ── 结构化标签 ──
  'mood_calm': '平静',
  'mood_uneasy': '不安',
  'mood_joyful': '喜悦',
  'mood_sad': '悲伤',
  'mood_tired': '疲惫',
  'mood_unclear': '说不清',
  'flag_nightmare': '噩梦',
  'flag_recurring': '反复出现的梦',
  'flag_deceased': '梦里有已故的人',
  'prompt_mood_prefix': '醒来第一感觉：{m}',
  'prompt_flags_prefix': '用户自行标注：{fs}',
  'prompt_tags_wrapper':
      '【本次记录的标签（由用户自己醒后立刻标注，是事实而非推断，'
      '可直接用于判断情绪基调与梦系列归属，但不得当作梦境原文引用）】',

  // ── 语音识别错误码 ──
  'err_speech_permission': '没有语音识别权限。请到系统设置里允许本应用使用麦克风。',
  'err_speech_busy': '麦克风被占用了（本应用的录音，或别的 App 正在用），识别服务拿不到声音。',
  'err_speech_audio': '麦克风采集失败。最常见的原因是同一时刻有别的功能也在录音。',
  'err_speech_network': '系统语音识别需要联网，当前网络不可用。',
  'err_speech_language': '这台设备没有安装中文语音识别包。',
  'err_speech_timeout': '没有听到声音——可能是麦克风根本没收到音频，也可能说话太轻。',
  'err_speech_no_match': '听到了声音，但没能识别成文字。',
  'err_speech_disabled': '系统语音识别被关闭了，请到系统设置里开启。',
  'err_speech_service': '系统语音识别服务异常（{raw}）。',
  'err_speech_unknown': '语音识别出错：{raw}',

  // ── 系统转写器 / 录音 / 离线模型 ──
  'err_system_transcriber_unavailable': '这台设备上用不了系统语音识别。',
  'err_system_transcriber_hint':
      '原因：{detail}\n'
      'Android 的语音识别通常由 Google 语音服务提供；部分国产系统默认不带 Google 服务，'
      '系统就无法转写。建议到「设置 → 语音识别方式」改成「离线识别」——'
      '那条路不依赖设备自带服务，也不需要联网。',
  'err_system_reason_unknown': '系统未提供可用的语音识别服务',
  'err_recorder_permission': '未获得麦克风权限，请到系统设置中允许本应用使用麦克风',
  'audio_format_wav_note': 'wav（16kHz 单声道，识别用）',
  'audio_format_m4a_note': 'm4a（压缩，体积小）',
  'offline_model_name': 'Paraformer 中文大模型',
  'offline_model_size': '约 320MB',
  'transcriber_offline_label': '离线识别',

  // ── 模型 API 调用失败 ──
  'err_llm_timeout_hint_reasoning': '所选模型是推理型，它通常要先想很久再给结果，慢多半来自模型本身。',
  'err_llm_timeout_hint_fast': '可以稍后重试，或换一个更快的模型。',
  'err_llm_timeout': '等模型响应超过 {minutes} 分钟，已放弃。{hint}',
  'err_llm_transport':
      '和模型服务之间的连接被中断了，这次没拿到结果。'
      '这不是 Key 或配置的问题（多半是网络波动，或服务端主动切断了这条长连接）；'
      '可以直接重试一次。',
  'err_llm_invoke': '调用模型服务时出错：{e}',
  'err_llm_no_content': '响应中没有可用的 content 字段',
  'err_llm_empty_stream': '流式响应未取到任何内容',

  // ── 云端转写 HTTP 失败 ──
  'err_asr_400': '服务商说请求不对（400）。多半是模型名填错了，或者这家不认这种音频格式。{detail}',
  'err_asr_401': 'API Key 不对或已失效（401）。到「设置 → 云端转写」重新填一次。',
  'err_asr_402': '服务商那边余额/额度不够了（402）。充值或换一家即可。',
  'err_asr_403': '这家服务商拒绝了这次调用（403）。可能是 Key 没有转写权限，或该模型未开通。',
  'err_asr_404':
      '这个地址上没有转写接口（404）。检查 Base URL：'
      '多数服务商是 `https://…/v1`，不是 `/v1/chat/completions` 那一串。',
  'err_asr_413': '录音太大了（413）。这条梦说得比较久，可以分两次说。',
  'err_asr_429': '请求太频繁被限流了（429）。等一会儿再试，或换一家服务商。',
  'err_asr_5xx': '服务商那边出错了（{status}），不是你的配置问题。等一会儿再试。',
  'err_asr_default': '转写请求失败（HTTP {status}）。{detail}',
  'err_asr_server_quote': '\n服务商原话：{snippet}',

  // ── 离线识别（sherpa_onnx_transcriber）的就绪/状态/错误文案 ──
  'err_offline_web': '网页版没有离线识别。想不联网用，请装手机版。',
  'err_offline_platform': '离线识别目前只在 Android / iOS 上提供。',
  'err_offline_no_dir': '这台设备上建不出模型目录：{e}',
  'offline_ready': '已就绪：{name}（{size}）已在本机，识别时会加载进内存',
  'offline_first_prepare': '模型还没下载到本机（{name}，{size}）。需要联网下载一次，之后识别全程离线、音频不出设备',
  'offline_dl_title': '下载离线识别模型',
  'offline_dl_body': '{name} 约 {size}，下载一次后识别全程离线、音频不出设备。建议在 Wi-Fi 下进行。',
  'offline_dl_confirm': '下载（约 {size}）',
  'offline_dl_cancel': '先不下载',
  'offline_dl_progress': '正在下载 {pct}%',
  'offline_dl_cancelled': '模型还没就绪，这次没有识别。下载完成后再点重试，或改用其他识别方式。',
  'offline_dl_failed': '下载失败：{e}\n请检查网络后重试。',
  'offline_need_download': '离线模型还没下载到本机（到「设置 → 语音识别方式」里下载）。',
  'retranscribe_button': '重新识别文字',
  'retranscribe_title': '重新识别这段录音？',
  'retranscribe_body': '将用当前语音识别方式重新转写，并覆盖现有文字；已有的解析会标记为「过期」，之后可再点重新解析。',
  'retranscribe_confirm': '重新识别',
  'retranscribe_running_title': '正在重新识别…',
  'retranscribe_running_hint': '长录音按段识别，百分比持续推进；空白段自动跳过。',
  'retranscribe_empty': '没有识别出文字（可能是纯空白录音）。现有文字未改动。',
  'retranscribe_failed': '重新识别失败：{e}\n现有文字未改动。',
  'retranscribe_done': '识别完成，文字已更新。已有解析标记为过期，可点「重新解析」。',
  'retranscribe_no_file': '录音文件已不在本机（可能被清理），无法重新识别。',
  'err_offline_no_samples': '这段录音解不出声音数据，没法离线识别。',
  'err_offline_no_samples_hint':
      '文件情况：{header}\n可以再说一次；如果反复出现，请把上面这行反馈给开发者。',
  'err_offline_failed': '离线识别出错：{e}',
  'err_offline_failed_hint':
      '这一条不需要联网，所以多半是模型文件或音频格式的问题。可以到「设置 → 语音识别方式」切到「云端转写」，或手动输入。',
  'offline_loading': '正在加载识别模型…',
  'offline_recognizing_progress': '正在识别 {pct}%…',
  'err_header_missing': '文件不存在：{path}',
  'err_header_failed': '读文件头失败：{e}',
  'header_bytes': '{size} 字节',
  'header_channels': '{n} 声道',
  'err_no_model_config': '尚未配置模型 API（到「设置」中填写 BYOK 配置，或选择本地 Ollama）',

  // ── 夜间配色的名字与说明（键由 DreamPalette.id 决定）──
  'palette_dawn_label': '浅色',
  'palette_dawn_note': '原来的样子 · 白天用',
  'palette_deep_blue_label': '深蓝夜',
  'palette_deep_blue_note': '保住蓝紫调性 · 默认',
  'palette_pure_black_label': '真黑',
  'palette_pure_black_note': 'OLED 最省电 · 最暗',
  'palette_warm_amber_label': '暖棕烛光',
  'palette_warm_amber_note': '蓝光最少 · 最护眼',
  'palette_red_shift_label': '暗红夜视',
  'palette_red_shift_note': '几乎零蓝光 · 保夜间视力',
  'palette_system_label': '跟随系统',
  'palette_system_note': '夜间暖棕烛光 · 白天浅色',
};

const Map<String, String> _zhTW = {
  'nav_record': '記錄',
  'nav_dreams': '夢境',
  'nav_settings': '設定',

  'grp_speech': '語音辨識方式',
  'grp_cloud': '雲端轉寫（BYOK）',
  'grp_recordings': '錄音檔案',
  'grp_model': '模型 API · 解析用',
  'grp_palette': '夜間配色',
  'grp_about': '關於與說明',
  'status_about': '社群版 · AGPL-3.0 開源',
  'status_not_configured': '未設定 · 解析不可用',
  'asr_badge_needed_fail': '未設定 · 當前辨識會失敗',
  'asr_badge_not_needed': '未設定 · 當前不需要',

  'llm_intro_native':
      '自帶 API Key 使用解析功能：你的夢境文本只發送給你自己設定的服務商，本應用不轉發、不留存。'
      'Key 只保存在本機的系統安全儲存（iOS Keychain / Android Keystore）。',
  'llm_intro_web':
      '自帶 API Key 使用解析功能：你的夢境文本只發送給你自己設定的服務商，本應用不轉發、不留存。'
      'Key 只保存在本機（網頁版為瀏覽器 localStorage，安全性弱於手機端）。',
  'label_api_key': 'API Key（本地 Ollama 可留空）',
  'label_model': '模型名',
  'stream_title': '使用串流介面',
  'stream_sub': '部分通道（如內測官方通道）僅支援串流回傳',
  'saved_snack': '已儲存（僅存本機）',

  'about_version': '版本',
  'about_text':
      'Dream Reader · 周公解夢版 · 開源（AGPL-3.0）\n'
      '解析引擎：以古傳周公解夢體系（周公解夢流傳本 / 夢林玄解 / 敦煌本夢書）取義，'
      '每條結論標註典籍出處與置信度（A 文本可見 / B 典籍明載 / C 權且一說），'
      '多解並陳、吉凶不定命。\n\n'
      '所有解析結果均由 AI 生成，僅供娛樂參考，不構成任何預言、占卜、醫學或心理學建議，'
      '不能替代專業心理幫助。若夢境長期困擾你，請尋求專業人士支持。',

  'speech_intro':
      '把口述變成文字有三條路。它們沒有哪一條絕對更好，取捨不一樣——'
      '下面把每一條路的實際情況逐項列出來，你挑一條自己願意接受代價的。'
      '隨時可以改，改完立刻生效。',
  'checking': '確認中…',
  'ready_cloud': '已就緒：錄音會發往 {endpoint}',
  'system_unknown':
      '要真正按一次才知道——這條路依賴裝置自帶服務，無法事先探測。',

  'recordings_intro':
      '錄音是轉錄文字唯一的原始證據：辨識把哪句聽錯了，回聽一下就知道。'
      '所有錄音都只存在這台裝置上，不上傳、也不參與解析。',
  'keep_rec_title': '辨識完保留錄音',
  'keep_rec_sub_needed':
      '當前方式本來就要先錄一段音訊（辨識需要它），這裡決定辨識完留不留。'
      '預設保留 —— 想核對辨識聽錯了哪裡時，它是唯一的依據。關掉則辨識完立刻刪掉，不佔地方。',
  'keep_rec_sub_system':
      '當前是系統辨識，音訊不由本應用產生，所以這一項現在不起作用；'
      '想在這種方式下也留一份錄音，用下面那一項。',
  'also_rec_title': '系統辨識時同時錄一份',
  'also_rec_sub_system':
      '預設關閉。打開後本應用會佔住麥克風，系統語音辨識可能一個字都收不到，'
      '而且不會報錯 —— 這是「說了話卻什麼都沒辨識出來」的根因。'
      '只有在你更看重回聽、願意拿轉寫換的時候才打開。',
  'also_rec_sub_other':
      '預設關閉。這一項只在「系統辨識」方式下起作用，當前方式用不到它。'
      '它會讓本應用佔住麥克風、把系統辨識靜音，所以不能預設打開。',
  'usage_empty': '本機還沒有留下錄音',
  'usage_files': '已佔 {total} · {count} 個檔案',
  'usage_over_line':
      '已經超過 {bytes} 的提醒線。清不清由你決定，本應用不會自動刪任何錄音。',
  'usage_warn_line':
      '提醒線 {bytes}（約 {span} 的錄音）。到線只提醒，不自動刪。',
  'usage_orphans':
      '其中 {count} 個（{size}）沒有任何記錄引用，多半是上次沒辨識成功的殘留。',
  'manage_recordings': '管理錄音',
  'manager_title': '管理錄音',
  'manager_count': '共 {count} 個檔案，合計 {total}。',
  'manager_no_orphans': '沒有記錄引用的錄音：一個都沒有。',
  'manager_orphans_title': '沒有記錄引用的錄音（{count} 個，{size}）',
  'manager_orphans_intro':
      '這些音訊沒有任何記錄指向它們，多半是上次辨識失敗留下的。'
      '刪之前可以先聽一遍 —— 萬一是你話說到一半被打斷的那段。',
  'confirm_purge_title': '清掉這 {count} 個錄音？',
  'confirm_purge_body':
      '它們不會被任何記錄用到，刪掉不影響任何夢境。但刪了就找不回來 —— '
      '本應用裡沒有資源回收桶，這些音訊也沒有別處的備份。',
  'confirm_purge_label': '清掉',
  'purge_all_section': '全部錄音',
  'purge_all_intro':
      '刪掉全部錄音不會動任何文字和解析結論，只是以後不能再回聽。這一步不可撤銷。',
  'purge_all_title': '刪掉本機全部錄音？',
  'purge_all_body':
      '共 {count} 個檔案、{total}。夢的文字和解析會全部保留，但錄音刪掉就找不回來了。',
  'purge_all_label': '全部刪掉',
  'deleted_n': '已刪掉 {n} 個錄音檔案',

  'asr_enabled_intro':
      '錄音會「上傳」到你填的這家服務商換取文字。這是三條路裡唯一會讓錄音離開裝置的一條。'
      '本應用不做中轉、不落檔：音訊直接從這台裝置發往下面這個地址。',
  'asr_disabled_intro':
      '當前沒在用雲端轉寫。填好下面三項後，到上面的「語音辨識方式」裡選「雲端轉寫」即可啟用。',
  'asr_warn_upload': '注意：這段夢的錄音會離開這台裝置。只有你自己填的那家服務商能看到它。',
  'asr_safe_key': 'Key 只存在本機安全儲存裡，不會上傳到任何地方。',
  'asr_only_two':
      '只列了兩家我確認過介面形狀的（讀官方文件核對過地址與模型名）。'
      '其他家只要相容 OpenAI 的 POST /v1/audio/transcriptions 也能用，'
      '地址照它的填——注意填到 /v1 為止，後面的路徑由 App 補。',
  'label_asr_model': '轉寫模型名',
  'asr_actual': '實際請求：POST {endpoint}',

  'palette_intro': '凌晨醒來時看這個介面，亮色會刺眼。選一套自己最舒服的，點一下立刻生效。',
  'palette_current': '當前：{label} · {note}',

  'rec_title': '點一下開始，說完再點一下',
  'rec_title_broken': '寫下剛才的夢',
  'rec_hint':
      '醒來後盡快開口，細節流失很快。說錯、說亂都沒關係，中間想停多久都行。\n{mode}',
  'rec_hint_broken':
      '這台裝置沒有可用的系統語音辨識服務。可以點大按鈕寫下來，'
      '或換成離線辨識——它不依賴裝置自帶能力，也不需要聯網。',
  'mood_label': '醒來第一感覺',
  'editing_bar_text': '正在改原文，改完點右邊「完成」',
  'editing_done': '完成',
  'box_editable': '辨識結果（可直接修改）',
  'box_listening': '你口述的內容',
  'box_hint': '（這裡會顯示你口述的內容，辨識完還能直接改）',
  'restore_raw': '還原成辨識結果',
  'stale_title': '原文已經改過了，下面那條解析結論是按改之前的原文得出的，已經對不上。',
  'stale_reparse': '用新原文重新解析',
  'caption_working': '正在辨識…',
  'caption_broken': '點一下寫下來',
  'caption_recording': '正在錄音 {clock} — 再點一下結束',
  'caption_idle': '點一下開始說話',
  'box_working': '正在辨識…',
  'box_recording_offline': '正在錄音 {clock}…\n說完再點一下按鈕，中間可以慢慢想。',
  'box_recording_system': '正在聆聽 {clock}…\n說完再點一下按鈕。',
  'saved_no_model': '已儲存。設定模型 API 後即可解析（設定 → 模型 API）',
  'offline_switched': '已改成離線辨識：不聯網、錄音不出裝置',
  'manual_input_title': '手動輸入夢境',
  'manual_input_hint': '趁還記得，把夢寫下來。寫得亂、寫得跳都沒關係。',
  'retry_recognize': '重試辨識（錄音還在，不用重說）',
  'view_analysis': '查看解析',
  'analyze_confirm_title': '是否解析這段夢境？',
  'analyze_confirm_body': '解析會呼叫你設定的模型，可能需要幾分鐘，且會消耗 API 額度。若想先修改文字，可點空白處關閉，改完後再於「查看解析」裡解析。',
  'analyze_confirm_yes': '是，立即解析',
  'analyze_confirm_no': '否，去夢境清單',
  'analyze_started': '已開始解析，可在夢境清單查看進度',
  'switch_offline': '改用離線辨識（不依賴裝置，不聯網）',
  'retry_system': '再試一次系統辨識',
  'manual_input_btn': '手動輸入',
  'transcript_edit_hint': '（辨識聽錯的地方，改成你真正的意思）',
  'mic_error': '開不了麥克風：{e}',
  'stop_rec_fail': '結束錄音失敗：{e}',
  'no_file': '這段錄音沒有落成檔案，沒法辨識。可以再說一次。',
  'too_short': '這段只有 {secs} 秒，太短了，沒聽到內容。點一下按鈕重新說一次就好。',
  'no_content': '沒有辨識到內容，麥克風可能沒收到聲音。',
  'no_content_tip': '可以再說一次，或用下面的「手動輸入」。',
  'silent_error_main':
      '這段錄音裡沒聽到你說話，就沒送去辨識。\n'
      '辨識模型遇到沒人說話的錄音不會回傳空，而是會編出像模一樣的一句話 —— '
      '與其給你一句編的，不如直說沒聽到。\n點一下按鈕重新說一次就好。',
  'silent_error_kept':
      '（這段錄音已經留下來了，到「設定 → 錄音檔案」裡可以回聽）',
  'lowconf_warn':
      '這段音訊裡幾乎聽不到人聲，上面的內容可能是辨識錯誤 —— 請核對，不對就刪掉重錄或手寫。',
  'recognize_empty':
      '沒有辨識出內容。可能是剛才聲音太輕、離麥克風太遠。可以點「重試辨識」，或再說一次。',
  'recognize_failed': '辨識失敗：{e}',
  'transcriber_not_ready': '「{label}」還不能用。',

    'timeline_empty': '還沒有記錄。\n回到「記錄」頁，點一下按鈕說一句就行。',
  'timeline_search_hint': '搜尋夢境內容…',
  'timeline_filter_all': '全部',
  'timeline_filter_unanalyzed': '未解析',
  'timeline_filter_analyzed': '已解析',
  'timeline_filter_stale': '結論過期',
  'timeline_filter_failed': '解析失敗',
  'timeline_no_match': '沒有符合條件的記錄。\n換個關鍵字或篩選條件試試。',
  'warn_banner_main': '錄音已經佔了 {total}（{count} 個檔案）。',
  'warn_banner_tip':
      '想騰點空間就到「設定 → 錄音檔案 → 管理錄音」裡清。本應用不會自動刪你的錄音。',
  'warn_dismiss': '知道了',
  'status_analyzed': '已解析',
  'status_failed': '解析失敗',
  'status_stale': '需重新解析',
  'status_only_record': '僅記錄',
  'edit_original': '修改原文',
  'delete_record_title': '刪除這條記錄？',
  'delete_record_body_has_audio':
      '刪除後不可恢復（記錄只存在本機）。這條記錄的錄音檔案會一起刪掉。',
  'delete_record_body': '刪除後不可恢復（記錄只存在本機）。',

  'not_found': '記錄已不存在',
  'section_transcript': '夢境原文',
  'edited_note': '這段原文你手動改過（辨識器原本聽成的是另一段）。',
  'audio_evidence': '錄音 · 原文的原始證據',
  'audio_note': '錄音只存在這台裝置上，也不參與解析。刪掉它不影響下面的文字與結論。',
  'tags_title': '標籤 · 會一起送給解析',
  'mood_label_dtl': '醒來第一感覺',
  'flag_label_dtl': '這條夢還有什麼特點（可多選）',
  'flag_note':
      '「反覆出現的夢」解析會專門用上。多輪閉環實測裡兩個模型都主動追問過'
      '「這是不是反覆出現的夢」——與其讓它每輪都問，不如一次把答案給它。',
  'reanalyze_tooltip': '重新解析（會覆蓋當前結論）',
  'analyze_cta_btn': '開始解析',
  'analyze_cta_supplement': '補充近期狀態（可選，會更準）',
  'analyze_cta_note': '解析會把你口述的文本發送到你設定的模型服務商（BYOK）。',
  'supplement_title': '補充說明',
  'supplement_intro':
      '可以回答上面的提問，也可以隨手寫寫最近的狀態。這些內容會跟夢一起發給模型，'
      '用來判斷哪些是最近的事、哪些是長期的議題。',
  'supplement_hint': '例如：最近在等一個工作結果，睡得不太踏實。',
  'supplement_save_only': '只儲存',
  'supplement_save_analyze': '儲存並解析',
  'tag_saved': '標籤已儲存。當前這條解析用的是改動前的輸入。',
  'reanalyze_same_title': '這條已經解析過了',
  'reanalyze_diff_title': '重新解析這條夢？',
  'reanalyze_same_body':
      '這條夢解析用到的輸入——原文、標籤、近期狀態、模型、解析框架、最近夢境摘要——'
      '都和上次一模一樣，重新解析大機率得到與現在相同的結論。\n\n'
      '繼續會覆蓋當前這條結論，並再消耗一次模型呼叫（BYOK 用你自己的額度）。',
  'reanalyze_diff_body':
      '重新解析會覆蓋當前這條結論，並再消耗一次模型呼叫（BYOK 用你自己的額度）。\n\n'
      '解析用到的某一份輸入（原文、標籤、近期狀態、模型、解析框架，或最近夢境摘要）'
      '和上次不一樣了，所以這次結論會變化。',
  'reanalyze_confirm_same': '仍然重新解析',
  'reanalyze_confirm_diff': '重新解析',
  'parsing_title': '正在解析…',
  'parsing_hint':
      '正在呼叫你設定的模型產生解析，可能需要 1 到 15 分鐘（推理型模型更慢）。'
      '你可以先返回夢境清單，解析完成後回到這裡就能看到結果。',
  'reparse_failed_banner':
      '本次重新解析失敗：{reason}（上一次的解析結果沒有被覆蓋，下面仍顯示之前得出的結論）',
  'reparse_failed_unknown': '原因未記錄',
  'status_parsing': '解析中',
  'delete_audio_title': '刪除這條錄音？',
  'delete_audio_body':
      '刪掉就找不回來了。這條夢的文字和解析不受影響，只是以後不能再回聽，'
      '也沒法拿原話去核對辨識錯在哪。',
  'delete_audio_btn': '刪除錄音',
  'trauma_note':
      '本次夢境呈現值得關注的重複/創傷性特徵。若持續出現並影響白天狀態，'
      '建議諮詢專業心理人士。本應用不提供診斷，也不替代專業幫助。',
  'reading_title': '這個夢可能在說',
  'mood_overall': '整體情緒：{mood}',
  'section_itemized': '逐條解讀',
  'fragment_note': '本條為碎片記錄，解析引擎按規則降級處理（不做強行解讀）。',
  'section_terms': '術語白話對照（{n} 個）',
  'section_questions': '想更準一點，可以補這幾件事',
  'no_questions_title': '這次沒有需要你補充的',
  'no_questions_body':
      '現有的材料已經夠支撐上面的結論，暫時沒有需要你回答的問題。'
      '如果你自己又想起什麼，隨時可以點「補充說明」再解析一次。',
  'section_advice': '建議',
  'disclaimer':
      '所有解析結果均由 AI 依古傳解夢體系生成，僅供娛樂參考，不構成任何預言、占卜、醫學或心理學建議，不能替代專業心理幫助。',
  'conf_A': 'A·文本可見',
  'conf_B': 'B·典籍明載',
  'conf_C': 'C·權且一說',
  'evidence': '原文："{ev}"',
  'fold_basis': '這一條的依據',

  'edit_title': '修改夢境原文',
  'edit_intro': '語音辨識難免有錯字、漏字。改完以你寫的為準。',
  'edit_hint': '把這段夢改準確。寫得亂、寫得跳都沒關係。',
  'edit_will_reanalyze':
      '這條已經有解析結論了。原文改動之後，舊結論就對不上原文了，建議儲存後重新解析一次。',
  'restore': '還原辨識結果',

  'audio_missing': '錄音檔案已經不在本機了（可能被清理過）。',
  'remove_from_record': '從記錄裡去掉',
  'play_tooltip': '播放',
  'pause_tooltip': '暫停',
  'delete_audio_tooltip': '刪除這條錄音',
  'play_failed': '播放失敗：{e}',

  'cancel': '取消',
  'delete': '刪除',
  'save': '儲存',

  'usage_local_status': '本機佔用 {total}',
  'mgr_empty': '本機還沒有留下任何錄音。',
  'purge_orphans_btn': '清掉這 {count} 個',
  'purge_all_btn': '刪掉本機全部錄音',
  'status_folding': '正在收起錄音…',
  'rec_stop_label': '結束錄音',
  'rec_start_label': '開始錄音',
  'write_down_label': '寫下來',
  'reanswer_reanalyze': '補充說明並重新解析',
  'grp_language': '介面語言',
  'language_intro': '選擇 App 顯示的語言。夢境解析的內容也會跟隨這裡的選擇。',
  'tag_saved_hint': '標籤已儲存。這條的解析用的是改動前的輸入，可在「查看解析」裡用新標籤重新解析。',
  'span_minutes': '{n} 分鐘',
  'span_hours': '{n} 小時',
  'preset_zhipu': '智譜 GLM',
  'preset_deepseek': 'DeepSeek',
  'preset_qwen': '通義千問（百煉）',
  'preset_kimi': 'Kimi（月之暗面）',
  'preset_siliconflow_llm': '矽基流動',
  'preset_openai': 'OpenAI',
  'preset_gemini': 'Google Gemini',
  'preset_openrouter': 'OpenRouter',
  'preset_custom': '自訂',
  'preset_label': '供應商預設',
  'preset_ollama_local': '本機 Ollama',
  'preset_siliconflow': '硅基流動 SenseVoice',

  // ── 語音辨識方式（service 層文案）──
  'speech_system_label': '系統語音辨識',
  'speech_system_tagline': '邊說邊出字，不多佔安裝包',
  'speech_system_caveat':
      '國產 ROM（華為鴻蒙等）通常沒帶可用的辨識服務，點下去不會有任何反應。'
      '真用不了時，App 會提示你換成「離線辨識」。',
  'speech_offline_label': '離線辨識（推薦）',
  'speech_offline_tagline': '說完後出字，全程不聯網，音訊不出裝置',
  'speech_offline_caveat': '首次使用需連網下載模型（約 320MB，只此一次），以及不是邊說邊出字——說完了才出。',
  'speech_cloud_label': '雲端轉寫（自帶 Key）',
  'speech_cloud_tagline': '準確率最高，但錄音要上傳到你自己設定的服務商',
  'speech_cloud_caveat':
      '選它就意味著這段夢的錄音會被上傳。App 不做任何中轉，'
      'Key 與音訊都只發給你自己填的那家服務商。',

  'speech_dim_timing': '出字時機',
  'speech_dim_audio': '音訊去向',
  'speech_dim_network': '要不要聯網',
  'speech_dim_cost': '花錢嗎',
  'speech_dim_prereq': '前提',

  'speech_system_timing': '說話時逐字出現，說完時就已經是一整段',
  'speech_system_audio': '不出裝置。由系統自帶的辨識服務在本機處理',
  'speech_system_network': '看機型。不少機型其實是把音訊交給雲端辨識，斷網就不出字',
  'speech_system_cost': '不花錢，也不消耗任何額度',
  'speech_system_prereq': '這台裝置自帶可用的語音辨識服務',

  'speech_offline_timing': '說完後等一會兒再整段出現；長錄音會按段提示進度，耗時與裝置有關',
  'speech_offline_audio': '不出裝置。辨識在本機記憶體裡算完，不留檔、不上傳',
  'speech_offline_network': '完全不需要。飛航模式、地下室、沒訊號都能用',
  'speech_offline_cost': '不花錢，也不消耗任何額度',
  'speech_offline_prereq': '需先連網下載模型（約 320MB，下載一次後離線可用）',

  'speech_cloud_timing': '說完後等一小會兒（看網速，通常 1~3 秒）',
  'speech_cloud_audio': '會上傳到你填的服務商。這是唯一一條音訊離開裝置的路',
  'speech_cloud_network': '必須聯網，沒網就一定失敗',
  'speech_cloud_cost': '按你服務商的計費走，一般每分鐘幾分錢到幾毛錢',
  'speech_cloud_prereq': '要填服務商的 Base URL、API Key 和轉寫模型名',

  // ── 結構化標籤 ──
  'mood_calm': '平靜',
  'mood_uneasy': '不安',
  'mood_joyful': '喜悅',
  'mood_sad': '悲傷',
  'mood_tired': '疲憊',
  'mood_unclear': '說不清',
  'flag_nightmare': '噩夢',
  'flag_recurring': '反覆出現的夢',
  'flag_deceased': '夢裡有已故的人',
  'prompt_mood_prefix': '醒來第一感覺：{m}',
  'prompt_flags_prefix': '使用者自行標註：{fs}',
  'prompt_tags_wrapper':
      '【本次記錄的標籤（由使用者自己醒後立刻標註，是事實而非推斷，'
      '可直接用於判斷情緒基調與夢系列歸屬，但不得當作夢境原文引用）】',

  // ── 語音辨識錯誤碼 ──
  'err_speech_permission': '沒有語音辨識權限。請到系統設定裡允許本應用使用麥克風。',
  'err_speech_busy': '麥克風被佔用了（本應用的錄音，或別的 App 正在用），辨識服務拿不到聲音。',
  'err_speech_audio': '麥克風擷取失敗。最常見的原因是同一時刻有別的功能也在錄音。',
  'err_speech_network': '系統語音辨識需要聯網，當前網路不可用。',
  'err_speech_language': '這台裝置沒有安裝中文語音辨識包。',
  'err_speech_timeout': '沒有聽到聲音——可能是麥克風根本沒收到音訊，也可能說話太輕。',
  'err_speech_no_match': '聽到了聲音，但沒能辨識成文字。',
  'err_speech_disabled': '系統語音辨識被關閉了，請到系統設定裡開啟。',
  'err_speech_service': '系統語音辨識服務異常（{raw}）。',
  'err_speech_unknown': '語音辨識出錯：{raw}',

  // ── 系統轉寫器 / 錄音 / 離線模型 ──
  'err_system_transcriber_unavailable': '這台裝置上用不了系統語音辨識。',
  'err_system_transcriber_hint':
      '原因：{detail}\n'
      'Android 的語音辨識通常由 Google 語音服務提供；部分國產系統預設不帶 Google 服務，'
      '系統就無法轉寫。建議到「設定 → 語音辨識方式」改成「離線辨識」——'
      '那條路不依賴裝置自帶服務，也不需要聯網。',
  'err_system_reason_unknown': '系統未提供可用的語音辨識服務',
  'err_recorder_permission': '未獲得麥克風權限，請到系統設定中允許本應用使用麥克風',
  'audio_format_wav_note': 'wav（16kHz 單聲道，辨識用）',
  'audio_format_m4a_note': 'm4a（壓縮，體積小）',
  'offline_model_name': 'Paraformer 中文大模型',
  'offline_model_size': '約 320MB',
  'transcriber_offline_label': '離線辨識',

  // ── 模型 API 呼叫失敗 ──
  'err_llm_timeout_hint_reasoning': '所選模型是推理型，它通常要先想很久再給結果，慢多半來自模型本身。',
  'err_llm_timeout_hint_fast': '可以稍後重試，或換一個更快的模型。',
  'err_llm_timeout': '等模型回應超過 {minutes} 分鐘，已放棄。{hint}',
  'err_llm_transport':
      '和模型服務之間的連線被中斷了，這次沒拿到結果。'
      '這不是 Key 或設定的問題（多半是網路波動，或服務端主動切斷了這條長連線）；'
      '可以直接重試一次。',
  'err_llm_invoke': '呼叫模型服務時出錯：{e}',
  'err_llm_no_content': '回應中沒有可用的 content 欄位',
  'err_llm_empty_stream': '串流回應未取到任何內容',

  // ── 雲端轉寫 HTTP 失敗 ──
  'err_asr_400': '服務商說請求不對（400）。多半是模型名填錯了，或者這家不認這種音訊格式。{detail}',
  'err_asr_401': 'API Key 不對或已失效（401）。到「設定 → 雲端轉寫」重新填一次。',
  'err_asr_402': '服務商那邊餘額/額度不夠了（402）。儲值或換一家即可。',
  'err_asr_403': '這家服務商拒絕了這次呼叫（403）。可能是 Key 沒有轉寫權限，或該模型未開通。',
  'err_asr_404':
      '這個地址上沒有轉寫介面（404）。檢查 Base URL：'
      '多數服務商是 `https://…/v1`，不是 `/v1/chat/completions` 那一串。',
  'err_asr_413': '錄音太大了（413）。這條夢說得比較久，可以分兩次說。',
  'err_asr_429': '請求太頻繁被限流了（429）。等一會兒再試，或換一家服務商。',
  'err_asr_5xx': '服務商那邊出錯了（{status}），不是你的設定問題。等一會兒再試。',
  'err_asr_default': '轉寫請求失敗（HTTP {status}）。{detail}',
  'err_asr_server_quote': '\n服務商原話：{snippet}',

  'err_offline_web': '網頁版沒有離線辨識。想不連網用，請裝手機版。',
  'err_offline_platform': '離線辨識目前只在 Android / iOS 上提供。',
  'err_offline_no_dir': '這台裝置上建不出模型目錄：{e}',
  'offline_ready': '已就緒：{name}（{size}）已在本機，辨識時會載入記憶體',
  'offline_first_prepare': '模型還沒下載到本機（{name}，{size}）。需要連網下載一次，之後辨識全程離線、音訊不出裝置',
  'offline_dl_title': '下載離線辨識模型',
  'offline_dl_body': '{name} 約 {size}，下載一次後辨識全程離線、音訊不出裝置。建議在 Wi-Fi 下進行。',
  'offline_dl_confirm': '下載（約 {size}）',
  'offline_dl_cancel': '先不下載',
  'offline_dl_progress': '正在下載 {pct}%',
  'offline_dl_cancelled': '模型還沒就緒，這次沒有辨識。下載完成後再點重試，或改用其他辨識方式。',
  'offline_dl_failed': '下載失敗：{e}\n請檢查網路後重試。',
  'offline_need_download': '離線模型還沒下載到本機（到「設定 → 語音辨識方式」裡下載）。',
  'retranscribe_button': '重新辨識文字',
  'retranscribe_title': '重新辨識這段錄音？',
  'retranscribe_body': '將用目前語音辨識方式重新轉寫，並覆蓋現有文字；已有的解析會標記為「過期」，之後可再點重新解析。',
  'retranscribe_confirm': '重新辨識',
  'retranscribe_running_title': '正在重新辨識…',
  'retranscribe_running_hint': '長錄音按段辨識，百分比持續推進；空白段自動跳過。',
  'retranscribe_empty': '沒有辨識出文字（可能是純空白錄音）。現有文字未改動。',
  'retranscribe_failed': '重新辨識失敗：{e}\n現有文字未改動。',
  'retranscribe_done': '辨識完成，文字已更新。已有解析標記為過期，可點「重新解析」。',
  'retranscribe_no_file': '錄音檔案已不在本機（可能被清理），無法重新辨識。',
  'err_offline_no_samples': '這段錄音解不出聲音資料，沒法離線辨識。',
  'err_offline_no_samples_hint':
      '檔案情況：{header}\n可以再說一次；如果反覆出現，請把上面這行回報給開發者。',
  'err_offline_failed': '離線辨識出錯：{e}',
  'err_offline_failed_hint':
      '這一條不需要連網，所以多半是模型檔案或音訊格式的問題。可以到「設定 → 語音辨識方式」切到「雲端轉寫」，或手動輸入。',
  'offline_loading': '正在載入辨識模型…',
  'offline_recognizing_progress': '正在辨識 {pct}%…',
  'err_header_missing': '檔案不存在：{path}',
  'err_header_failed': '讀取檔案標頭失敗：{e}',
  'header_bytes': '{size} 位元組',
  'header_channels': '{n} 聲道',
  'err_no_model_config': '尚未設定模型 API（到「設定」中填寫 BYOK 設定，或選擇本機 Ollama）',

  'palette_dawn_label': '淺色',
  'palette_dawn_note': '原來的樣子 · 白天用',
  'palette_deep_blue_label': '深藍夜',
  'palette_deep_blue_note': '保住藍紫調性 · 預設',
  'palette_pure_black_label': '真黑',
  'palette_pure_black_note': 'OLED 最省電 · 最暗',
  'palette_warm_amber_label': '暖棕燭光',
  'palette_warm_amber_note': '藍光最少 · 最護眼',
  'palette_red_shift_label': '暗紅夜視',
  'palette_red_shift_note': '幾乎零藍光 · 保夜間視力',
  'palette_system_label': '跟隨系統',
  'palette_system_note': '夜間暖棕燭光 · 白天淺色',
};

const Map<String, String> _en = {
  'nav_record': 'Record',
  'nav_dreams': 'Dreams',
  'nav_settings': 'Settings',

  'grp_speech': 'Speech method',
  'grp_cloud': 'Cloud transcription (BYOK)',
  'grp_recordings': 'Recordings',
  'grp_model': 'Model API (for analysis)',
  'grp_palette': 'Night theme',
  'grp_about': 'About',
  'status_about': 'Community · AGPL-3.0 open source',
  'status_not_configured': 'Not set · analysis unavailable',
  'asr_badge_needed_fail': 'Not set · recognition will fail',
  'asr_badge_not_needed': 'Not set · not needed now',

  'llm_intro_native':
      'Bring your own API key to use analysis: your dream text is sent only to the '
      'provider you configure; this app never forwards or stores it. The key lives only '
      'in this device’s secure storage (iOS Keychain / Android Keystore).',
  'llm_intro_web':
      'Bring your own API key to use analysis: your dream text is sent only to the '
      'provider you configure; this app never forwards or stores it. The key lives only '
      'on this device (the web build uses browser localStorage, which is weaker than the phone).',
  'label_api_key': 'API Key (leave empty for local Ollama)',
  'label_model': 'Model name',
  'stream_title': 'Use streaming API',
  'stream_sub': 'Some channels (e.g. the beta official channel) only support streaming.',
  'saved_snack': 'Saved (stored on this device only)',

  'about_version': 'Version',
  'about_text':
      'Dream Reader Community · open source (AGPL-3.0)\n'
      'Engine: a psychoanalytic framework (Freud / Jung / Hall–Van de Castle coding). '
      'Every conclusion is tagged with its theoretical basis and confidence '
      '(A visible in text / B theoretical inference / C open hypothesis).\n\n'
      'All analysis is AI-generated, for entertainment only, and is not medical or '
      'psychological advice. It cannot replace professional help. If dreams keep troubling '
      'you, please reach out to a professional.',

  'speech_intro':
      'There are three ways to turn speech into text. None is absolutely better — they '
      'trade off differently. The real facts about each are listed below; pick the one '
      'whose trade-offs you can accept. You can change it anytime; it takes effect immediately.',
  'checking': 'Checking…',
  'ready_cloud': 'Ready: audio will be sent to {endpoint}',
  'system_unknown':
      'You’ll only know by trying — this path relies on the device’s built-in service and '
      'can’t be probed in advance.',

  'recordings_intro':
      'The recording is the only raw evidence for the transcript: replay it to see exactly '
      'which line the recognizer heard wrong. All recordings stay on this device only — '
      'never uploaded, never used for analysis.',
  'keep_rec_title': 'Keep recording after recognition',
  'keep_rec_sub_needed':
      'This method already needs the audio (recognition requires it); this switch decides '
      'whether to keep it afterward. Kept by default — it’s the only way to check what the '
      'recognizer misheard. Turn it off to delete immediately after recognition.',
  'keep_rec_sub_system':
      'You’re on system recognition, whose audio isn’t produced by this app, so this switch '
      'does nothing now. To also keep a copy under system recognition, use the option below.',
  'also_rec_title': 'Also record during system recognition',
  'also_rec_sub_system':
      'Off by default. Turning it on makes this app grab the microphone, so system speech '
      'recognition may receive nothing — and it fails silently. That’s the root cause of '
      '“I spoke but nothing was recognized.” Only enable it if replay matters more to you '
      'than transcription.',
  'also_rec_sub_other':
      'Off by default. This only applies to the “system recognition” method, not the current '
      'one. It would make this app grab the microphone and mute system recognition, so it '
      'can’t be on by default.',
  'usage_empty': 'No recordings stored on this device yet',
  'usage_files': 'Using {total} · {count} files',
  'usage_over_line':
      'Already over the {bytes} reminder line. It’s your call whether to clear; this app '
      'won’t auto-delete any recording.',
  'usage_warn_line':
      'Reminder line {bytes} (about {span} of audio). We only remind at the line, never auto-delete.',
  'usage_orphans':
      'Of these, {count} ({size}) are referenced by no record — likely leftovers from a '
      'failed recognition.',
  'manage_recordings': 'Manage recordings',
  'manager_title': 'Manage recordings',
  'manager_count': 'Total {count} files, {total}.',
  'manager_no_orphans': 'No recordings without a referencing record — none at all.',
  'manager_orphans_title': 'Recordings with no referencing record ({count}, {size})',
  'manager_orphans_intro':
      'No record points to these audio files; they’re mostly leftovers from a failed '
      'recognition. You can listen before deleting — in case it’s the half-finished sentence '
      'you were cut off mid-way through.',
  'confirm_purge_title': 'Clear these {count} recordings?',
  'confirm_purge_body':
      'No record uses them, so deleting won’t affect any dream. But it can’t be undone — '
      'this app has no trash, and these files aren’t backed up anywhere else.',
  'confirm_purge_label': 'Clear',
  'purge_all_section': 'All recordings',
  'purge_all_intro':
      'Deleting all recordings touches no text or analysis conclusions; you just can’t replay '
      'afterward. This step is irreversible.',
  'purge_all_title': 'Delete all recordings on this device?',
  'purge_all_body':
      'Total {count} files, {total}. Dream text and analysis are fully kept; only the audio '
      'is gone for good.',
  'purge_all_label': 'Delete all',
  'deleted_n': 'Deleted {n} recording file(s)',

  'asr_enabled_intro':
      'The recording is “uploaded” to the provider you fill in, in exchange for text. This is '
      'the only path where audio leaves the device. This app does no relay and keeps no copy: '
      'audio goes straight from this device to the address below.',
  'asr_disabled_intro':
      'Cloud transcription isn’t in use right now. Fill in the three fields below, then pick '
      '“Cloud transcription” under “Speech method” above to enable it.',
  'asr_warn_upload':
      'Note: this dream’s recording will leave this device. Only the provider you filled in '
      'can see it.',
  'asr_safe_key': 'The key lives only in this device’s secure storage and is never uploaded.',
  'asr_only_two':
      'Only two providers whose interface shape I’ve verified (address and model name checked '
      'against official docs) are listed. Any other provider compatible with OpenAI’s '
      'POST /v1/audio/transcriptions also works — fill its address, but stop at /v1; the app '
      'appends the rest of the path.',
  'label_asr_model': 'Transcription model',
  'asr_actual': 'Actual request: POST {endpoint}',

  'palette_intro':
      'Bright themes are harsh when you wake at dawn. Pick the one that feels best; tap to '
      'apply instantly.',
  'palette_current': 'Current: {label} · {note}',

  'rec_title': 'Tap to start, tap again when done',
  'rec_title_broken': 'Write down the dream',
  'rec_hint':
      'Speak as soon as you wake — details fade fast. It’s fine to stumble or ramble; pause '
      'as long as you like.\n{mode}',
  'rec_hint_broken':
      'This device has no usable system speech recognition. Tap the big button to write it '
      'down, or switch to offline recognition — it needs neither the device service nor the network.',
  'mood_label': 'How you felt waking',
  'editing_bar_text': 'Editing the transcript — tap “Done” when finished',
  'editing_done': 'Done',
  'box_editable': 'Recognition result (editable)',
  'box_listening': 'What you said',
  'box_hint': '(Your speech shows here, and stays editable after recognition.)',
  'restore_raw': 'Restore recognized text',
  'stale_title':
      'The transcript was edited, so the analysis below — derived from the old transcript — '
      'no longer matches.',
  'stale_reparse': 'Re-analyze with new transcript',
  'caption_working': 'Recognizing…',
  'caption_broken': 'Tap to write it down',
  'caption_recording': 'Recording {clock} — tap again to stop',
  'caption_idle': 'Tap to start speaking',
  'box_working': 'Recognizing…',
  'box_recording_offline':
      'Recording {clock}…\nTap the button again when done; take your time to think in between.',
  'box_recording_system': 'Listening {clock}…\nTap the button again when done.',
  'saved_no_model':
      'Saved. Configure a model API to analyze (Settings → Model API).',
  'offline_switched':
      'Switched to offline recognition: no network, audio stays on device',
  'manual_input_title': 'Type your dream',
  'manual_input_hint':
      'Write the dream down while you still remember. Messy or scattered is fine.',
  'retry_recognize': 'Retry recognition (audio kept, no need to re-record)',
  'view_analysis': 'View analysis',
  'analyze_confirm_title': 'Analyze this dream now?',
  'analyze_confirm_body': 'Analysis calls your configured model and may take a few minutes and use API credits. To edit the text first, tap outside to dismiss and analyze later from “View analysis”.',
  'analyze_confirm_yes': 'Yes, analyze now',
  'analyze_confirm_no': 'No, go to dreams',
  'analyze_started': 'Analysis started — track progress in your dreams list',
  'switch_offline': 'Switch to offline recognition (device-independent, no network)',
  'retry_system': 'Try system recognition again',
  'manual_input_btn': 'Type instead',
  'transcript_edit_hint': '(Fix wherever the recognizer heard wrong.)',
  'mic_error': 'Can’t open the microphone: {e}',
  'stop_rec_fail': 'Failed to stop recording: {e}',
  'no_file': 'This recording didn’t become a file, so it can’t be recognized. Please try again.',
  'too_short':
      'That was only {secs} seconds — too short, nothing was heard. Just tap the button and say it again.',
  'no_content': 'Nothing was recognized; the microphone may not have picked up sound.',
  'no_content_tip': 'Try again, or use “Type instead” below.',
  'silent_error_main':
      'No speech was heard in this recording, so it wasn’t sent for recognition.\n'
      'A recognition model given silence won’t return empty — it fabricates a plausible sentence. '
      'Better to tell you straight that nothing was heard.\nTap the button and say it again.',
  'silent_error_kept':
      '(This recording was kept; you can replay it under Settings → Recordings.)',
  'lowconf_warn':
      'Almost no speech was heard in this audio; the text above may be a recognition error — '
      'please check it, and delete or re-record if it’s wrong.',
  'recognize_empty':
      'Nothing was recognized. Maybe the voice was too soft or too far from the mic. Tap '
      '“Retry recognition”, or say it again.',
  'recognize_failed': 'Recognition failed: {e}',
  'transcriber_not_ready': '“{label}” isn’t ready yet.',

    'timeline_empty': 'No records yet.\nGo to “Record” and tap the button to say a line.',
  'timeline_search_hint': 'Search dream text…',
  'timeline_filter_all': 'All',
  'timeline_filter_unanalyzed': 'Not analyzed',
  'timeline_filter_analyzed': 'Analyzed',
  'timeline_filter_stale': 'Stale',
  'timeline_filter_failed': 'Failed',
  'timeline_no_match': 'No records match.\nTry different keywords or filters.',
  'warn_banner_main': 'Recordings now take {total} ({count} files).',
  'warn_banner_tip':
      'To free space, go to Settings → Recordings → Manage recordings. This app never '
      'auto-deletes your recordings.',
  'warn_dismiss': 'Got it',
  'status_analyzed': 'Analyzed',
  'status_failed': 'Failed',
  'status_stale': 'Needs re-analysis',
  'status_only_record': 'Recorded only',
  'edit_original': 'Edit transcript',
  'delete_record_title': 'Delete this record?',
  'delete_record_body_has_audio':
      'This can’t be undone (records live only on this device). This record’s audio file is '
      'deleted along with it.',
  'delete_record_body': 'This can’t be undone (records live only on this device).',

  'not_found': 'Record no longer exists',
  'section_transcript': 'Dream transcript',
  'edited_note':
      'You edited this transcript by hand (the recognizer originally heard something else).',
  'audio_evidence': 'Audio · original evidence for the transcript',
  'audio_note':
      'The audio stays on this device and isn’t used for analysis. Deleting it doesn’t affect '
      'the text or conclusions below.',
  'tags_title': 'Tags · sent to analysis too',
  'mood_label_dtl': 'How you felt waking',
  'flag_label_dtl': 'What else about this dream (multi-select)',
  'flag_note':
      '“Recurring dreams” get special handling in analysis. In multi-turn tests both models '
      'asked “is this a recurring dream?” — better to give the answer once than have it ask '
      'every round.',
  'reanalyze_tooltip': 'Re-analyze (overwrites current conclusion)',
  'analyze_cta_btn': 'Start analysis',
  'analyze_cta_supplement': 'Add recent context (optional, more accurate)',
  'analyze_cta_note':
      'Analysis sends your spoken text to the model provider you configured (BYOK).',
  'supplement_title': 'Additional context',
  'supplement_intro':
      'Answer the questions above, or jot down recent state. This is sent to the model with '
      'the dream to tell recent events from long-term themes.',
  'supplement_hint': 'e.g. Waiting on a work result lately, not sleeping well.',
  'supplement_save_only': 'Save only',
  'supplement_save_analyze': 'Save & analyze',
  'tag_saved': 'Tags saved. The current analysis was made with the previous input.',
  'reanalyze_same_title': 'This one is already analyzed',
  'reanalyze_diff_title': 'Re-analyze this dream?',
  'reanalyze_same_body':
      'Every input used for this analysis — transcript, tags, recent context, model, analysis '
      'framework, recent dream digest — is identical to last time, so re-analysis will most '
      'likely return the same conclusion.\n\nContinuing overwrites the current conclusion and '
      'spends another model call (BYOK, billed to your own quota).',
  'reanalyze_diff_body':
      'Re-analyzing overwrites the current conclusion and spends another model call '
      '(BYOK, billed to your own quota).\n\nSome input (transcript, tags, recent context, '
      'model, framework, or recent digest) changed since last time, so the conclusion will differ.',
  'reanalyze_confirm_same': 'Re-analyze anyway',
  'reanalyze_confirm_diff': 'Re-analyze',
  'parsing_title': 'Analyzing…',
  'parsing_hint':
      'Calling your configured model to generate the analysis. This may take '
      '1–15 minutes (reasoning models are slower). You can go back to the dream '
      'list now — the result will be here when it finishes.',
  'reparse_failed_banner':
      'Latest re-analysis failed: {reason} (your previous analysis is unchanged; '
      'the conclusions below are from before).',
  'reparse_failed_unknown': 'reason not recorded',
  'status_parsing': 'Analyzing',
  'delete_audio_title': 'Delete this recording?',
  'delete_audio_body':
      'This can’t be undone. The dream’s text and analysis are unaffected — you just can’t '
      'replay, and can’t use the original to check where recognition went wrong.',
  'delete_audio_btn': 'Delete recording',
  'trauma_note':
      'This dream shows notable repetitive/traumatic features. If it keeps recurring and '
      'affects your daytime state, consider consulting a professional. This app offers no '
      'diagnosis and replaces no professional help.',
  'reading_title': 'This dream may be about',
  'mood_overall': 'Overall mood: {mood}',
  'section_itemized': 'Point-by-point interpretation',
  'fragment_note':
      'This is a fragment record; the engine degraded gracefully (no forced interpretation).',
  'section_terms': 'Terms in plain language ({n})',
  'section_questions': 'To get more precise, you can add these',
  'no_questions_title': 'Nothing more needed from you this time',
  'no_questions_body':
      'The material on hand is enough to support the conclusions above, so there are no '
      'questions to answer. If you think of anything else, tap “Additional context” to '
      're-analyze anytime.',
  'section_advice': 'Suggestions',
  'disclaimer':
      'All interpretations are AI-generated from the classical Zhou Gong dream '
      'tradition, for entertainment only. They are not prophecy, divination, '
      'medical or psychological advice, and cannot replace professional help.',
  'conf_A': 'A · visible in text',
  'conf_B': 'B · from classics',
  'conf_C': 'C · tentative',
  'evidence': 'Original: "{ev}"',
  'fold_basis': 'Basis for this point',

  'edit_title': 'Edit dream transcript',
  'edit_intro': 'Speech recognition makes mistakes. After editing, your text wins.',
  'edit_hint': 'Get this dream accurate. Messy or scattered is fine.',
  'edit_will_reanalyze':
      'This one already has an analysis. Once the transcript changes, the old conclusion no '
      'longer matches — save, then re-analyze.',
  'restore': 'Restore recognized text',

  'audio_missing':
      'The recording file is no longer on this device (may have been cleared).',
  'remove_from_record': 'Remove from record',
  'play_tooltip': 'Play',
  'pause_tooltip': 'Pause',
  'delete_audio_tooltip': 'Delete this recording',
  'play_failed': 'Playback failed: {e}',

  'cancel': 'Cancel',
  'delete': 'Delete',
  'save': 'Save',

  'usage_local_status': 'Using {total} on this device',
  'mgr_empty': 'No recordings stored on this device yet.',
  'purge_orphans_btn': 'Clear these {count}',
  'purge_all_btn': 'Delete all recordings on this device',
  'status_folding': 'Finishing recording…',
  'rec_stop_label': 'Stop recording',
  'rec_start_label': 'Start recording',
  'write_down_label': 'Write it down',
  'reanswer_reanalyze': 'Add context & re-analyze',
  'grp_language': 'Interface language',
  'language_intro': 'Choose the language this app displays. Dream analysis follows this choice too.',
  'tag_saved_hint':
      'Tags saved. This analysis used the previous input — re-analyze with the new tags under “View analysis”.',
  'span_minutes': '{n} min',
  'span_hours': '{n} hr',
  'preset_zhipu': 'Zhipu GLM',
  'preset_deepseek': 'DeepSeek',
  'preset_qwen': 'Qwen (DashScope)',
  'preset_kimi': 'Kimi (Moonshot)',
  'preset_siliconflow_llm': 'SiliconFlow',
  'preset_openai': 'OpenAI',
  'preset_gemini': 'Google Gemini',
  'preset_openrouter': 'OpenRouter',
  'preset_custom': 'Custom',
  'preset_label': 'Provider preset',
  'preset_ollama_local': 'Local Ollama',
  'preset_siliconflow': 'SiliconFlow SenseVoice',

  // ── Speech methods (service-layer copy) ──
  'speech_system_label': 'System speech recognition',
  'speech_system_tagline': 'Words appear as you speak, no extra app size',
  'speech_system_caveat':
      'Chinese OEM ROMs (Huawei HarmonyOS, etc.) usually ship no usable recognition service, '
      'so tapping does nothing. When it truly can’t work, the app will suggest switching to '
      '“Offline recognition”.',
  'speech_offline_label': 'Offline recognition (recommended)',
  'speech_offline_tagline':
      'Words appear once you finish, fully offline, audio never leaves the device',
  'speech_offline_caveat':
      'The cost: a one-time model download over the network at first use (~320 MB), '
      'and it is not live — text appears only once you finish.',
  'speech_cloud_label': 'Cloud transcription (bring your own key)',
  'speech_cloud_tagline':
      'Most accurate, but the recording is uploaded to the provider you configure',
  'speech_cloud_caveat':
      'Choosing it means this dream’s recording will be uploaded. The app does no relay: both '
      'the key and the audio go only to the provider you filled in.',

  'speech_dim_timing': 'When words appear',
  'speech_dim_audio': 'Where audio goes',
  'speech_dim_network': 'Network needed',
  'speech_dim_cost': 'Cost',
  'speech_dim_prereq': 'Requirement',

  'speech_system_timing':
      'Words appear one by one as you speak; a full paragraph by the time you finish',
  'speech_system_audio': 'Never leaves the device. Handled locally by the built-in recognizer',
  'speech_system_network':
      'Depends on the device. Many actually send audio to the cloud; no network, no words',
  'speech_system_cost': 'Free, and consumes no quota',
  'speech_system_prereq': 'This device has a usable built-in speech recognition service',

  'speech_offline_timing':
      'A wait after you finish, then the whole paragraph appears; long recordings '
      'show per-segment progress, and the time depends on the device',
  'speech_offline_audio':
      'Never leaves the device. Computed in local memory, kept nowhere, uploaded nowhere',
  'speech_offline_network':
      'Not needed at all. Works in airplane mode, basements, or with no signal',
  'speech_offline_cost': 'Free, and consumes no quota',
  'speech_offline_prereq': 'One-time model download required (~320 MB); fully offline afterwards',

  'speech_cloud_timing': 'A short wait after you finish (depends on speed, usually 1–3s)',
  'speech_cloud_audio':
      'Uploaded to the provider you filled in. The only path where audio leaves the device',
  'speech_cloud_network': 'Required; without a network it always fails',
  'speech_cloud_cost': 'Billed by your provider, typically a fraction of a cent per minute',
  'speech_cloud_prereq':
      'Fill in the provider’s Base URL, API Key, and transcription model name',

  // ── Structured tags ──
  'mood_calm': 'Calm',
  'mood_uneasy': 'Uneasy',
  'mood_joyful': 'Joyful',
  'mood_sad': 'Sad',
  'mood_tired': 'Tired',
  'mood_unclear': 'Unclear',
  'flag_nightmare': 'Nightmare',
  'flag_recurring': 'Recurring dream',
  'flag_deceased': 'A deceased person appears',
  'prompt_mood_prefix': 'First feeling on waking: {m}',
  'prompt_flags_prefix': 'User-tagged: {fs}',
  'prompt_tags_wrapper':
      '[Tags for this record (marked by the user right after waking; these are facts, not '
      'inferences. They may be used directly to judge the emotional tone and dream-series '
      'membership, but must never be cited as the dream transcript.)]',

  // ── Speech recognition error codes ──
  'err_speech_permission':
      'No speech recognition permission. Allow microphone access for this app in system settings.',
  'err_speech_busy':
      'The microphone is busy (this app’s recording, or another app), so the recognizer gets no sound.',
  'err_speech_audio':
      'Microphone capture failed. The usual cause is another feature recording at the same time.',
  'err_speech_network': 'System speech recognition needs a network, and none is available.',
  'err_speech_language': 'This device has no Chinese speech recognition package installed.',
  'err_speech_timeout':
      'No sound was heard — the microphone may have received nothing, or the speech was too soft.',
  'err_speech_no_match': 'Sound was heard, but it couldn’t be recognized as text.',
  'err_speech_disabled': 'System speech recognition is turned off; enable it in system settings.',
  'err_speech_service': 'The system speech recognition service failed ({raw}).',
  'err_speech_unknown': 'Speech recognition error: {raw}',

  // ── System transcriber / recorder / offline model ──
  'err_system_transcriber_unavailable':
      'System speech recognition isn’t available on this device.',
  'err_system_transcriber_hint':
      'Reason: {detail}\n'
      'Android speech recognition is usually provided by Google’s speech service; some Chinese '
      'OEM systems ship without Google services, so the system can’t transcribe. Switch to '
      '“Offline recognition” under Settings → Speech method — that path needs neither the device '
      'service nor the network.',
  'err_system_reason_unknown': 'The system provides no usable speech recognition service',
  'err_recorder_permission':
      'No microphone permission. Allow microphone access for this app in system settings.',
  'audio_format_wav_note': 'wav (16kHz mono, for recognition)',
  'audio_format_m4a_note': 'm4a (compressed, smaller)',
  'offline_model_name': 'Paraformer Chinese large model',
  'offline_model_size': 'about 320MB',
  'transcriber_offline_label': 'Offline recognition',

  // ── Model API call failures ──
  'err_llm_timeout_hint_reasoning':
      'The selected model is a reasoning model; it usually thinks for a long time before '
      'answering, so the slowness is mostly the model itself.',
  'err_llm_timeout_hint_fast': 'Retry later, or switch to a faster model.',
  'err_llm_timeout': 'Gave up after waiting over {minutes} minutes for the model. {hint}',
  'err_llm_transport':
      'The connection to the model service was interrupted, so no result came back. This isn’t '
      'a key or configuration problem (usually a network blip, or the server closing this '
      'long-lived connection); just retry once.',
  'err_llm_invoke': 'Error while calling the model service: {e}',
  'err_llm_no_content': 'The response had no usable content field',
  'err_llm_empty_stream': 'The streaming response produced no content',

  // ── Cloud transcription HTTP failures ──
  'err_asr_400':
      'The provider says the request is wrong (400). Usually a wrong model name, or this '
      'provider doesn’t accept this audio format.{detail}',
  'err_asr_401':
      'The API Key is wrong or expired (401). Re-enter it under Settings → Cloud transcription.',
  'err_asr_402': 'The provider is out of balance/quota (402). Top up or switch providers.',
  'err_asr_403':
      'The provider rejected this call (403). The key may lack transcription permission, or the '
      'model isn’t enabled.',
  'err_asr_404':
      'There’s no transcription endpoint at this address (404). Check the Base URL: most '
      'providers use `https://…/v1`, not the `/v1/chat/completions` string.',
  'err_asr_413': 'The recording is too large (413). This dream ran long; say it in two parts.',
  'err_asr_429': 'Too many requests, rate-limited (429). Wait a while, or switch providers.',
  'err_asr_5xx': 'The provider errored ({status}) — not your configuration. Try again later.',
  'err_asr_default': 'Transcription request failed (HTTP {status}).{detail}',
  'err_asr_server_quote': '\nProvider says: {snippet}',

  'err_offline_web':
      'Offline recognition is not available on the web. To use it without a network, install the phone app.',
  'err_offline_platform': 'Offline recognition is currently available only on Android / iOS.',
  'err_offline_no_dir': 'Could not create the model directory on this device: {e}',
  'offline_ready': 'Ready: {name} ({size}) is on this device and loads into memory when recognizing.',
  'offline_first_prepare':
      'The model is not downloaded yet ({name}, {size}). One download over the network is needed; recognition stays fully offline afterwards.',
  'offline_dl_title': 'Download the offline recognition model',
  'offline_dl_body':
      '{name} is about {size}. One download, then recognition runs fully offline and audio never leaves the device. Wi-Fi recommended.',
  'offline_dl_confirm': 'Download (~{size})',
  'offline_dl_cancel': 'Not now',
  'offline_dl_progress': 'Downloading {pct}%',
  'offline_dl_cancelled':
      'The model is not ready, so nothing was recognized this time. Retry after the download completes, or use another method.',
  'offline_dl_failed': 'Download failed: {e}\nCheck the network and retry.',
  'offline_need_download':
      'The offline model is not downloaded yet (download it under Settings → Speech method).',
  'retranscribe_button': 'Re-recognize text',
  'retranscribe_title': 'Re-recognize this recording?',
  'retranscribe_body':
      'The recording will be transcribed again with the current speech method, overwriting the existing text. Any existing analysis will be marked as outdated; you can re-analyze afterwards.',
  'retranscribe_confirm': 'Re-recognize',
  'retranscribe_running_title': 'Re-recognizing…',
  'retranscribe_running_hint':
      'Long recordings are recognized segment by segment with a live percentage; silent gaps are skipped automatically.',
  'retranscribe_empty':
      'No text was recognized (the recording may be pure silence). The existing text was left untouched.',
  'retranscribe_failed':
      'Re-recognition failed: {e}\nThe existing text was left untouched.',
  'retranscribe_done':
      'Done — text updated. Existing analysis is marked as outdated; tap “Re-analyze” to refresh it.',
  'retranscribe_no_file':
      'The audio file is no longer on this device (it may have been cleaned up).',
  'err_offline_no_samples':
      'This recording could not be decoded into audio data, so it cannot be recognized offline.',
  'err_offline_no_samples_hint':
      'File info: {header}\nYou can say it again; if this keeps happening, please report the line above to the developer.',
  'err_offline_failed': 'Offline recognition error: {e}',
  'err_offline_failed_hint':
      'This path needs no network, so it is most likely a model-file or audio-format problem. You can switch to “Cloud transcription” under Settings → Speech method, or type it in manually.',
  'offline_loading': 'Loading the recognition model…',
  'offline_recognizing_progress': 'Recognizing… {pct}%',
  'err_header_missing': 'File not found: {path}',
  'err_header_failed': 'Failed to read the file header: {e}',
  'header_bytes': '{size} bytes',
  'header_channels': '{n} ch',
  'err_no_model_config':
      'No model API configured yet (fill in your BYOK config under Settings, or choose local Ollama).',

  'palette_dawn_label': 'Light',
  'palette_dawn_note': 'The original look · for daytime',
  'palette_deep_blue_label': 'Deep blue night',
  'palette_deep_blue_note': 'Keeps the blue-violet tone · default',
  'palette_pure_black_label': 'True black',
  'palette_pure_black_note': 'Best for OLED · darkest',
  'palette_warm_amber_label': 'Warm candlelight',
  'palette_warm_amber_note': 'Least blue light · easiest on the eyes',
  'palette_red_shift_label': 'Dark red night',
  'palette_red_shift_note': 'Almost no blue light · preserves night vision',
  'palette_system_label': 'Follow system',
  'palette_system_note': 'Warm candlelight at night · light by day',
};

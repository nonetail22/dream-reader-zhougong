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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/app_version.dart';
import '../services/audio_store.dart';
import '../services/cloud_transcriber.dart';
import '../services/llm_client.dart';
import '../services/sherpa_onnx_transcriber.dart';
import '../services/speech_mode.dart';
import '../theme/palettes.dart';
import 'audio_player_bar.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_localizations.dart';
import 'offline_model_dialog.dart';
import '../l10n/messages.dart';

/// 解析 API 的**供应商预设**（0.7.4）。
///
/// 只是一组"开箱即用的 Base URL + 模型名"默认值，用户选定后仍可自由编辑
/// （换模型名、改代理地址都行）；都走 **OpenAI 兼容协议**（与 [LlmClient]
/// 一致），不兼容的供应商（如 Anthropic 原生 /v1/messages）不进这个列表。
/// 模型名取各家长销的稳定款，用户有更新的型号自己改输入框即可。
class _LlmPreset {
  const _LlmPreset(this.key, this.baseUrl, this.model);

  final String key; // i18n 键
  final String baseUrl;
  final String model;
}

const List<_LlmPreset> _llmPresets = [
  // ── 国内 ──
  _LlmPreset('preset_deepseek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
  _LlmPreset(
      'preset_zhipu', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
  _LlmPreset('preset_qwen', 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'qwen-plus'),
  _LlmPreset('preset_kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
  _LlmPreset('preset_siliconflow_llm', 'https://api.siliconflow.cn/v1',
      'deepseek-ai/DeepSeek-V3'),
  // ── 国际 ──
  _LlmPreset('preset_openai', 'https://api.openai.com/v1', 'gpt-4o'),
  _LlmPreset(
      'preset_gemini',
      'https://generativelanguage.googleapis.com/v1beta/openai',
      'gemini-2.0-flash'),
  _LlmPreset('preset_openrouter', 'https://openrouter.ai/api/v1',
      'openai/gpt-4o-mini'),
  // ── 本机 ──
  _LlmPreset('preset_ollama_local', 'http://localhost:11434/v1', 'qwen2.5:7b'),
];

/// 设置页。
///
/// 两个「自带凭据」的区块（解析用的模型 API、转写用的 ASR）都在这里，
/// 隐私承诺一致：**Key 只存本机，绝不上传**。原生平台落 Keychain/Keystore
/// （加密）；web 端只能落浏览器 localStorage，设置页据实告知，不暗示同等安全。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  bool _stream = false;
  bool _loaded = false;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController();
    _apiKey = TextEditingController();
    _model = TextEditingController();
  }

  void _loadFrom(AppController c) {
    if (_loaded) return;
    _baseUrl.text = c.config.baseUrl;
    _apiKey.text = c.config.apiKey;
    _model.text = c.config.model;
    _stream = c.config.stream;
    _loaded = true;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _applyPreset(String baseUrl, String model, {bool stream = false}) {
    setState(() {
      _baseUrl.text = baseUrl;
      _model.text = model;
      _stream = stream;
    });
  }

  /// 当前 Base URL + 模型与哪一家预设吻合；都不吻合（或还没填）→ 自定义。
  /// 每次构建现算而不是存状态：用户手改了输入框就自动落回「自定义」，
  /// 不会出现"明明改了 URL 下拉还停在 DeepSeek"的错位。
  String _currentPresetKey() {
    for (final p in _llmPresets) {
      if (_baseUrl.text.trim() == p.baseUrl && _model.text.trim() == p.model) {
        return p.key;
      }
    }
    return 'preset_custom';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    _loadFrom(c);
    final theme = Theme.of(context);

    // ── 分组顺序就是优先级，而且它是照着**产品自己的两半**分的 ──
    //
    // README 第一节把这件事写成一句话：「用户希望解决『梦境记录 + 专业解析』两件事」。
    // 那么设置页自然就该分成「让梦变成文字」和「让文字被读懂」两组，
    // 其余两组（外观、说明）是 App 级别的偏好。
    // 在那之前这里是 6 个板块用 `Divider` 平铺，于是**两大坨填 Key 的表单
    // （云端转写、模型 API）一直挡在前面**——而它们对多数人多数时候是无关的。
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SettingsGroup(
          icon: Icons.record_voice_over_outlined,
          title: context.l10n.tr('grp_speech'),
          status: c.speechMode.label,
          // 2026-09-26 改为**不默认展开**（用户要求）。
          //
          // 原先它是唯一默认展开的一组，理由是它决定"今天能不能把梦记下来"。
          // 收起来之后这个理由依然成立、也没有信息损失：折叠标题行本身就把
          // **当前方式**显示在 `status` 里（见 [_SettingsGroup.status] 的说明），
          // 不展开也知道现在用的是离线 / 系统 / 云端。
          //
          // ⚠️ 但要说清楚：**这次改动并没有修掉用户报的那个"第一次点会卡一下"**，
          // 只是把那次卡顿从"进设置页时自动触发"挪到了"用户第一次手动点开时"。
          // 那个卡顿是一次性的（之后就不卡），属于首次动画/着色器预热成本，
          // 真正定位它在 `validation/preview` 的渲染后端 A/B（0.5.3 vs 0.5.4）。
          // 别把这条当成"卡顿已修"。
          children: const [_SpeechSection()],
        ),
        _SettingsGroup(
          icon: Icons.cloud_upload_outlined,
          title: context.l10n.tr('grp_cloud'),
          status: _asrBadge(context, c),
          children: const [_AsrSection()],
        ),
        _SettingsGroup(
          icon: Icons.folder_outlined,
          title: context.l10n.tr('grp_recordings'),
          status: context.l10n
              .tr('usage_local_status', {'total': c.audioUsage.humanTotal}),
          children: const [_RecordingsSection()],
        ),
        _SettingsGroup(
          icon: Icons.auto_awesome_outlined,
          title: context.l10n.tr('grp_model'),
          status: c.config.isConfigured
              ? c.config.model
              : context.l10n.tr('status_not_configured'),
          children: _llmChildren(context, c, theme),
        ),
        _SettingsGroup(
          icon: Icons.nightlight_outlined,
          title: context.l10n.tr('grp_palette'),
          status: c.palette.label,
          children: const [_PalettePicker()],
        ),
        _SettingsGroup(
          icon: Icons.translate_outlined,
          title: context.l10n.tr('grp_language'),
          status: c.locale.label,
          children: const [_LocalePicker()],
        ),
        _SettingsGroup(
          icon: Icons.info_outline,
          title: context.l10n.tr('grp_about'),
          status: context.l10n.tr('status_about'),
          children: _aboutChildren(context, theme),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 云端转写那一组标题下的**现状行**（`_SettingsGroup` 的 `status`）。
  ///
  /// 三种状态必须**分开说**，因为它们的下一步动作完全不同：
  /// - 已配置 → 没什么要做的，就显示用的是哪个转写模型；
  /// - 没配、也不在用 → 告诉他"当前不需要"（别让他以为坏了）；
  /// - 没配、却正在用 → 这是**真的出问题了**，要说"当前识别会失败"。
  ///
  /// 三者混成一句"未配置"是最省事的写法，也是最坏的一种：第一种用户会以为没事，
  /// 第三种会以为只是还没填而已——**给一个错的原因，比给一句难懂的话更害人**
  /// （与第九节第 55 条同一条理由）。
  String _asrBadge(BuildContext context, AppController c) {
    if (c.asrConfig.isConfigured) return c.asrConfig.model;
    return c.speechMode == SpeechMode.cloud
        ? context.l10n.tr('asr_badge_needed_fail')
        : context.l10n.tr('asr_badge_not_needed');
  }

  /// 「模型 API · 解析用」组里的内容。
  ///
  /// 留在 State 里、而不是拆成一个独立 widget：这几个输入框的控制器、`_stream`、
  /// `_showKey` 全是页面状态，拆出去要透传五个参数，可读性反而更差。
  List<Widget> _llmChildren(
    BuildContext context,
    AppController c,
    ThemeData theme,
  ) {
    return [
      Text(
        kIsWeb
            ? context.l10n.tr('llm_intro_web')
            : context.l10n.tr('llm_intro_native'),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
      const SizedBox(height: 12),
      // 0.7.4：三个 ActionChip 换成**供应商预设下拉**（用户需求：覆盖国内
      // 外主流供应商 + 自定义）。预设只填 Base URL 与模型名，**不动 API Key**
      // ——Key 是每家自己的，选了新供应商后 Key 清空等用户填。
      // 受控的 DropdownButton + InputDecorator：value 每次构建都从输入框
      // 现算，选了预设/手改了字段都能正确反映。不用 DropdownButtonFormField
      // 的 initialValue——那是非受控的，预设应用后下拉不会跟着变。
      InputDecorator(
        decoration: InputDecoration(
          labelText: context.l10n.tr('preset_label'),
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _currentPresetKey(),
            isExpanded: true,
            isDense: true,
            items: [
              for (final p in _llmPresets)
                DropdownMenuItem(
                  value: p.key,
                  child: Text(context.l10n.tr(p.key)),
                ),
              DropdownMenuItem(
                value: 'preset_custom',
                child: Text(context.l10n.tr('preset_custom')),
              ),
            ],
            onChanged: (key) {
              if (key == null) return;
              final p = _llmPresets.where((x) => x.key == key).firstOrNull;
              if (p == null) {
                // 自定义：已填的内容一字不动，交给用户自己编辑
                setState(() {});
                return;
              }
              _applyPreset(p.baseUrl, p.model);
              // 换供应商 = 换了 Key 的归属，旧 Key 留着只会造成"以为选了新家
              // 结果用的是旧家 Key"的困惑——清空更诚实。
              setState(() => _apiKey.clear());
            },
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _baseUrl,
        // 手改字段后下拉要实时回落「自定义」——没有这个回调，控制器变了
        // 但页面不重建，下拉会停在旧供应商上（测试 llm_preset_test 抓到）。
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Base URL',
          hintText: 'https://api.deepseek.com/v1',
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.url,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _apiKey,
        obscureText: !_showKey,
        decoration: InputDecoration(
          labelText: context.l10n.tr('label_api_key'),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showKey = !_showKey),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _model,
        onChanged: (_) => setState(() {}), // 同 Base URL：让下拉实时反映
        decoration: InputDecoration(
          labelText: context.l10n.tr('label_model'),
          hintText: 'deepseek-chat',
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.l10n.tr('stream_title')),
        subtitle: Text(context.l10n.tr('stream_sub')),
        value: _stream,
        onChanged: (v) => setState(() => _stream = v),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () async {
          await c.saveConfig(LlmConfig(
            baseUrl: _baseUrl.text.trim(),
            apiKey: _apiKey.text.trim(),
            model: _model.text.trim(),
            stream: _stream,
          ));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.tr('saved_snack'))));
          }
        },
        child: Text(context.l10n.tr('save')),
      ),
    ];
  }

  /// 「关于与说明」组里的内容。
  ///
  /// 免责声明是**红线区要求**（README 第六节第 1 条：解析不得构成医学/心理学诊断），
  /// 所以它只是被折叠，不许被删掉或挪进更深的层级——折叠后标题上那句
  /// 「社区版 · AGPL-3.0 开源」就是它在页面上的存在证明。
  List<Widget> _aboutChildren(BuildContext context, ThemeData theme) {
    return [
      Text(
        context.l10n.tr('about_text'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      // 0.7.5：版本号。排查问题时报版本比"最新版"准确得多；
      // versionCode 一并给出（dist 归档与真机 dumpsys 对的正是它）。
      _VersionRow(),
    ];
  }
}

/// 「关于」组里的版本号行：左标签、右值。
class _VersionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String>(
      future: AppVersion.load(),
      builder: (context, snap) {
        final version = snap.hasData ? snap.data! : '—';
        return Row(
          children: [
            Icon(Icons.tag, size: 16, color: theme.hintColor),
            const SizedBox(width: 8),
            Text(
              context.l10n.tr('about_version'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
            const Spacer(),
            Text(
              version,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        );
      },
    );
  }
}

/// 设置页里的一组可折叠内容：图标 + 标题 + 一行现状，默认收起。
///
/// **为什么要折叠**：设置里的东西大多**配一次就不再动**（两条自带凭据、配色、录音策略），
/// 但它们的**现状**需要一直看得见——现在走哪条识别路、Key 配没配、录音占了多少。
/// 做成「点进去的二级页」会把现状藏起来：用户想知道「我现在到底在用哪个」，
/// 还得点进去看一眼再退回来。
///
/// 折叠标题行正好把这两件事分开：**密度收进正文，现状留在标题**。
/// 于是那些「两个月才碰一次」的填表项（两坨 Key 表单）不会再挡在每次打开设置的第一屏。
///
/// **为什么要走 `subtitle` 而不是自己拼一个右侧小胶囊**：`ExpansionTile` 的标题行
/// 左边有图标、右边有展开箭头，真正能用的宽度不到屏幕一半，而中文状态串
/// （「未配置 · 当前识别会失败」）十几个字就撑爆了。放进副标题能拿到整行剩余宽度，
/// 再配 `ellipsis` 兜底，窄屏也不会溢出——凌晨三点在枕边看的东西，不能有一个字是糊的。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.status,
    required this.children,
  });

  final IconData icon;
  final String title;

  /// 标题下面那行**当前事实**。不是「这组能干什么」，而是「它现在是什么状态」——
  /// 这样不展开也知道现状，展开只是为了让用户改。
  final String status;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        // ★ ListTile（ExpansionTile 的标题行）把墨水/背景画在**最近的 Material
        // 祖先**上；不补这一层透明 Material，墨水会被外层带背景色的 Container
        // 盖住（debug 断言会直接报 "ListTile background color or ink splashes
        // may be invisible"，widget 测试也过不去）。
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            // ExpansionTile 展开时会自己补上下两条 1px 分隔线（用 `dividerColor` 上色）。
            // 这里已经有容器描边了，再叠两条就成了三层边框，所以把它调透明。
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              // 所有组都不默认展开（原先「语音识别方式」那一组是 true，2026-09-26 按用户
              // 要求收起来了）。这里**故意不留 `initiallyExpanded` 参数**：留着它就会有人
              // 某天顺手把它翻回 true，而当初收起来是有理由的（见上面调用处的注释）。
              // 折叠标题行的 `status` 已经显示现状，所以收起不等于藏信息。
              // 全组保活：展开后往下翻、再翻回来，展开状态与输入框里的内容都还在。
              // 数量是固定的个位数，这点开销换「回来不被重置」很划算。
              maintainState: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              // 正文左右各让 12，与标题行左缘对齐；底部留 14，别让最后一行贴着圆角。
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              leading: Icon(icon, size: 20, color: scheme.primary),
              title: Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              // 正文统一裹一层 `stretch` 的 Column：
              // ExpansionTile 内部那个 Column 是按**居中**排的，直接塞进去会让
              // 只含文字的组（配色、关于）宽度缩到文字那么宽然后整体居中，
              // 和上面那些满宽的表单组左缘对不齐。stretch 把它拉回满宽，
              // 也就还原了这页之前直接挂在 ListView 下时每个区块拿到的紧约束。
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 语音识别方式：三条路子的**逐项对照** + 选择器。
///
/// 为什么把差别摊开写而不是只给一个下拉框：这三条路的取舍是**不可比**的——
/// 一条看设备脸色、一条多占 78MB 换"绝不出设备"、一条要上传录音换准确率。
/// 只写「离线 / 云端 / 系统」三个词，用户没有依据做选择，最后只能靠试错，
/// 而试错的代价是凌晨三点对着手机说话却什么都没记下来。
class _SpeechSection extends StatelessWidget {
  const _SpeechSection();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final theme = Theme.of(context);
    // 注意：本区块**不再自带标题**——标题由外层 `_SettingsGroup` 的折叠头承担。
    // 留着它会变成「语音识别方式」上下各一行、字号还不同的双标题。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.tr('speech_intro'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        for (final mode in SpeechMode.values) ...[
          _ModeCard(
            mode: mode,
            selected: c.speechMode == mode,
            onTap: () => _selectMode(context, c, mode),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// 选择语音识别方式。
///
/// 离线路在模型未下载时先引导下载（0.6.0 起模型不预装进安装包）：
/// 用户取消或下载失败就**不切换**——切过去却识别不了，比不切更糟。
/// 已下载时行为与以前完全一致（直接切换）。
Future<void> _selectMode(
  BuildContext context,
  AppController c,
  SpeechMode mode,
) async {
  if (mode == SpeechMode.offline) {
    final ok = await ensureOfflineModel(context);
    if (!ok) return;
  }
  await c.setSpeechMode(mode);
}

/// 一种转写方式的说明卡片：点一下选中，并把该方式的各项实情列全。
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final SpeechMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final warn = mode.audioLeavesDevice;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? scheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.tagline,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 逐项实情。**每一条都列全**：折叠起来省地方，同时也就省掉了
            // 用户做判断的依据——而这张表的全部意义就是让人能比较。
            for (final f in mode.facts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        f.label,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: Text(f.value, style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: warn
                    ? scheme.errorContainer.withValues(alpha: 0.35)
                    : scheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    warn ? Icons.privacy_tip_outlined : Icons.info_outline,
                    size: 15,
                    color: warn ? scheme.error : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      mode.caveat,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: warn ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 只有被选中的那一条才去查"现在能不能用"——它要读文件系统 / 读配置
            if (selected) ...[
              const SizedBox(height: 8),
              _ModeReadiness(mode: mode),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「这条路现在能不能用」的实况。
///
/// 存在的意义：让用户在**切换之前**就知道准备得怎么样。否则他会在凌晨三点
/// 按下去、失败、再自己去翻设置，才能发现"模型还没准备好"。
///
/// 做成 StatefulWidget 是为了**只在开始时查一次**：检查要读文件系统，
/// 而父级会因设置变更频繁重建，放 build 里会每次重开一遍查询。
class _ModeReadiness extends StatefulWidget {
  const _ModeReadiness({required this.mode});

  final SpeechMode mode;

  @override
  State<_ModeReadiness> createState() => _ModeReadinessState();
}

class _ModeReadinessState extends State<_ModeReadiness> {
  Future<String>? _future;

  /// 在 `didChangeDependencies` 里探一次，而不是 `initState`：
  ///
  /// 1. `initState` 里不能安全地读 `AppScope`（继承依赖要等依赖解析完成）；
  /// 2. 更重要的是这里会**登记依赖** —— 云端那条的就绪情况依赖 `asrConfig`，
  ///    用户在下面填完并保存后必须立刻刷新。只在 initState 算一次的版本会一直
  ///    停在旧结果上，界面显示"还没填 Base URL"而下面明明填好了（真踩过）。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _probe();
  }

  Future<String> _probe() async {
    final c = AppScope.of(context);
    switch (widget.mode) {
      case SpeechMode.offline:
        return SherpaOnnxTranscriber().describeReadiness();
      case SpeechMode.cloud:
        // 先在 await 之前取好文案，避免跨异步间隙使用 context。
        final ready =
            context.l10n.tr('ready_cloud', {'endpoint': c.asrConfig.endpoint});
        final issue = await CloudTranscriber(config: c.asrConfig).readyIssue();
        return issue ?? ready;
      case SpeechMode.system:
        // 系统服务能不能用，只有在真正按住说话时才知道（探测会弹权限框），
        // 所以这里如实说明"要试了才知道"，而不是假装知道。
        return context.l10n.tr('system_unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        final text = snap.connectionState == ConnectionState.done
            ? (snap.data ?? '')
            : context.l10n.tr('checking');
        if (text.isEmpty) return const SizedBox.shrink();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_outline, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: theme.textTheme.labelSmall)),
          ],
        );
      },
    );
  }
}

/// 「录音留不留 · 已经占了多少 · 怎么清」。
///
/// 三件事合在一个区块里，因为它们回答的是同一个问题的三个阶段：要不要留、
/// 留了多少、留太多怎么办。拆到三个地方的话，用户看到"已经占了 480MB"时
/// 得自己往上翻去找开关在哪。
///
/// 关于 0.3.3 的默认值改动（用户要求）：**「保留录音」默认打开**。
/// 因为默认转写方式是离线，音频本来就要录（识别需要它），留着只是留存策略、
/// 没有额外代价；而它是转录文字唯一的原始证据。配套的不是"替用户自动删"，
/// 而是这个区块里的占用显示 + 到线提醒 —— 音频是用户自己的原话，
/// 删不删只能由他点确认。
class _RecordingsSection extends StatefulWidget {
  const _RecordingsSection();

  @override
  State<_RecordingsSection> createState() => _RecordingsSectionState();
}

class _RecordingsSectionState extends State<_RecordingsSection> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    // 进设置页量一次占用。两个讲究：
    // 1. 只做一次（`_asked` 守着）—— 统计要读目录、逐文件 stat，每次重建都跑一遍没必要；
    // 2. 推到帧后执行（postFrame），不占着这一帧。
    // 为什么不写在 didChangeDependencies：AppScope 是 InheritedNotifier，
    // 刷新占用会 notifyListeners，写在那里会自己喂自己，转成死循环。
    if (!_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppScope.of(context).refreshAudioUsage();
      });
    }

    final theme = Theme.of(context);
    final recordsAnyway = c.speechMode.needsRecording;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题由外层分组头承担，见 `_SettingsGroup`。
        Text(
          context.l10n.tr('recordings_intro'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        _UsageCard(
          usage: c.audioUsage,
          onManage: () => _openManager(context, c),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.tr('keep_rec_title')),
          subtitle: Text(
            recordsAnyway
                ? context.l10n.tr('keep_rec_sub_needed')
                : context.l10n.tr('keep_rec_sub_system'),
          ),
          value: c.keepRecording,
          onChanged: (v) => c.setKeepRecording(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.tr('also_rec_title')),
          subtitle: Text(
            c.speechMode == SpeechMode.system
                ? context.l10n.tr('also_rec_sub_system')
                : context.l10n.tr('also_rec_sub_other'),
          ),
          value: c.alsoRecordDuringSystemAsr,
          onChanged: (v) => c.setAlsoRecordDuringSystemAsr(v),
        ),
      ],
    );
  }

  void _openManager(BuildContext context, AppController c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AudioManagerSheet(controller: c),
    );
  }
}

/// 录音占用：体积 + 到提醒线的进度 + 无主文件提示 + 管理入口。
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.usage, required this.onManage});

  final AudioUsage usage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final over = usage.overWarnLine;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: over
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: over
              ? scheme.error.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                over ? Icons.warning_amber_outlined : Icons.graphic_eq,
                size: 18,
                color: over ? scheme.error : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  usage.isEmpty
                      ? context.l10n.tr('usage_empty')
                      : context.l10n.tr('usage_files', {
                          'total': usage.humanTotal,
                          'count': '${usage.fileCount}'
                        }),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: over ? scheme.error : null,
                  ),
                ),
              ),
            ],
          ),
          if (!usage.isEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usage.warnRatio,
                minHeight: 4,
                color: over ? scheme.error : scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              over
                  ? context.l10n.tr('usage_over_line',
                      {'bytes': formatBytes(kAudioWarnBytes)})
                  : context.l10n.tr('usage_warn_line', {
                      'bytes': formatBytes(kAudioWarnBytes),
                      'span': _humanAudioSpan(kAudioWarnBytes)
                    }),
              style: theme.textTheme.labelSmall?.copyWith(
                color: over ? scheme.error : theme.hintColor,
              ),
            ),
          ],
          if (usage.hasOrphans) ...[
            const SizedBox(height: 6),
            Text(
              context.l10n.tr('usage_orphans', {
                'count': '${usage.orphanCount}',
                'size': usage.humanOrphans,
              }),
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onManage,
              icon: const Icon(Icons.tune, size: 16),
              label: Text(context.l10n.tr('manage_recordings')),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「管理录音」面板。
///
/// 只列**没有记录引用的**音频，不列全部。有记录引用的音频在详情页就能听、
/// 就能逐条删，这里再列一遍等于制造第二套真相；而"没有主人的那些"在界面上
/// 原本无处可见（用户既不知道它们存在，也没法听、没法删）—— 它们才是这个面板
/// 存在的理由，也是 0.3.3 之前真实存在的漏洞：删掉一条记录只删了 JSON，
/// 音频会永远留在盘上。
class _AudioManagerSheet extends StatefulWidget {
  const _AudioManagerSheet({required this.controller});

  /// 显式把控制器传进来，而不是在这里 `AppScope.of(context)`：面板是另一个
  /// route，读 InheritedWidget 要依赖外层挂载位置，传进来就不用关心这件事。
  final AppController controller;

  @override
  State<_AudioManagerSheet> createState() => _AudioManagerSheetState();
}

class _AudioManagerSheetState extends State<_AudioManagerSheet> {
  AppController get _c => widget.controller;

  /// 每次删除之后重新量一遍，并把面板自己重画一次。
  /// 控制器那边会 notifyListeners，但面板不在它的依赖链上（见上面构造参数），
  /// 所以要自己 setState。
  Future<void> _refresh() async {
    await _c.refreshAudioUsage();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final u = _c.audioUsage;
    final orphans = _c.orphanAudioPaths;

    return SafeArea(
      // 外面套一层滚动：无主音频理论上可能很多（反复失败、崩在半路），
      // 不滚动的话底部的操作按钮会被顶出屏幕，而那两个按钮才是这个面板的目的。
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.tr('manager_title'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              u.isEmpty
                  ? context.l10n.tr('mgr_empty')
                  : context.l10n.tr('manager_count',
                      {'count': '${u.fileCount}', 'total': u.humanTotal}),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const Divider(height: 24),
            if (orphans.isEmpty)
              Text(
                context.l10n.tr('manager_no_orphans'),
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                context.l10n.tr('manager_orphans_title',
                    {'count': '${orphans.length}', 'size': u.humanOrphans}),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.tr('manager_orphans_intro'),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 8),
              for (final path in orphans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _OrphanTile(
                    path: path,
                    onDelete: () async {
                      await _c.deleteAudioAt(path);
                      await _refresh();
                    },
                  ),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    title: context.l10n.tr(
                        'confirm_purge_title', {'count': '${orphans.length}'}),
                    body: context.l10n.tr('confirm_purge_body'),
                    confirmLabel: context.l10n.tr('confirm_purge_label'),
                  );
                  if (!ok) return;
                  await _c.purgeOrphanAudioFiles();
                  await _refresh();
                },
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                label: Text(context.l10n
                    .tr('purge_orphans_btn', {'count': '${orphans.length}'})),
              ),
            ],
            const Divider(height: 28),
            Text(context.l10n.tr('purge_all_section'),
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              context.l10n.tr('purge_all_intro'),
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: u.isEmpty
                  ? null
                  : () async {
                      final ok = await _confirm(
                        context,
                        title: context.l10n.tr('purge_all_title'),
                        body: context.l10n.tr('purge_all_body',
                            {'count': '${u.fileCount}', 'total': u.humanTotal}),
                        confirmLabel: context.l10n.tr('purge_all_label'),
                        danger: true,
                      );
                      if (!ok) return;
                      final n = await _c.deleteAllAudio();
                      await _refresh();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                context.l10n.tr('deleted_n', {'n': '$n'}))),
                      );
                    },
              icon: Icon(Icons.delete_sweep_outlined,
                  size: 18, color: u.isEmpty ? null : scheme.error),
              label: Text(context.l10n.tr('purge_all_btn')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条无主音频：文件名 + 回听 + 单条删除。
class _OrphanTile extends StatelessWidget {
  const _OrphanTile({required this.path, required this.onDelete});

  final String path;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = path.split('/').last;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 只给文件名：它是"哪一次录音"的唯一线索，而路径前缀对用户没有信息量
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          AudioPlayerBar(
            path: path,
            dense: true,
            onDelete: () => onDelete(),
          ),
        ],
      ),
    );
  }
}

/// 破坏性动作的确认框。返回用户是否确认。
///
/// 统一到一个函数里，是为了让"取消"永远是左起第一个、默认样式、
/// 而且是 `TextButton`（不抢眼）—— 删除类操作里，习惯性连点两下的代价
/// 是丢掉用户自己的声音，值得在样式上刻意区分。
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.tr('cancel')),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// 把字节数换算成"大约多少分钟的录音"。
///
/// 用 16kHz 单声道 WAV 的 **32KB/秒** 算（见 `audio_store.dart`）。给用户看
/// "500MB" 是没有体感的，换成"约 4 小时"他才判断得出这个提醒线合不合理。
String _humanAudioSpan(int bytes) {
  final minutes = (bytes / 32768 / 60).round();
  // 这是个无 BuildContext 的顶层函数，用当前语言单例取文案（见 AppL10n.current）。
  final l10n = AppL10n.current;
  if (minutes < 60) return l10n.tr('span_minutes', {'n': '$minutes'});
  return l10n.tr('span_hours', {'n': (minutes / 60).toStringAsFixed(1)});
}

/// 云端转写（BYOK）的凭据配置。
///
/// 自己持有输入框状态、只在「保存」时写回控制器：这样设置页的其他区块重建
/// 不会把用户正在敲的内容冲掉，也不需要让父级替它保管一堆 controller。
class _AsrSection extends StatefulWidget {
  const _AsrSection();

  @override
  State<_AsrSection> createState() => _AsrSectionState();
}

class _AsrSectionState extends State<_AsrSection> {
  final _baseUrl = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _showKey = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    final cfg = AppScope.of(context).asrConfig;
    _baseUrl.text = cfg.baseUrl;
    _key.text = cfg.apiKey;
    _model.text = cfg.model;
    _seeded = true;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _applyPreset(String baseUrl, String model) {
    setState(() {
      _baseUrl.text = baseUrl;
      _model.text = model;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = c.speechMode == SpeechMode.cloud;
    final endpoint = asrEndpoint(_baseUrl.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题由外层分组头承担，见 `_SettingsGroup`。
        Text(
          enabled
              ? context.l10n.tr('asr_enabled_intro')
              : context.l10n.tr('asr_disabled_intro'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: enabled ? scheme.error : theme.hintColor,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              enabled ? Icons.warning_amber_outlined : Icons.lock_outline,
              size: 15,
              color: enabled ? scheme.error : theme.hintColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                enabled
                    ? context.l10n.tr('asr_warn_upload')
                    : context.l10n.tr('asr_safe_key'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: enabled ? scheme.error : theme.hintColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: Text(context.l10n.tr('preset_siliconflow')),
              onPressed: () => _applyPreset(
                'https://api.siliconflow.cn/v1',
                'FunAudioLLM/SenseVoiceSmall',
              ),
            ),
            ActionChip(
              label: const Text('OpenAI Whisper'),
              onPressed: () =>
                  _applyPreset('https://api.openai.com/v1', 'whisper-1'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.tr('asr_only_two'),
          style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _baseUrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Base URL',
            hintText: 'https://api.siliconflow.cn/v1',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          obscureText: !_showKey,
          decoration: InputDecoration(
            labelText: 'API Key',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: context.l10n.tr('label_asr_model'),
            hintText: 'FunAudioLLM/SenseVoiceSmall',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        // 回显归一后的地址：拼错的后果是 404，而 404 的报错本身毫无信息量，
        // 所以把"实际会请求哪个地址"直接摆给用户看。
        if (endpoint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.tr('asr_actual', {'endpoint': endpoint}),
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ),
        FilledButton(
          onPressed: () async {
            await c.setAsrConfig(CloudAsrConfig(
              baseUrl: _baseUrl.text.trim(),
              apiKey: _key.text.trim(),
              model: _model.text.trim(),
            ));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.tr('saved_snack'))));
            }
          },
          child: Text(context.l10n.tr('save')),
        ),
      ],
    );
  }
}

/// 夜间配色选择器。
///
/// 刻意**不做「保存」按钮**：配色要当场看到效果才能判断合不合适，
/// 所以点选即时生效并落盘——这一点和 BYOK「填完再提交」的交互刻意区分开。
class _PalettePicker extends StatelessWidget {
  const _PalettePicker();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题由外层分组头承担，见 `_SettingsGroup`。
        Text(
          context.l10n.tr('palette_intro'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final p in DreamPalette.values)
              _PaletteChip(
                palette: p,
                selected: c.palette == p,
                onTap: () => c.setPalette(p),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.tr('palette_current',
              {'label': c.palette.label, 'note': c.palette.note}),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 界面语言选择器。
///
/// 与夜间配色一样是「点选即时生效」：语言切换要当场看到效果，不该再点保存。
/// 选项直接列三种语言的自称（简体中文 / 繁體中文 / English）——语言名本身不需要
/// 翻译，任何语言下用户都能认出自己要选哪个。
class _LocalePicker extends StatelessWidget {
  const _LocalePicker();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.tr('language_intro'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final l in AppLocale.values)
              ChoiceChip(
                label: Text(l.label),
                selected: c.locale == l,
                onSelected: (_) => c.setLocale(l),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final DreamPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 用该方案真实的 ThemeData 取色来做缩略预览，避免"预览和实际不符"。
    // 「跟随系统」没有自己的颜色：底色/文字取浅色方案（白天态），
    // 主色圆点取暖棕烛光（夜间态），拼出「白天浅底 + 夜里暖点」的混合预览。
    final isSystem = palette == DreamPalette.systemFollow;
    final p = buildDreamTheme(isSystem ? DreamPalette.dawn : palette).colorScheme;
    final night =
        isSystem ? buildDreamTheme(DreamPalette.warmAmber).colorScheme : p;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 46,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? theme.colorScheme.primary : p.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.onSurface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: 20,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                      color: night.primary, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            palette.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

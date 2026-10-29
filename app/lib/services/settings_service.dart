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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';
import 'cloud_transcriber.dart';
import 'llm_client.dart';
import 'recording_policy.dart';
import 'speech_mode.dart';

/// BYOK 凭据的存储后端。
///
/// 隐私承诺（写入 README / 隐私政策）：**API Key 只存本机，绝不上传任何服务器**。
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 原生平台：iOS Keychain / Android Keystore 加密存储（flutter_secure_storage）。
///
/// v11 默认参数已是强加密（Android：AES-GCM 数据加密 + RSA-OAEP 密钥包装、
/// 需 API 23+；iOS：Keychain）。不额外放宽参数。
class KeychainSecureStore implements SecureStore {
  const KeychainSecureStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Web 端兜底：浏览器没有 Keychain 等价物，只能落 localStorage。
/// 设置页必须明确告知用户这一点（不应暗示 web 端同样安全）。
class PrefsSecureStore implements SecureStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// 按平台选择存储后端：原生走 Keychain/Keystore，web 走 localStorage。
SecureStore defaultSecureStore() =>
    kIsWeb ? PrefsSecureStore() : const KeychainSecureStore();

class SettingsService {
  static const _kConfig = 'llm_config';
  static const _kApiKey = 'llm_api_key';
  static const _kOnboarded = 'onboarded';
  static const _kPalette = 'night_palette';
  static const _kSpeechMode = 'speech_mode';
  static const _kAsrConfig = 'asr_config';
  static const _kAsrKey = 'asr_api_key';

  /// 界面语言（落盘键）。见 [AppLocale.id]——枚举名即稳定 id，不能改。
  static const _kLocale = 'ui_locale';

  final SecureStore store;
  SettingsService({SecureStore? store}) : store = store ?? defaultSecureStore();

  Future<LlmConfig> load() async {
    final raw = await store.read(_kConfig);
    final key = await store.read(_kApiKey) ?? '';
    if (raw == null) return const LlmConfig(baseUrl: '', apiKey: '', model: '');
    final cfg = LlmConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return cfg.copyWith(apiKey: key);
  }

  Future<void> save(LlmConfig config) async {
    // Key 与其余配置分开存：Key 单独进安全存储，其余（baseUrl/model）非敏感
    await store.write(_kApiKey, config.apiKey);
    final rest = config.copyWith(apiKey: '');
    await store.write(_kConfig, jsonEncode(rest.toJson()));
  }

  Future<void> clearApiKey() => store.delete(_kApiKey);

  Future<bool> isOnboarded() async => (await store.read(_kOnboarded)) == 'true';

  Future<void> setOnboarded() async => store.write(_kOnboarded, 'true');

  /// 夜间配色是**纯 UI 偏好、不敏感**，所以刻意不走安全存储：
  /// 免掉一次 Keychain/Keystore 往返，web 端与原生端行为也一致。
  Future<String?> loadPaletteId() async =>
      (await SharedPreferences.getInstance()).getString(_kPalette);

  Future<void> savePaletteId(String id) async =>
      (await SharedPreferences.getInstance()).setString(_kPalette, id);

  /// ★ 这两个原本是**同一个**开关（`save_audio`），0.3.3 拆开了。
  ///
  /// 拆的理由：那一个开关在两种转写方式下管的是**两件完全不同的事**——
  /// - 离线/云端：音频**本来就要录**（识别需要它），开关只决定"识别完留不留"，
  ///   没有任何代价；
  /// - 系统识别：音频本来不录，打开开关是"额外录一份"，而它会让本应用占住
  ///   麦克风、把系统识别服务静音（Android 10+ 只允许一个应用采集音频，
  ///   前台应用优先）——就是华为那次「说了话却一个字都没识别出来」的根因。
  ///
  /// 合成一个开关的后果很具体：想把"保留"的默认值调成开（用户想要），
  /// 就会**连带把"抢麦克风"的默认值也调成开**，一切到系统识别就静默失灵。
  /// 拆开之后两个默认值可以各自合理。
  static const _kKeepRecording = 'keep_recording';
  static const _kAlsoRecordDuringSystemAsr = 'also_record_during_system_asr';

  /// 旧键，仅用于一次性迁移。
  static const _kSaveAudioLegacy = 'save_audio';

  /// 识别完成后是否把录音留在本机。**默认开。**
  ///
  /// 默认开是 0.3.3 按用户要求改的，理由：默认转写方式是离线，音频本来就要录，
  /// 留着只是留存策略；而**音频是转录文字唯一的原始证据**——听得到自己当时说了
  /// 什么，才谈得上发现识别错在哪、才谈得上修正原文（见 0.3.0 的改原文功能）。
  /// 这跟本项目"可查证性"的立身之本是同一条链。
  ///
  /// 代价是占地方：16kHz 单声道 WAV 约 **1.9MB/分钟**。所以配套了三件事——
  /// 设置页显示实际占用、详情页能回听、超线提醒清理（见 `audio_store.dart`）。
  /// **提醒不等于自动删**：音频是用户的原话，删不删只能用户点确认。
  Future<bool> loadKeepRecording() async {
    final prefs = await SharedPreferences.getInstance();
    return resolveKeepRecording(
      current: prefs.getBool(_kKeepRecording),
      // 迁移：老用户没设过新键，就用旧的 save_audio 决定——
      // 旧值 true 表示"我要留音频"，那两种模式下都算留。
      legacy: prefs.getBool(_kSaveAudioLegacy),
    );
  }

  Future<void> saveKeepRecording(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kKeepRecording, value);

  /// 「系统识别」时是否**额外**录一份音频。**默认关。**
  ///
  /// 默认关是刻意的、有代价的默认值：打开后本应用会占住麦克风，系统识别服务
  /// （独立进程）拿不到音频，表现是「说了话却一个字都识别不出来」，而且**不报错**。
  /// 识别是主功能、音频是附加品，所以默认让识别独占麦克风。
  /// 用户明确表示自己更看重回听时，才打开它——设置页写明了这个代价。
  Future<bool> loadAlsoRecordDuringSystemAsr() async {
    final prefs = await SharedPreferences.getInstance();
    return resolveAlsoRecordDuringSystemAsr(
      current: prefs.getBool(_kAlsoRecordDuringSystemAsr),
      // 迁移：旧的 save_audio=true 在系统识别模式下本就意味着"开着额外录音"，
      // 原样搬过来，不替用户改主意。
      legacy: prefs.getBool(_kSaveAudioLegacy),
    );
  }

  Future<void> saveAlsoRecordDuringSystemAsr(bool value) async =>
      (await SharedPreferences.getInstance())
          .setBool(_kAlsoRecordDuringSystemAsr, value);

  /// 用户点过"知道了"时的录音占用字节数。
  ///
  /// 记下**当时**的大小而不是一个 bool：忽略之后只有占用继续涨（涨过一定比例）
  /// 才再提醒一次。否则要么每次启动都弹（烦），要么永远不再提醒（危险）。
  Future<int> loadAudioWarnDismissedBytes() async =>
      (await SharedPreferences.getInstance()).getInt(_kAudioWarnDismissed) ?? 0;

  Future<void> saveAudioWarnDismissedBytes(int bytes) async =>
      (await SharedPreferences.getInstance()).setInt(_kAudioWarnDismissed, bytes);

  static const _kAudioWarnDismissed = 'audio_warn_dismissed_bytes';

  /// 转写方式。
  ///
  /// 存在 SharedPreferences 而不是安全存储：它只是一个偏好，不含任何凭据。
  /// 认不出来的 id 会回落到默认值（见 [SpeechMode.fromId]）——不能抛异常，
  /// 否则用户跨版本升级后 App 会直接起不来。
  Future<SpeechMode> loadSpeechMode() async => SpeechMode.fromId(
      (await SharedPreferences.getInstance()).getString(_kSpeechMode));

  Future<void> saveSpeechMode(SpeechMode mode) async =>
      (await SharedPreferences.getInstance()).setString(_kSpeechMode, mode.id);

  /// 界面语言。同样是纯 UI 偏好、不含凭据，所以进 SharedPreferences 而非安全存储。
  /// 认不出来的 id 会回落到简体中文（见 [AppLocaleX.fromId]）——不能抛异常。
  Future<AppLocale> loadLocale() async =>
      AppLocaleX.fromId((await SharedPreferences.getInstance()).getString(_kLocale));

  Future<void> saveLocale(AppLocale locale) async =>
      (await SharedPreferences.getInstance()).setString(_kLocale, locale.id);

  /// 云端转写（BYOK）配置。三段都进安全存储，和解析用的 Key 同等对待——
  /// 它同样是一把能花钱的凭据。
  Future<CloudAsrConfig> loadAsrConfig() async {
    final raw = await store.read(_kAsrConfig);
    final key = await store.read(_kAsrKey) ?? '';
    if (raw == null) return CloudAsrConfig(apiKey: key);
    return CloudAsrConfig.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      apiKey: key,
    );
  }

  Future<void> saveAsrConfig(CloudAsrConfig config) async {
    await store.write(_kAsrKey, config.apiKey);
    await store.write(_kAsrConfig, jsonEncode(config.copyWith(apiKey: '').toJson()));
  }
}

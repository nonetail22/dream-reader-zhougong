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

/// 两个录音开关的**取值规则**。
///
/// 为什么单独成一个文件：这些规则同时承载了三种情况 —— 新键有值、只有旧键有值
/// （从 0.3.3 之前的 `save_audio` 迁移）、两者都没有（默认值）。而这三个分支的
/// 取值正是本次改动**最要紧的定义**：默认要从"不留"翻成"留"，但迁移过来的老用户
/// 不能被翻掉意图。
///
/// 留在 `settings_service.dart` 里就没法验证 —— 那边为了读写
/// `SharedPreferences` 必须 import Flutter，而本工程的单测走 `dart test`（纯 Dart、
/// 不拉 flutter_tester），碰不了 Flutter 依赖。规则与存储分开，规则这半边就测得动。
///
/// 本文件**不 import 任何东西**，加依赖前请想一想它还测不测得动。
library;

/// 「识别完保留录音」：**默认开**。
///
/// [current] 是新键（`keep_recording`）的值，[legacy] 是旧的 `save_audio` 的值，
/// 都可能为 null（表示没存过）。
///
/// 默认开是 0.3.3 按用户要求改的。理由是默认转写方式就是离线 —— 音频本来就要录
/// （识别需要它），留着只是留存策略、没有额外代价；而录音是转录文字**唯一的原始
/// 证据**：想看"识别到底把哪句听错了"，只有它拿得出。
///
/// 迁移时旧值原样搬过来（`legacy ?? true`），不替老用户改主意 —— 他设过 `false`
/// 就是明确表示过不要，那就不该因为一次版本升级被翻掉。
bool resolveKeepRecording({bool? current, bool? legacy}) =>
    current ?? legacy ?? true;

/// 「系统识别时同时录一份」：**默认关**。
///
/// 这是一个**有代价的默认值**，所以不能跟着上面那个一起翻转：
/// 打开后本应用会占住麦克风（Android 10+ 只允许一个应用采集音频、前台优先），
/// 系统语音识别服务拿不到音频，表现是「说了话却一个字都识别不出来」，**而且不报错**。
/// 识别是主功能、音频是附加品，所以默认让识别独占麦克风。
///
/// 0.3.3 把这两个开关拆开，全部理由就在这一句：合成一个开关时，想默认保留录音
/// （用户要的）就必然连带把"抢麦克风"也默认打开，一切到系统识别就静默失灵。
bool resolveAlsoRecordDuringSystemAsr({bool? current, bool? legacy}) =>
    current ?? legacy ?? false;

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

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 回听一条录音：播放/暂停 + 拖动进度 + 当前时间 / 总时长。
///
/// 为什么值得单独做成一个可复用的小件 —— 它有两个调用点，语义完全不同：
/// - **详情页**：听"这条梦当时是怎么说的"。这是转录文字唯一的原始证据，
///   也是 0.3.0 加「改原文」时缺的那一环：字能改，原话却印证不了；
/// - **设置 → 录音文件 → 管理**：听"这些没有记录引用的音频到底是什么"。
///
/// 第二个调用点才是这个件存在的关键理由：**删之前能先听一遍**。没有回听，
/// 「清理无主录音」就是个让人不敢按的按钮 —— 不知道要删的是什么，而删掉的是
/// 用户自己的声音，找不回来。能听，这个按钮才谈得上可用。
///
/// 播放状态全部收在本件内部（位置/时长/是否在播），父级只需要给一个路径。
class AudioPlayerBar extends StatefulWidget {
  const AudioPlayerBar({
    super.key,
    required this.path,
    this.onDelete,
    this.dense = false,
  });

  /// 本机音频路径（16kHz WAV 或 m4a，都交给系统解码，本件不关心格式）。
  final String path;

  /// 给了就在最右边显示删除按钮。**删的是这条录音本身**，不是整条记录。
  final VoidCallback? onDelete;

  /// 紧凑模式：给管理列表用（图标更小、进度条更细）。
  final bool dense;

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// 文件已经不在本机。**刻意不当作错误**，当成一种正常状态 ——
  /// 用户可能刚在管理里清过录音，那时记录还在，界面得说清楚为什么放不出声，
  /// 而不是抛一句原生的 "Unable to open file"。
  bool _missing = false;
  String? _error;

  /// 用户正拖着进度条。拖动期间忽略播放器推来的位置，否则手指会被拽回去。
  bool _dragging = false;

  bool get _playing => _state == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    // ReleaseMode.stop：播完**停在原地**，而不是把播放器释放掉。释放的话
    // 再按一次要重新 prepare（约半秒空白），而这个件的用法就是"再听一遍确认"，
    // 反复播是常态。
    _player.setReleaseMode(ReleaseMode.stop);
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (!mounted || _dragging) return;
      setState(() => _position = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _state = PlayerState.stopped;
        _position = Duration.zero;
      });
    }));
    _probeFile();
  }

  /// 先看文件在不在，再决定要不要让用户按得下去。
  ///
  /// 对一个"音频只在本机"的应用来说，这类状态必须说人话：文件被清掉时如果
  /// 只扔一个底层报错，用户会怀疑是自己哪里操作错了。
  Future<void> _probeFile() async {
    var exists = false;
    try {
      exists = await File(widget.path).exists();
    } catch (_) {
      exists = false;
    }
    if (!mounted) return;
    setState(() => _missing = !exists);
  }

  @override
  void didUpdateWidget(covariant AudioPlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _stop();
      _position = Duration.zero;
      _duration = Duration.zero;
      _error = null;
      setState(() {});
      _probeFile();
    }
  }

  Future<void> _stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // 停不下来（对象已释放等）不是用户需要知道的事，静默收场
    }
  }

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      // 播完再按一次要从头放：ReleaseMode.stop 会把位置留在结尾，
      // 不归零的话第二次按下去会"什么都没发生"。
      if (_duration > Duration.zero && _position >= _duration) {
        await _player.seek(Duration.zero);
      }
      await _player.play(DeviceFileSource(widget.path));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = context.l10n.tr('play_failed', {'e': '$e'});
          _state = PlayerState.stopped;
        });
      }
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    _dragging = false;
    final ms = (_duration.inMilliseconds * fraction).round();
    try {
      await _player.seek(Duration(milliseconds: ms));
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    // 出页面必须把声音真停掉：只 dispose 对象时，某些平台上声音会继续放完，
    // 而用户已经退出这一页了（凌晨场景下尤其突兀）。
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_missing) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.dense ? 6 : 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.tr('audio_missing'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
            if (widget.onDelete != null)
              TextButton(
                onPressed: widget.onDelete,
                child: Text(context.l10n.tr('remove_from_record')),
              ),
          ],
        ),
      );
    }

    final total = _duration.inMilliseconds;
    final value = total <= 0
        ? 0.0
        : (_position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _toggle,
              iconSize: widget.dense ? 26 : 34,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              tooltip: _playing
                  ? context.l10n.tr('pause_tooltip')
                  : context.l10n.tr('play_tooltip'),
              icon: Icon(
                _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: scheme.primary,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: value,
                  // 时长还没读出来之前不给拖：拖一根总长未知的进度条没有意义，
                  // 而 seek 到越界位置在部分解码器上会直接报错。
                  onChanged: total > 0
                      ? (v) => setState(() => _position =
                          Duration(milliseconds: (v * total).round()))
                      : null,
                  onChangeStart: (_) => _dragging = true,
                  onChangeEnd: _seekToFraction,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${formatClock(_position)} / ${formatClock(_duration)}',
              style: theme.textTheme.labelSmall,
            ),
            if (widget.onDelete != null)
              IconButton(
                onPressed: widget.onDelete,
                tooltip: context.l10n.tr('delete_audio_tooltip'),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, color: scheme.error),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              _error!,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }
}

/// `mm:ss`。超过一小时也只往分钟数上加（梦的录音不会有那么长，不值得为它加一列）。
String formatClock(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

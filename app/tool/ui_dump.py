#!/usr/bin/env python3
"""解析 `uiautomator dump` 出来的界面 XML，给出可点击的坐标。

为什么需要它：Flutter 应用整个界面是一块画布，**按坐标猜点击位置非常不可靠**
（实测偏差能到 120px，看着"点过了"其实点空了）。`uiautomator dump` 能把 Flutter 的
语义树导出成 `text` / `content-desc` 节点，带上精确的 `bounds`，从这里取中心点才稳。

配套用法：

    ADB=$ANDROID_SDK/platform-tools/adb
    $ADB shell uiautomator dump /sdcard/ui.xml
    $ADB pull /sdcard/ui.xml /tmp/ui.xml
    python3 app/tool/ui_dump.py                 # 概览：所有带文字的节点 + 中心坐标
    python3 app/tool/ui_dump.py --find 保存      # 找某个控件：完整文字 + 可点坐标
    python3 app/tool/ui_dump.py --all            # 完整文字（不截断）

三个反复踩到的坑，都写在下面代码里：
  1. 键盘弹出时会盖住下半屏，**下半屏的节点根本不出现在 dump 里** —— 先
     `adb shell input keyevent 4` 收键盘再 dump（这一步不会退出 App）。
  2. `Switch` 的语义节点覆盖整行，但**只有右侧滑块可点**，点行中心无效 ——
     用 `--find` 拿到 bounds 后点 `x2-40`，并读 `checked` 属性确认。
  3. 文字里的 `&#10;` 是换行、`&amp;` 等是实体 —— 用 `html.unescape` 还原，
     否则关键词匹配会假阴性。
"""
import html
import re
import sys

NODE_RE = re.compile(r'<node[^>]*>')
BOUNDS_RE = re.compile(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
CLASS_RE = re.compile(r'class="([^"]*)"')
CHECKED_RE = re.compile(r'checked="([^"]*)"')


def node_text(node):
    """取节点的可读文字。text 优先，其次 content-desc（Flutter 语义多用后者）。"""
    for attr in ('text', 'content-desc'):
        m = re.search(attr + r'="([^"]*)"', node)
        if m and m.group(1).strip():
            return html.unescape(m.group(1))
    return ''


def node_bounds(node):
    m = BOUNDS_RE.search(node)
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return x1, y1, x2, y2


def load(path):
    with open(path, encoding='utf-8') as f:
        return NODE_RE.findall(f.read())


def fmt_bounds(b):
    if not b:
        return '无 bounds'
    x1, y1, x2, y2 = b
    return f'@({(x1 + x2) // 2},{(y1 + y2) // 2})  bounds=({x1},{y1})-({x2},{y2})'


def fmt_class(node):
    m = CLASS_RE.search(node)
    if not m:
        return ''
    return m.group(1).rsplit('.', 1)[-1]


def main():
    args = sys.argv[1:]
    path = '/tmp/ui.xml'
    keyword = None
    show_all = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == '--find' and i + 1 < len(args):
            keyword = args[i + 1]
            i += 2
        elif a == '--all':
            show_all = True
            i += 1
        else:
            path = a
            i += 1

    try:
        nodes = load(path)
    except FileNotFoundError:
        print(f'读不到 {path}，先跑：adb shell uiautomator dump /sdcard/ui.xml && '
              f'adb pull /sdcard/ui.xml /tmp/ui.xml')
        return 2

    if keyword is not None:
        hits = 0
        for node in nodes:
            text = node_text(node)
            if keyword in text:
                hits += 1
                print(f'--- 命中 {hits}  [{fmt_class(node)}] ---')
                print(f'  可点坐标: {fmt_bounds(node_bounds(node))}')
                print(text)
                print()
        if not hits:
            print(f'没找到含「{keyword}」的节点。可能它在屏幕外——试试先滚动，'
                  f'或先按 BACK 收起键盘再 dump。')
            return 1
        return 0

    print(f'节点总数: {len(nodes)}（文件 {path}）')
    shown = 0
    for node in nodes:
        text = node_text(node)
        if not text:
            continue
        shown += 1
        # 只有可勾选的控件才读 checked —— XML 里每个节点都带 checked="false"，
        # 对普通 View 打印它只会显示一排误导性的 false。
        flag = ''
        if fmt_class(node) in ('Switch', 'CheckBox', 'RadioButton', 'ToggleButton'):
            checked = CHECKED_RE.search(node)
            if checked:
                flag = f'  checked={checked.group(1)}'
        body = text if show_all else text.replace('\n', ' / ')[:70]
        print(f'  {fmt_class(node):<22} {fmt_bounds(node_bounds(node)):<44}{flag}')
        print(f'      {body!r}')
    print(f'带文字的节点: {shown}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""按文字找控件并点它。

为什么需要它：Flutter 应用整个界面是一块画布，**按坐标猜点击位置非常不可靠**
（实测偏差能到 120px，看着"点过了"其实点空了）。`uiautomator dump` 能把 Flutter 的
语义树导出成带 `bounds` 的节点，从这里取中心点才稳。`ui_dump.py` 负责解析，
本脚本负责"找到 → 点下去"这一步，省掉每次手工抄坐标。

用法：

    python3 app/tool/tap_text.py "设置"              # 点第一个含「设置」的节点中心
    python3 app/tool/tap_text.py "保留录音" --switch # Switch 行：点右侧滑块
    python3 app/tool/tap_text.py "保留录音" --dry    # 只打印坐标与状态，不点
    python3 app/tool/tap_text.py "设置" --index 1    # 点第二个命中（0 起）

**为什么要有 `--switch`**：`SwitchListTile` 的语义节点覆盖整行，可**只有右侧滑块
响应点击**，点行中心等于什么都没发生（而且不报错、不提示）。这是本项目在验证
设置页开关时踩过的坑，写进工具里免得再踩一次。

退出码：0 点到/找到；1 没找到；2 用法不对。
"""
import os
import re
import subprocess
import sys

SDK = os.environ.get('ANDROID_SDK') or os.path.expanduser('~/Library/Android/sdk')
ADB = os.path.join(SDK, 'platform-tools', 'adb')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ui_dump import load, node_text, node_bounds, fmt_class  # noqa: E402

CHECKED_RE = re.compile(r'checked="([^"]*)"')


def main():
    argv = sys.argv[1:]
    flags = {a for a in argv if a.startswith('--')}
    positional = [a for a in argv if not a.startswith('--')]
    if not positional:
        print(__doc__)
        return 2

    keyword = positional[0]
    want_index = 0
    if '--index' in argv:
        want_index = int(argv[argv.index('--index') + 1])

    # 键盘弹出时会盖住下半屏、下半屏节点根本不进 dump；先收键盘再 dump。
    # keyevent 4 在键盘已收起时会退出 App，所以只在 --back 时才发。
    if '--back' in flags:
        subprocess.run([ADB, 'shell', 'input', 'keyevent', '4'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    subprocess.run([ADB, 'shell', 'uiautomator', 'dump', '/sdcard/ui.xml'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run([ADB, 'pull', '/sdcard/ui.xml', '/tmp/ui.xml'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    hits = []
    for node in load('/tmp/ui.xml'):
        text = node_text(node)
        if keyword in text:
            hits.append((node, text))

    if not hits:
        print(f'没找到含「{keyword}」的节点')
        return 1

    if want_index >= len(hits):
        print(f'含「{keyword}」的节点只有 {len(hits)} 个，要第 {want_index} 个越界了')
        return 1

    node, text = hits[want_index]
    b = node_bounds(node)
    if not b:
        print(f'「{keyword}」的节点没有 bounds，点不了')
        return 1
    x1, y1, x2, y2 = b

    if '--switch' in flags:
        x, y = x2 - 40, (y1 + y2) // 2
    else:
        x, y = (x1 + x2) // 2, (y1 + y2) // 2

    checked = CHECKED_RE.search(node)
    state = f'  checked={checked.group(1)}' if checked else ''
    print(f'命中「{keyword}」[{fmt_class(node)}]{state}')
    print(f'  bounds=({x1},{y1})-({x2},{y2})  点击点=({x},{y})')
    print(f'  文字: {text.replace(chr(10), " / ")[:120]}')

    if '--dry' in flags:
        return 0

    subprocess.run([ADB, 'shell', 'input', 'tap', str(x), str(y)], check=False)
    return 0


if __name__ == '__main__':
    sys.exit(main())

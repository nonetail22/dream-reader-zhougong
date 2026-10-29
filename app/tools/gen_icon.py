#!/usr/bin/env python3
"""DreamReader 应用图标生成器（纯 Pillow，无外部依赖）。

为什么自己画：本机没有 rsvg-convert / ImageMagick / Inkscape，`qlmanage` 也不能把
SVG 光栅化。所以用 Pillow 在 3 倍超采样画布（1024 逻辑 → 3072 实画）上作画，
再用 LANCZOS 缩下来，边缘和三处圆形遮罩都干净。

设计依据（都来自 App 自己已有的视觉语言，不是外来的）：
- 深夜使用场景：凌晨半梦半醒看屏幕，「柔和、不刺眼」优先于「对比强烈」。
- 暖琥珀是 App 里既有的语义色（Accents.confidenceC / stale = #E8B062），
  并且有一整套「暖棕烛光」配色（primary #C9974F）。图标走暖色是有出处的。
- 默认深蓝主题（#7C84D8）→ night 版直接用「深靛蓝夜 + 暖琥珀」，
  正好是 App 自己的「夜 + 暖」两个关键词。

三层分离的原因：自适应图标（adaptive icon）前景层会被裁成圆/圆角方，
内容必须落在中央安全圈内；传统图标（legacy）则可以满幅。所以标记层要能单独缩放：
  bg 层   竖向渐变底色
  glow 层 形状背后的柔光（夜里那版全靠它显暖）
  mark 层 月牙与配角，由一张 L 遮罩 + 竖向渐变上色得到

  explore  候选探索图（每概念 × 每底色一张 512px）
  board    单文件 HTML 设计评审板（图片内嵌，离线可看）
  build    选定后写入工程（传统图标 + 自适应三件套 + web/PWA 全套）

用法：
  python3 app/tools/gen_icon.py explore --out /tmp/icon_out
  python3 app/tools/gen_icon.py board
  python3 app/tools/gen_icon.py build --concept B --theme night
"""
from __future__ import annotations

import argparse
import base64
import io
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

# ---------------------------------------------------------------- 基本常量

CANVAS = 1024                  # 逻辑画布边长
SS = 3                         # 超采样倍率
W = CANVAS * SS                # 实际作图边长 3072

# 自适应图标（adaptive icon）的两条线（画布 108dp ↔ CANVAS 像素）：
#   SAFE_R   66dp 安全圈半径 —— 硬线，标记越过就可能被圆/圆角方遮罩切到。
#   TARGET_R 约 57dp 直径的视觉目标 —— 启动器只显示 108dp 画布中央约 72dp，
#            标记按这个尺寸画，在可视区里约占八成，既不空也不挤。
DP = CANVAS / 108                     # 1dp = 9.48px
SAFE_R = round(33 * DP)               # → 313px
TARGET_R = round(28.5 * DP)           # → 270px

# 启动器实际显示的可视区：108dp 画布的正中央约 72dp（2/3）。
ADAPTIVE_VIEW = 72 / 108

THEMES: dict[str, dict] = {
    # 暖奶油底：和 App 浅色主题的纸感一致，白天看着舒服。
    'light': dict(
        label='暖奶油底',
        bg_top=(253, 247, 236), bg_bot=(245, 224, 193),
        hi=(232, 168, 106), lo=(184, 102, 48),
        glow=(255, 240, 210), glow_alpha=0.50,
    ),
    # 深靛蓝夜底：App 默认深蓝主题 + 暖琥珀，夜里不刺眼，小尺寸对比也够。
    'night': dict(
        label='深靛蓝夜底',
        bg_top=(40, 48, 80), bg_bot=(19, 23, 42),
        hi=(252, 212, 158), lo=(228, 168, 88),
        glow=(230, 172, 92), glow_alpha=0.34,
    ),
}

CONCEPTS = ('A', 'B', 'C', 'D')
CONCEPT_INFO = {
    'A': ('月牙 + 一道声波', '夜 + 说的话从月亮的开口荡出去'),
    'B': ('月牙 + 两道声波弧', '夜 + 声音一圈圈扩散，最像「在响」'),
    'C': ('月牙（内缘化作波纹）', '梦与声音合成一个形，最简'),
    'D': ('月牙 + 两点柔光星', '只讲夜与梦，最柔最静'),
}


# ---------------------------------------------------------------- 作图工具

def sx(v: float) -> float:
    """逻辑坐标 → 超采样坐标。"""
    return v * SS


def box(cx: float, cy: float, rx: float, ry: float | None = None) -> list[float]:
    ry = rx if ry is None else ry
    return [sx(cx - rx), sx(cy - ry), sx(cx + rx), sx(cy + ry)]


def blank() -> Image.Image:
    return Image.new('L', (W, W), 0)


def make_bg(theme: dict) -> Image.Image:
    grad = Image.linear_gradient('L').resize((W, W), Image.BILINEAR)
    return ImageOps.colorize(grad, black=theme['bg_top'], white=theme['bg_bot']).convert('RGB')


def shade(theme: dict) -> Image.Image:
    """标记的上色层：自带竖向渐变（上亮下暗），平面形状因此有一点体积感。"""
    grad = Image.linear_gradient('L').resize((W, W), Image.BILINEAR)
    return ImageOps.colorize(grad, black=theme['hi'], white=theme['lo']).convert('RGB')


def tint(mask: Image.Image, theme: dict) -> Image.Image:
    return Image.merge('RGBA', (*shade(theme).split(), mask))


def glow_layer(theme: dict, cx: float, cy: float, r: float) -> Image.Image:
    rad = ImageOps.invert(Image.radial_gradient('L').resize((W, W), Image.BILINEAR))
    clip = blank()
    ImageDraw.Draw(clip).ellipse(box(cx, cy, r), fill=255)
    m = Image.composite(rad, blank(), clip)
    a = theme['glow_alpha']
    alpha = m.point(lambda v: int(v * a))
    return Image.merge('RGBA', (*Image.new('RGB', (W, W), theme['glow']).split(), alpha))


# ---------------------------------------------------------------- 形状遮罩

def moon_mask(ocx: float, ocy: float, orr: float,
              icx: float, icy: float, irr: float) -> Image.Image:
    """月牙 = 外圆挖掉一个偏右上方的内圆 → 开口朝右上。"""
    m = blank()
    d = ImageDraw.Draw(m)
    d.ellipse(box(ocx, ocy, orr), fill=255)
    d.ellipse(box(icx, icy, irr), fill=0)
    return m


# 月牙的固定几何（四个概念共用同一轮月亮，换的只是配角）
MOON = dict(ocx=430.0, ocy=500.0, orr=248.0, icx=524.0, icy=424.0, irr=222.0)


def arc_mask(cx: float, cy: float, r: float, span_deg: float, stroke: float) -> Image.Image:
    """一段带圆头的圆弧（圆心在月亮中心，向右张开 → 「声音荡出去」）。"""
    m = blank()
    d = ImageDraw.Draw(m)
    d.arc(box(cx, cy, r), start=-span_deg, end=span_deg, fill=255, width=sx(stroke))
    for sgn in (-1, 1):
        a = math.radians(span_deg * sgn)
        px, py = cx + r * math.cos(a), cy + r * math.sin(a)
        d.ellipse(box(px, py, stroke / 2), fill=255)
    return m


def wave_mask(x0: float, x1: float, cy: float, amp: float,
              cycles: float, hw: float, n: int = 1400) -> Image.Image:
    """一条两端收尖的声波线。收尖是为了让它看起来像「声音」而不是一根管子。"""
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        env = math.sin(math.pi * t) ** 0.55
        x = x0 + (x1 - x0) * t
        y = cy + amp * env * math.sin(2 * math.pi * cycles * t)
        w = hw * env
        top.append((sx(x), sx(y - w)))
        bot.append((sx(x), sx(y + w)))
    m = blank()
    ImageDraw.Draw(m).polygon(top + bot[::-1], fill=255)
    return m


def star_mask(cx: float, cy: float, r: float, fat: float = 0.40) -> Image.Image:
    """四角柔光星：8 个顶点长短交替。fat 控制腰身肥瘦——
    太瘦在小尺寸下会细到看不见（实测 0.30 时只有 2px 宽），所以放宽到 0.40。"""
    m = blank()
    d = ImageDraw.Draw(m)
    pts = []
    for k in range(8):
        a = math.radians(k * 45 - 90)
        rr = r if k % 2 == 0 else r * fat
        pts.append((sx(cx + rr * math.cos(a)), sx(cy + rr * math.sin(a))))
    d.polygon(pts, fill=255)
    return m


# ------------------------------------------------------- 四个概念 → 标记遮罩
# 月牙内缘（凹侧）的可见角度范围实测为 53.6° → 228.5°，中点 141°。
# 一开始写成 -95°..17° 是反的：那个方向在内圆「外侧」，本来就被挖空了，
# 圆缺啃了个寂寞，C 方案的遮罩和「纯月牙」逐像素完全一样。有校验才发现。
SCALLOP_SPAN = (96.0, 186.0)


def mask_a() -> Image.Image:
    """A. 月牙 + 一道从开口荡出去的声波。

    最早这里画的是两根音量柱，但两根柱在启动器里会被读成「暂停键」——
    对一个录音 App 是反义，所以换成一整条收尖的声波线（只有一个笔画，48px 也不糊）。
    """
    m = moon_mask(**MOON)
    w = wave_mask(596, 884, 470, 52, 1.25, 32)
    m.paste(w, (0, 0), w)
    return m


def mask_b() -> Image.Image:
    """B. 月牙 + 两道声波弧。弧间距（54）必须大于线宽（46），否则 48px 下并成一条。"""
    m = moon_mask(**MOON)
    for r in (300.0, 400.0):
        a = arc_mask(MOON['ocx'], MOON['ocy'], r, 46, 46)
        m.paste(a, (0, 0), a)
    return m


def mask_c() -> Image.Image:
    """C. 只一个月牙，内缘被啃出三个圆缺 → 内边界本身成为一道声波。"""
    m = moon_mask(**MOON)
    t0, t1 = SCALLOP_SPAN
    notch = blank()
    d = ImageDraw.Draw(notch)
    for i in range(3):
        t = math.radians(t0 + (t1 - t0) * i / 2)
        px = MOON['icx'] + MOON['irr'] * math.cos(t)
        py = MOON['icy'] + MOON['irr'] * math.sin(t)
        d.ellipse(box(px, py, 52), fill=255)
    # 从月牙里挖掉 → 洞底会露出柔光，正是想要的效果
    return Image.composite(Image.new('L', (W, W), 0), m, notch)


def mask_d() -> Image.Image:
    """D. 月牙 + 两点柔光星。"""
    m = moon_mask(**MOON)
    for cx, cy, r in ((742, 284, 78), (830, 434, 52)):
        s = star_mask(cx, cy, r)
        m.paste(s, (0, 0), s)
    return m


MASKS = {'A': mask_a, 'B': mask_b, 'C': mask_c, 'D': mask_d}


# ---------------------------------------------------------------- 合成

def content_radius(mask: Image.Image) -> float:
    """标记层最远像素到画布中心的距离（逻辑坐标），用来算自适应前景缩放。

    按实际像素量，不按包围盒——月牙/圆弧的包围盒角点其实是空的，
    用 bbox 会把半径高估一大截（实测 422 vs 331），导致前景被过分缩小。
    """
    n = 256
    small = mask.resize((n, n), Image.BOX).point(lambda v: 255 if v > 127 else 0)
    px = small.load()
    c = (n - 1) / 2
    far = 0.0
    for y in range(n):
        for x in range(n):
            if px[x, y]:
                d = math.hypot(x - c, y - c)
                if d > far:
                    far = d
    return far / n * CANVAS


def mark_stack(concept: str, theme: dict) -> Image.Image:
    """柔光 + 标记，合成在一张透明层上（不含底色）。"""
    lay = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    lay = Image.alpha_composite(lay, glow_layer(theme, 468, 486, 430))
    return Image.alpha_composite(lay, tint(MASKS[concept](), theme))


def scaled(layer: Image.Image, factor: float) -> Image.Image:
    """围绕画布中心缩放一层。"""
    if abs(factor - 1.0) < 1e-6:
        return layer
    side = round(W * factor)
    small = layer.resize((side, side), Image.LANCZOS)
    out = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    out.paste(small, ((W - side) // 2, (W - side) // 2))
    return out


def _adaptive_factor(concept: str) -> float:
    """自适应前景缩放系数：把标记收进视觉目标圈；万一某方案本来就小于目标，也不放大。"""
    r = content_radius(MASKS[concept]())
    return min(1.0, TARGET_R / r) if r > 0 else 1.0


def render(concept: str, theme_name: str, scale: float = 1.0) -> Image.Image:
    """传统图标：满幅底色 + 标记（标记按画布本来的比例满画，不做安全圈收缩）。"""
    theme = THEMES[theme_name]
    img = make_bg(theme).convert('RGBA')
    img = Image.alpha_composite(img, scaled(mark_stack(concept, theme), scale))
    return img.convert('RGB')


def render_foreground(concept: str, theme_name: str) -> Image.Image:
    """自适应前景：透明底，标记已收进安全圈。"""
    theme = THEMES[theme_name]
    return scaled(mark_stack(concept, theme), _adaptive_factor(concept))


def compose_adaptive(concept: str, theme_name: str) -> Image.Image:
    """背景满幅 + 前景（已收缩）→ 一张完整的 108dp 画布。"""
    theme = THEMES[theme_name]
    img = make_bg(theme).convert('RGBA')
    return Image.alpha_composite(img, render_foreground(concept, theme_name))


def render_adaptive(concept: str, theme_name: str) -> Image.Image:
    """自适应图标在桌面上的真实观感：把上面那张按启动器可视区裁到中央 2/3。
    评审时要看的就是这个东西——不是传统图标那种满幅铺开的样子。"""
    side = round(W * ADAPTIVE_VIEW)
    off = (W - side) // 2
    return compose_adaptive(concept, theme_name) \
        .crop((off, off, off + side, off + side)).convert('RGB')


def render_monochrome(concept: str) -> Image.Image:
    """Android 13 主题图标用的单色剪影（白色标记 on 透明）。"""
    layer = tint(MASKS[concept](), dict(hi=(255, 255, 255), lo=(255, 255, 255)))
    return scaled(layer, _adaptive_factor(concept))


# ---------------------------------------------------------------- 遮罩预演

def masked(im: Image.Image, shape: str, size: int) -> Image.Image:
    icon = im.resize((size, size), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(m)
    if shape == 'circle':
        d.ellipse([0, 0, size - 1, size - 1], fill=255)
    elif shape == 'squircle':
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.255), fill=255)
    else:
        d.rectangle([0, 0, size - 1, size - 1], fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(icon, (0, 0), m)
    return out


def uri(im: Image.Image) -> str:
    buf = io.BytesIO()
    im.convert('RGBA').save(buf, format='PNG')
    return 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()


def on_wall(im: Image.Image, size: int, bg=(18, 21, 28)) -> Image.Image:
    plate = Image.new('RGB', (size, size), bg)
    circ = masked(im, 'circle', size)
    plate.paste(circ, (0, 0), circ)
    return plate


# ---------------------------------------------------------------- 子命令

def at(im: Image.Image, size: int) -> Image.Image:
    """从 3 倍超采样画布一次性缩到目标尺寸（LANCZOS 会按缩放比自动展宽滤波核）。"""
    return im.resize((size, size), Image.LANCZOS)


def cmd_explore(args: argparse.Namespace) -> int:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    n = 0
    for c in CONCEPTS:
        for t in THEMES:
            at(render_adaptive(c, t), 512).save(out / f'{c}_{t}.png')
            n += 1
    print(f'已生成 {n} 张候选图（自适应图标实际观感）→ {out}')
    return 0


def cmd_board(args: argparse.Namespace) -> int:
    out = Path(args.board)
    cards = []
    for c in CONCEPTS:
        for t in THEMES:
            # 用自适应图标的实际观感出图，避免「评审时好看、装到桌面上变小」的偏差
            im = render_adaptive(c, t)
            title, why = CONCEPT_INFO[c]
            cards.append(f'''      <figure class="card">
        <div class="hero"><img src="{uri(masked(im, 'squircle', 176))}" alt=""></div>
        <figcaption>
          <div class="tag">{c} · {THEMES[t]['label']}</div>
          <div class="name">{title}</div>
          <div class="why">{why}</div>
        </figcaption>
        <div class="strip">
          <img class="s" src="{uri(masked(im, 'circle', 96))}" title="圆形遮罩（Pixel 等）" alt="">
          <img class="s" src="{uri(im.resize((48, 48), Image.LANCZOS).resize((96, 96), Image.NEAREST))}" title="48px 放大（看小尺寸是否糊）" alt="">
          <img class="s" src="{uri(on_wall(im, 96))}" title="深色壁纸上的样子" alt="">
        </div>
      </figure>''')

    html = f'''<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DreamReader 图标方案评审</title>
<style>
  :root {{ --ink:#2c2620; --ink2:#6d6355; --line:#e6ded0; --paper:#fdfaf4;
           --card:#fffdf9; --amber:#b8702c; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--paper); color:var(--ink);
         font:15px/1.7 -apple-system,"PingFang SC","Microsoft YaHei",sans-serif; }}
  header {{ max-width:1080px; margin:0 auto; padding:44px 24px 8px; }}
  h1 {{ font-size:25px; margin:0 0 10px; letter-spacing:.5px; }}
  .lede {{ color:var(--ink2); max-width:790px; }}
  .lede b {{ color:var(--amber); font-weight:600; }}
  main {{ max-width:1080px; margin:0 auto; padding:16px 24px 70px; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(250px,1fr)); gap:18px; }}
  .card {{ margin:0; background:var(--card); border:1px solid var(--line);
           border-radius:16px; padding:16px; }}
  .hero {{ border-radius:22px; overflow:hidden; line-height:0; }}
  .hero img {{ width:100%; display:block; }}
  figcaption {{ padding:12px 2px 4px; }}
  .tag {{ font-size:12px; letter-spacing:.6px; color:#a4917a; }}
  .name {{ font-weight:600; margin-top:2px; }}
  .why {{ font-size:13px; color:var(--ink2); }}
  .strip {{ display:flex; gap:10px; padding:6px 2px 2px; }}
  .strip img.s {{ width:52px; height:52px; border-radius:12px; }}
  .notes {{ margin-top:34px; border-top:1px solid var(--line); padding-top:22px; }}
  .notes h2 {{ font-size:17px; margin:0 0 8px; }}
  .notes ul {{ margin:0; padding-left:20px; color:var(--ink2); font-size:14px; }}
  code {{ background:#f2ebdd; padding:1px 5px; border-radius:4px; font-size:12.5px; }}
</style></head><body>
<header>
  <h1>DreamReader 图标方案评审</h1>
  <p class="lede">四个月亮方向 × 两种底色，都用 App 自己已有的暖琥珀（<code>#E8B062</code>）
  与暖棕烛光（<code>#C9974F</code>）调色，前提是「凌晨半梦半醒看不刺眼」。
  每张卡片下面一排，从左到右是 <b>圆形遮罩</b>、<b>48px 像素级放大</b>（最容易糊的一档）、
  <b>深色壁纸上的样子</b>。</p>
</header>
<main>
  <div class="grid">
{chr(10).join(cards)}
  </div>
  <div class="notes">
    <h2>怎么挑</h2>
    <ul>
      <li>先看第三排最左边那格 <b>48px</b>——那是启动器里最常出现的大小，糊了就直接淘汰。</li>
      <li>「体现 App 特点」优先看 <b>A / B</b>（夜 + 口述）；想要最安静柔和看 <b>C / D</b>。</li>
      <li>底色定调：<b>暖奶油</b>偏日记本、白天友好；<b>深靛蓝夜</b>偏梦、夜里护眼、小尺寸对比更强。</li>
      <li>选定后一条命令写进工程：传统图标 5 档 + 自适应前景/背景/单色 + web/PWA 全套。</li>
    </ul>
  </div>
</main></body></html>'''
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding='utf-8')
    print(f'评审板已生成 → {out}（内嵌 {len(cards)} 张候选，单文件离线可看）')
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    project = Path(args.project)
    c, t = args.concept, args.theme

    legacy = render(c, t)
    fg = render_foreground(c, t)
    bg = make_bg(THEMES[t])
    mono = render_monochrome(c)

    sizes_legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    # 自适应图标以 108dp 为画布基准
    sizes_adaptive = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

    written: list[str] = []

    def put(im: Image.Image, rel: str, px: int) -> None:
        p = project / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        im.resize((px, px), Image.LANCZOS).save(p)
        written.append(str(p))

    # 老系统的 roundIcon 兜底：API < 26 不认 anydpi-v26 的自适应描述文件，
    # 必须有一张真的圆形位图，否则 @mipmap/ic_launcher_round 解析不到。
    # 圆外留透明（不能转 RGB，否则四角会变成黑块）。
    round_icon = masked(legacy, 'circle', W)

    for dens, px in sizes_legacy.items():
        put(legacy, f'android/app/src/main/res/mipmap-{dens}/ic_launcher.png', px)
        put(round_icon, f'android/app/src/main/res/mipmap-{dens}/ic_launcher_round.png', px)
    for dens, px in sizes_adaptive.items():
        put(fg, f'android/app/src/main/res/mipmap-{dens}/ic_launcher_foreground.png', px)
        put(bg, f'android/app/src/main/res/mipmap-{dens}/ic_launcher_background.png', px)
        put(mono, f'android/app/src/main/res/mipmap-{dens}/ic_launcher_monochrome.png', px)

    # 自适应图标描述文件（Android 8.0+）
    xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
'''
    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        p = project / f'android/app/src/main/res/mipmap-anydpi-v26/{name}'
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(xml, encoding='utf-8')
        written.append(str(p))

    put(legacy, 'web/favicon.png', 64)
    put(legacy, 'web/icons/Icon-192.png', 192)
    put(legacy, 'web/icons/Icon-512.png', 512)
    # maskable：底色铺满整格（PWA 遮罩会裁外边），标记同样收在安全圈内
    maskable = compose_adaptive(c, t).convert('RGB')
    for px in (192, 512):
        put(maskable, f'web/icons/Icon-maskable-{px}.png', px)

    # iOS：尺寸表直接读 Contents.json，别手抄（手抄迟早漏一张或算错 @2x）
    ios_dir = project / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    if (ios_dir / 'Contents.json').exists():
        import json
        spec = json.loads((ios_dir / 'Contents.json').read_text(encoding='utf-8'))
        for entry in spec.get('images', []):
            name = entry.get('filename')
            if not name:
                continue
            side = float(entry['size'].split('x')[0])
            px = round(side * float(entry.get('scale', '1').rstrip('x')))
            # iOS 图标必须不透明、直角（圆角由系统裁），所以用满幅那版并转 RGB
            put(legacy.convert('RGB'), f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}', px)

    for p in written:
        print('写出', p)
    r = content_radius(MASKS[c]())
    print(f'\n共 {len(written)} 个文件（concept={c}, theme={t}）')
    print(f'标记最远半径 {r:.0f}px → 自适应前景缩放 {_adaptive_factor(c):.3f}'
          f'（硬线 {SAFE_R}px / 视觉目标 {TARGET_R}px）')
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description='DreamReader 图标生成器')
    sub = ap.add_subparsers(dest='cmd', required=True)

    e = sub.add_parser('explore', help='生成候选探索图')
    e.add_argument('--out', default='/tmp/icon_out')
    e.set_defaults(func=cmd_explore)

    b = sub.add_parser('board', help='生成单文件 HTML 设计评审板')
    b.add_argument('--board', default='docs/icon-review.html')
    b.set_defaults(func=cmd_board)

    d = sub.add_parser('build', help='写入工程资源')
    d.add_argument('--concept', choices=CONCEPTS, required=True)
    d.add_argument('--theme', choices=tuple(THEMES), required=True)
    d.add_argument('--project', default=str(Path(__file__).resolve().parents[1]))
    d.set_defaults(func=cmd_build)

    args = ap.parse_args()
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())

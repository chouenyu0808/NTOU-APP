"""產出 App 圖示。

    py tool/render_icon.py

會寫出三個檔：

    assets/icon.png             1024²，白底、不透明。iOS 和舊版 Android 用。
    assets/icon_foreground.png  1024²，透明底。Android adaptive icon 的前景層。
    assets/icon.svg             向量版。

標是一個「海」字 —— 校名的關鍵字，中文語境裡比拉丁字母直接，
而且不會跟任何一個 App 撞形。

**字形只有 tool/hai_path.json 這一份。** `lib/src/ui/hai_path.dart` 是從它
產生的（見 tool/extract_glyph.py），改了一邊就要重跑一次產生器，
不然桌面上的圖示會跟 App 裡的標長得不一樣。

為什麼前景要另外出一張：Android 8 以後系統會自己套遮罩（圓形、方形、水滴，
各家不同）而且會視差移動，中央 72/108 以外隨時會被切掉。所以前景層的字要
縮得比 icon.png 小，背景則是純色、寫在 pubspec 裡不用出圖。
"""

import io
import json
import os

from PIL import Image, ImageDraw

# 深海藍。跟 NtouTheme.seed 是同一個值。
INK = (0x00, 0x50, 0x6B)
PAPER = (0xFF, 0xFF, 0xFF)

SIZE = 1024
SS = 4  # 先畫 4 倍再縮，邊緣才不會有鋸齒

# 字身佔整格的比例。
SPAN_ICON = 0.62

# **前景層不能跟 icon.png 用同一個數字。**
#
# Android 的 adaptive icon 前景層是 108dp，但系統只顯示中央的 72dp ——
# 前景層上佔 F 的東西，在桌面上會被放大成 F × 108/72 = F × 1.5。
#
# 這裡踩過一次：icon.png 設 0.76、前景設 0.60，結果 iOS 顯示 76%、
# Android 顯示 90%，同一個 App 兩個平台的字差了一大截，Android 那邊爆滿。
# 當時驗遮罩是拿整張 1024 去套圓形，不是中央的 72/108，所以沒看出來。
#
# 所以這個值用推導的，不要手填。驗證的時候也要記得把前景裁到中央 72/108
# 再看，那才是桌面上的樣子。
SPAN_FOREGROUND = SPAN_ICON * 72 / 108

TOOL = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(TOOL, '..', 'assets')


def _quad(p0, c, e, n=24):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * e[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * e[1])
            for t in (i / n for i in range(1, n + 1))]


def _cubic(p0, a, b, e, n=28):
    return [((1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * a[0]
             + 3 * (1 - t) * t * t * b[0] + t ** 3 * e[0],
             (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * a[1]
             + 3 * (1 - t) * t * t * b[1] + t ** 3 * e[1])
            for t in (i / n for i in range(1, n + 1))]


def contours():
    """把 hai_path.json 的曲線攤平成多邊形，座標還是 100 格的。"""
    ops = json.load(io.open(os.path.join(TOOL, 'hai_path.json'), encoding='utf-8'))['ops']
    out, cur, pos = [], [], (0.0, 0.0)
    for op in ops:
        kind = op[0]
        if kind == 'm':
            if len(cur) > 2:
                out.append(cur)
            pos = tuple(op[1])
            cur = [pos]
        elif kind == 'l':
            pos = tuple(op[1])
            cur.append(pos)
        elif kind == 'q':
            cur += _quad(pos, tuple(op[1]), tuple(op[2]))
            pos = tuple(op[2])
        elif kind == 'c':
            cur += _cubic(pos, tuple(op[1]), tuple(op[2]), tuple(op[3]))
            pos = tuple(op[3])
        elif kind == 'z':
            if len(cur) > 2:
                out.append(cur)
            cur = []
    if len(cur) > 2:
        out.append(cur)
    return out


def glyph_mask(span):
    """字的遮罩。span 是字身佔整格的比例。"""
    s = SIZE * SS
    m = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(m)
    # 12 個輪廓全部同向、沒有反向內孔，所以聯集就是 nonzero 的結果。
    for c in contours():
        d.polygon([((x - 50) * span / 100 * s + s / 2,
                    (y - 50) * span / 100 * s + s / 2) for x, y in c], fill=255)
    return m


def draw(span, background):
    """background 是 None 的話底是透明的。"""
    s = SIZE * SS
    base = Image.new('RGBA', (s, s), background + (255,) if background else (0, 0, 0, 0))
    base.paste(Image.new('RGBA', (s, s), INK + (255,)), (0, 0), glyph_mask(span))
    return base.resize((SIZE, SIZE), Image.LANCZOS)


def svg():
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"'
             ' width="1024" height="1024">',
             f'  <rect width="100" height="100" fill="#{PAPER[0]:02X}{PAPER[1]:02X}{PAPER[2]:02X}"/>']
    span = SPAN_ICON
    for c in contours():
        pts = ' '.join(f'{(x - 50) * span + 50:.2f},{(y - 50) * span + 50:.2f}' for x, y in c)
        parts.append(f'  <polygon points="{pts}" fill="#{INK[0]:02X}{INK[1]:02X}{INK[2]:02X}"/>')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'


def main():
    icon = os.path.join(ASSETS, 'icon.png')
    fg = os.path.join(ASSETS, 'icon_foreground.png')
    vector = os.path.join(ASSETS, 'icon.svg')

    draw(SPAN_ICON, PAPER).convert('RGB').save(icon, optimize=True)  # iOS 不吃 alpha
    draw(SPAN_FOREGROUND, None).save(fg, optimize=True)
    io.open(vector, 'w', encoding='utf-8', newline='\n').write(svg())

    for path in (icon, fg, vector):
        print(f'{os.path.relpath(path, os.path.join(ASSETS, ".."))}'
              f'  {os.path.getsize(path):,} bytes')
    print()
    print('提醒：底色從深藍換成白底了，pubspec.yaml 要跟著改 ——')
    print(f'  adaptive_icon_background: "#{PAPER[0]:02X}{PAPER[1]:02X}{PAPER[2]:02X}"')
    print('  沒改的話 Android 會拿深藍當底配深藍的字，圖示是一片藍。')


if __name__ == '__main__':
    main()

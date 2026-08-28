"""產出 App 圖示。

    py tool/render_icon.py

會寫出三個檔：

    assets/icon.png             1024²，畫滿、不透明。iOS 和舊版 Android 用。
    assets/icon_foreground.png  1024²，透明底。Android adaptive icon 的前景層。
    assets/icon.svg             同一組座標的向量版，改東西從這裡改。

**字形的座標只有 MARK 這一份。** `lib/src/ui/ntou_mark.dart` 裡那個
CustomPainter 用的是同一組數字 —— 改了這裡就要一起改那裡，不然桌面上的圖示
會跟登入頁的標長得不一樣。

為什麼不是一張圖切兩次：Android 8 以後系統會自己套遮罩（圓形、方形、水滴，
各家不同）並且會視差移動，中央 72/108 以外隨時可能被切掉。所以前景層的標
要縮得比 icon.png 小，而背景是純色、寫在 pubspec 裡不用出圖。
"""

import io
import os

from PIL import Image, ImageDraw

# 稜面 N。座標寫在 100×100 的方格裡，字身佔 24–76，直桿寬 14。
#
# 四塊直接拼出字形，不用 clip —— 接縫的位置是設計出來的（兩根直桿、
# 對角線上下各一半），不是任兩條線交會的地方。
#
# **對角線的垂直落差是 22，不是 16。** 斜筆畫的視覺粗細是垂直落差除以
# sqrt(1 + 斜率²)：落差 16 只有 8.9 粗，比直桿細三分之一，看起來像根牙籤。
# 落差 22 換算出來是 13.7，跟直桿的 14 打平（斜筆畫本來就該比直筆略細一點點，
# 不然視覺上會顯得更重）。
#
# 配色的邏輯是「一個被打光的物件」而不是四片拼貼：兩根桿子同色系（青），
# 對角線另一色系（藍白）。同色系用透明度分遠近，換色系標出那一筆才是字的主角。
MARK = [
    # 左桿 —— 迎光面
    ([(24, 24), (38, 24), (38, 76), (24, 76)], (0x26, 0xC6, 0xDA), 1.00),
    # 對角線上半 —— 最亮的一片
    ([(38, 24), (50, 39), (50, 61), (38, 46)], (0xC1, 0xE8, 0xFF), 1.00),
    # 對角線下半 —— 同一片的背光側
    ([(50, 39), (62, 54), (62, 76), (50, 61)], (0xC1, 0xE8, 0xFF), 0.58),
    # 右桿 —— 退一階
    ([(62, 24), (76, 24), (76, 76), (62, 76)], (0x26, 0xC6, 0xDA), 0.70),
]

# 深海藍。跟 NtouTheme.seed 是同一個值。
BG = (0x00, 0x50, 0x6B)

SIZE = 1024
SS = 4  # 先畫 4 倍再縮，邊緣才不會有鋸齒

# 字身現在佔 52%（24–76）。兩張圖要的大小不一樣：
#   icon.png       系統只會切掉四角，可以放大一點
#   foreground.png 要留在中央的安全區裡，所以縮小
SPAN_ICON = 0.62
SPAN_FOREGROUND = 0.50
_SPAN_SOURCE = 0.52

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets')


def scaled(points, span):
    """把座標對著中心點縮放到指定的佔比，再換算成像素。"""
    k = span / _SPAN_SOURCE
    out = []
    for x, y in points:
        out.append((
            (50 + (x - 50) * k) / 100 * SIZE * SS,
            (50 + (y - 50) * k) / 100 * SIZE * SS,
        ))
    return out


def draw(span, background):
    """畫一張圖。background 是 None 的話底是透明的。"""
    base = Image.new('RGBA', (SIZE * SS, SIZE * SS),
                     background + (255,) if background else (0, 0, 0, 0))
    for points, rgb, alpha in MARK:
        # 每一片各自畫在一張透明圖上再疊回去 —— ImageDraw 不會做 alpha 混色，
        # 直接畫的話 55% 那片會變成不透明的。
        layer = Image.new('RGBA', base.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).polygon(scaled(points, span), fill=rgb + (round(alpha * 255),))
        base = Image.alpha_composite(base, layer)
    return base.resize((SIZE, SIZE), Image.LANCZOS)


def svg():
    """向量版。用的是原始座標，不縮放。"""
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="1024" height="1024">',
        f'  <rect width="100" height="100" fill="#{BG[0]:02X}{BG[1]:02X}{BG[2]:02X}"/>',
    ]
    for points, rgb, alpha in MARK:
        d = 'M' + ' L'.join(f'{x} {y}' for x, y in points) + ' Z'
        hexcol = f'#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}'
        op = '' if alpha == 1.0 else f' opacity="{alpha}"'
        parts.append(f'  <path d="{d}" fill="{hexcol}"{op}/>')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'


def main():
    icon = os.path.join(ASSETS, 'icon.png')
    fg = os.path.join(ASSETS, 'icon_foreground.png')
    vector = os.path.join(ASSETS, 'icon.svg')

    # iOS 不吃 alpha，這張直接轉成 RGB。
    draw(SPAN_ICON, BG).convert('RGB').save(icon, optimize=True)
    draw(SPAN_FOREGROUND, None).save(fg, optimize=True)
    io.open(vector, 'w', encoding='utf-8', newline='\n').write(svg())

    for path in (icon, fg, vector):
        print(f'{os.path.relpath(path, os.path.join(ASSETS, ".."))}'
              f'  {os.path.getsize(path):,} bytes')


if __name__ == '__main__':
    main()

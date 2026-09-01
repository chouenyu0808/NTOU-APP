"""把「海」在 Noto Sans TC Black 的外框抽成向量路徑。

包整套 CJK 字型是 10MB 以上，只為了一個字；用系統字型的話各平台長得不一樣
（而且不保證有 Black 字重）。抽成路徑寫死，兩邊都免了。
"""
import io, json
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.recordingPen import RecordingPen

SRC = r'C:\Windows\Fonts\NotoSansTC-VF.ttf'
CH = '海'

f = TTFont(SRC)
f = instancer.instantiateVariableFont(f, {'wght': 900})   # Black
name = f.getBestCmap()[ord(CH)]
gs = f.getGlyphSet()
pen = RecordingPen()
gs[name].draw(pen)
upem = f['head'].unitsPerEm

# 取得邊界
xs, ys = [], []
for op, pts in pen.value:
    for p in pts or ():
        xs.append(p[0]); ys.append(p[1])
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
w, h = x1 - x0, y1 - y0
side = max(w, h)
print(f'glyph={name} upem={upem} bbox=({x0},{y0})-({x1},{y1}) w={w} h={h}')

# 正規化到 0..100 的方格，置中，y 向下翻
def N(p):
    x = (p[0] - x0 - w / 2) / side * 100 + 50
    y = 50 - (p[1] - y0 - h / 2) / side * 100
    return (round(x, 2), round(y, 2))

svg, dart, ncontour = [], [], 0
for op, pts in pen.value:
    if op == 'moveTo':
        a = N(pts[0]); svg.append(f'M{a[0]} {a[1]}'); dart.append(('m', a)); ncontour += 1
    elif op == 'lineTo':
        a = N(pts[0]); svg.append(f'L{a[0]} {a[1]}'); dart.append(('l', a))
    elif op == 'qCurveTo':
        q = [N(p) for p in pts if p is not None]
        implied = pts[-1] is None
        if implied:  # TrueType 的隱含終點：最後兩個控制點的中點
            q.append(((q[-1][0] + q[0][0]) / 2, (q[-1][1] + q[0][1]) / 2))
        for i in range(len(q) - 1):
            c, e = q[i], q[i + 1]
            if i < len(q) - 2:  # 隱含在途中的 on-curve 點
                e = (round((c[0] + q[i + 1][0]) / 2, 2), round((c[1] + q[i + 1][1]) / 2, 2))
            svg.append(f'Q{c[0]} {c[1]} {e[0]} {e[1]}'); dart.append(('q', c, e))
    elif op == 'curveTo':
        cs = [N(p) for p in pts]
        svg.append('C' + ' '.join(f'{p[0]} {p[1]}' for p in cs)); dart.append(('c', *cs))
    elif op == 'closePath':
        svg.append('Z'); dart.append(('z',))

d = ' '.join(svg)
io.open('hai-path.svg', 'w', encoding='utf-8', newline='\n').write(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512">\n'
    f'  <rect width="100" height="100" fill="#FFFFFF"/>\n'
    f'  <path d="{d}" fill="#00506B" fill-rule="nonzero"/>\n</svg>\n')
io.open('hai-path.json', 'w', encoding='utf-8', newline='\n').write(
    json.dumps({'viewBox': 100, 'contours': ncontour, 'ops': dart}, ensure_ascii=False))
print(f'輪廓 {ncontour} 個  路徑 {len(d)} 字元  → hai-path.svg / hai-path.json')

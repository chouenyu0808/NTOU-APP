import 'package:flutter/material.dart';

/// 稜面 N —— NTOU 的標。
///
/// 四塊多邊形直接拼出字形，沒有 clip：接縫的位置是設計出來的（兩根直桿、
/// 對角線上下各一半），不是任兩條線交會的地方。少一層繪圖機制就少一種壞法。
///
/// **這組座標跟 `assets/icon.png` 是同一份**，見 [tool/render_icon.py]。
/// 改了一邊一定要改另一邊 —— 桌面上的圖示跟 App 裡的標長得不一樣，
/// 正是換掉舊圖示的原因（桌面是舵輪，開 App 是 `Icons.sailing` 的帆船）。
class NtouMark extends StatelessWidget {
  const NtouMark({super.key, required this.size, this.color});

  /// **字身**的大小，不是含留白的方框。
  ///
  /// 呼叫端才知道這個標在它的容器裡該佔多大 —— `assets/icon.png` 是 62%、
  /// Android 前景層是 50%（要留在遮罩的安全區裡）。把留白算進來的話，
  /// 每個呼叫端都得先反推一次。
  final double size;

  /// `assets/icon.png` 裡字身佔整格的比例。
  ///
  /// 登入頁那格要跟桌面圖示長得一樣，所以用同一個數字。
  static const double iconSpan = 0.62;

  /// 四片稜面的座標與透明度。**只給測試用。**
  ///
  /// 開出來是為了讓 `ntou_mark_test.dart` 驗得到那幾個一旦改壞就再也看不出來的
  /// 比例（尤其是對角線的粗細）—— 那種東西在畫面上只會「怪怪的」，
  /// 不會壞掉，所以要用測試釘住。
  @visibleForTesting
  static List<({List<Offset> points, double opacity, double monoOpacity})>
      get facets => [
            for (final f in _facets)
              (points: f.points, opacity: f.opacity, monoOpacity: f.monoOpacity),
          ];

  /// 單色版：四片改用同一個顏色的不同透明度。
  ///
  /// 印刷、浮水印、深色底上的小圖都會用到。給 null 就是彩色版。
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter(color)),
      );
}

/// 一片稜面。
class _Facet {
  const _Facet(this.points, this.color, this.opacity, this.monoOpacity);

  /// 座標寫在 100×100 的方格裡，畫的時候等比縮放。
  final List<Offset> points;

  final Color color;

  /// 彩色版的透明度。
  final double opacity;

  /// 單色版的透明度。彩色版有兩片都是 1.0（靠色相分開），單色沒有色相可用，
  /// 所以四片各給一階，不然會黏成兩塊。
  final double monoOpacity;
}

/// 字身佔 24–76，直桿寬 14。
///
/// **對角線的垂直落差是 22，不是 16。** 斜筆畫的視覺粗細是垂直落差除以
/// `sqrt(1 + 斜率²)`：落差 16 只有 8.9 粗，比直桿細三分之一，看起來像根牙籤。
/// 落差 22 換算是 13.7，跟直桿的 14 打平 —— 斜筆畫本來就該比直筆略細一點點，
/// 不然視覺上會顯得更重。
///
/// 配色是「一個被打光的物件」而不是四片拼貼：兩根桿子同色系（青），
/// 對角線另一色系（藍白）。同色系用透明度分遠近，換色系標出那一筆才是字的主角。
const List<_Facet> _facets = [
  // 左桿 —— 迎光面
  _Facet(
    [Offset(24, 24), Offset(38, 24), Offset(38, 76), Offset(24, 76)],
    Color(0xFF26C6DA),
    1.00,
    0.76,
  ),
  // 對角線上半 —— 最亮的一片
  _Facet(
    [Offset(38, 24), Offset(50, 39), Offset(50, 61), Offset(38, 46)],
    Color(0xFFC1E8FF),
    1.00,
    1.00,
  ),
  // 對角線下半 —— 同一片的背光側
  _Facet(
    [Offset(50, 39), Offset(62, 54), Offset(62, 76), Offset(50, 61)],
    Color(0xFFC1E8FF),
    0.58,
    0.40,
  ),
  // 右桿 —— 退一階
  _Facet(
    [Offset(62, 24), Offset(76, 24), Offset(76, 76), Offset(62, 76)],
    Color(0xFF26C6DA),
    0.70,
    0.56,
  ),
];

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.mono);

  final Color? mono;

  @override
  void paint(Canvas canvas, Size size) {
    // 座標是 100 格的，但字身只佔 24–76：換算成「字身填滿這個 widget」。
    const origin = 24.0;
    const span = 52.0;
    final k = size.shortestSide / span;
    final paint = Paint()..isAntiAlias = true;
    final mono = this.mono;

    for (final facet in _facets) {
      final first = facet.points.first;
      final path = Path()..moveTo((first.dx - origin) * k, (first.dy - origin) * k);
      for (final p in facet.points.skip(1)) {
        path.lineTo((p.dx - origin) * k, (p.dy - origin) * k);
      }
      path.close();

      paint.color = mono == null
          ? facet.color.withValues(alpha: facet.opacity)
          : mono.withValues(alpha: mono.a * facet.monoOpacity);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.mono != mono;
}

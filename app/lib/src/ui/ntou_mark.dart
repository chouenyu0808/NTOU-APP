import 'package:flutter/material.dart';

import 'hai_path.dart';
import 'theme.dart';

/// 「海」—— NTOU 的標。
///
/// 校名的關鍵字。N、T、U 台灣每一間國立大學都有，只有這個字是海大獨有的。
///
/// 字形是 Noto Sans TC Black 的「海」抽出來的向量路徑（[kHaiPath]），
/// **不是拿字型畫的**：包整套 CJK 字型是 10 MB 以上、只為了一個字；
/// 用系統字型的話各平台長得不一樣，而且不保證有 Black 字重。
///
/// **這份路徑跟 `assets/icon.png` 是同一份**（見 `tool/render_icon.py`）。
/// 桌面上的圖示跟 App 裡的標長得不一樣，正是當初換掉舊圖示的原因 ——
/// 改字形的話兩邊要一起改，來源是 `tool/hai_path.json`。
class NtouMark extends StatelessWidget {
  const NtouMark({super.key, required this.size, this.color});

  /// **字身**的大小，不是含留白的方框。
  ///
  /// 呼叫端才知道這個標在它的容器裡該佔多大 —— `assets/icon.png` 是 76%、
  /// Android 前景層是 60%（要留在遮罩的安全區裡）。把留白算進來的話，
  /// 每個呼叫端都得先反推一次。
  final double size;

  /// 字的顏色。預設是深海藍。
  final Color? color;

  /// `assets/icon.png` 裡字身佔整格的比例。
  ///
  /// 登入頁那格要跟桌面圖示長得一樣，所以用同一個數字。
  static const double iconSpan = 0.76;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter(color ?? NtouTheme.seed)),
      );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 路徑的座標是 0–100，字身剛好撐滿，所以直接等比放大。
    final k = size.shortestSide / 100;
    final path = Path();

    for (final op in kHaiPath) {
      final code = op[0].toInt();
      if (code == 0) {
        path.moveTo(op[1] * k, op[2] * k);
      } else if (code == 1) {
        path.lineTo(op[1] * k, op[2] * k);
      } else if (code == 2) {
        path.quadraticBezierTo(op[1] * k, op[2] * k, op[3] * k, op[4] * k);
      } else if (code == 3) {
        path.cubicTo(op[1] * k, op[2] * k, op[3] * k, op[4] * k, op[5] * k, op[6] * k);
      } else {
        path.close();
      }
    }

    // nonZero 是 Path 的預設。十二個輪廓全部同向、沒有反向內孔 ——
    // 用 evenOdd 的話筆畫交疊的地方會被挖掉，變成一片棋盤格。
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color;
}

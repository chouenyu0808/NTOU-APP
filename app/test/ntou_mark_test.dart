import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/hai_path.dart';
import 'package:ntou_app/src/ui/ntou_mark.dart';

/// 「海」的字形資料。
///
/// [kHaiPath] 是產生出來的（`tool/extract_glyph.py` → `tool/hai_path.json`），
/// 所以這裡測的不是「畫得好不好看」，是**它有沒有在某次重新產生之後悄悄變形**：
/// 座標範圍變了的話，呼叫端算的留白就全錯；指令長度錯一格，painter 會畫出
/// 一團垃圾但不會丟例外。這兩種都不會在畫面上看起來像 bug。
void main() {
  group('海的字形路徑', () {
    test('指令的參數個數都對得上', () {
      // 0 moveTo / 1 lineTo 各一個點、2 quadraticBezierTo 兩個、
      // 3 cubicTo 三個、-1 close 沒有。少一個數字整條路徑就從那裡開始歪。
      const arity = {0: 2, 1: 2, 2: 4, 3: 6, -1: 0};
      for (final op in kHaiPath) {
        final code = op[0].toInt();
        expect(arity.containsKey(code), isTrue, reason: '不認得的指令碼 $code');
        expect(op.length - 1, arity[code], reason: '指令 $code 的參數個數不對');
      }
    });

    test('十二個輪廓，每個都收尾', () {
      final opens = kHaiPath.where((op) => op[0] == 0).length;
      final closes = kHaiPath.where((op) => op[0] == -1).length;
      expect(opens, 12);
      // 沒收尾的輪廓在 nonZero 底下會被隱含地連回起點，形狀不一定壞 ——
      // 但那是碰運氣，不是設計。
      expect(closes, opens);
    });

    test('字身撐滿 0–100 並且置中', () {
      // 留白由呼叫端決定（icon.png 佔 76%、Android 前景層佔 60%）。
      // 這裡如果自己偷留白或偏一邊，那兩個比例就都算錯了。
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      for (final op in kHaiPath) {
        for (var i = 1; i < op.length; i += 2) {
          minX = minX < op[i] ? minX : op[i];
          maxX = maxX > op[i] ? maxX : op[i];
          minY = minY < op[i + 1] ? minY : op[i + 1];
          maxY = maxY > op[i + 1] ? maxY : op[i + 1];
        }
      }
      // 「海」比高略寬（948 × 944），正規化時取長邊，所以 x 剛好撐滿、
      // y 置中後上下各留一點點。
      expect(minX, closeTo(0, 0.01));
      expect(maxX, closeTo(100, 0.01));
      expect(minY, greaterThanOrEqualTo(0));
      expect(maxY, lessThanOrEqualTo(100));
      expect((minY + maxY) / 2, closeTo(50, 0.01));
    });

    test('icon.png 的字身比例跟 painter 是同一個數字', () {
      // 登入頁那格用 NtouMark.iconSpan 算大小，tool/render_icon.py 用
      // SPAN_ICON 出圖。兩個對不上的話，桌面圖示和 App 裡的標會不一樣大 ——
      // 而那正是當初換掉舊圖示的原因。
      expect(NtouMark.iconSpan, 0.76);
    });
  });

  testWidgets('畫得出來，而且尺寸是字身的大小', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: NtouMark(size: 48))),
    ));

    expect(tester.getSize(find.byType(NtouMark)), const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('指定顏色也畫得出來', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: NtouMark(size: 24, color: Colors.white)),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}

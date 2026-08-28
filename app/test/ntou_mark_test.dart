import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/ntou_mark.dart';

/// 稜面 N 的幾何。
///
/// 這裡釘的都是「改壞了也不會壞掉、只會變得怪怪的」那種比例 ——
/// 畫面上看不出是 bug，只覺得標醜了，所以沒有測試就會慢慢飄掉。
void main() {
  final facets = NtouMark.facets;

  group('稜面 N 的幾何', () {
    test('四片，一片不多一片不少', () {
      // 少一片字形就破了，多一片就開始糊 —— 現在那張 icon.jpg 的舵輪
      // 就是細節太多，在 40px 糊成一團。
      expect(facets, hasLength(4));
    });

    test('對角線的視覺粗細跟直桿打平', () {
      // 斜筆畫的視覺粗細不是垂直落差，是垂直落差除以 sqrt(1 + 斜率²)。
      // 這個換算漏掉的話，落差 16 看起來只有 8.9 粗 —— 比直桿細三分之一，
      // 對角線會像根牙籤。這是實際發生過的一版。
      const stemWidth = 14.0; // 38 - 24

      // 對角線上半那一片：(38,24) (50,39) (50,61) (38,46)
      final diagonal = facets[1].points;
      final topEdge = diagonal[1] - diagonal[0]; // (38,24) → (50,39)
      final verticalDrop = (diagonal[3] - diagonal[0]).dy; // 24 → 46

      final slope = topEdge.dy / topEdge.dx;
      final visualWidth = verticalDrop / math.sqrt(1 + slope * slope);

      // 斜筆畫本來就該比直筆略細一點點（不然視覺上會顯得更重），
      // 但差距要在一成以內。
      expect(visualWidth, lessThan(stemWidth));
      expect(visualWidth, greaterThan(stemWidth * 0.9));
    });

    test('接縫是共用的頂點，不是兩條剛好靠在一起的邊', () {
      // 四片是拼出來的、不是 clip 出來的，所以相鄰的兩片一定要共用頂點。
      // 差半個單位在大圖看不出來，縮到 29px 會出現一條背景色的裂縫。
      final diagUpper = facets[1].points;
      final diagLower = facets[2].points;

      // 上半的 (50,39)/(50,61) 就是下半的起點與終點
      expect(diagLower.first, diagUpper[1]);
      expect(diagLower.last, diagUpper[2]);
    });

    test('單色版四片各有各的階，不會黏成兩塊', () {
      // 彩色版有兩片都是 1.0，靠色相分開。單色沒有色相可用，
      // 四片就必須各給一階，不然對角線上半和左桿會連成一片。
      final steps = facets.map((f) => f.monoOpacity).toSet();
      expect(steps, hasLength(4));

      final sorted = steps.toList()..sort();
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i] - sorted[i - 1], greaterThan(0.1),
            reason: '相鄰兩階差太小，印出來分不開');
      }
    });

    test('字身撐滿 widget，四周不留白', () {
      // 留白由呼叫端決定（icon.png 佔 62%、Android 前景層佔 50%）。
      // 這裡如果自己偷留白，那兩個比例就都算錯了。
      var minX = double.infinity, maxX = -double.infinity;
      var minY = double.infinity, maxY = -double.infinity;
      for (final f in facets) {
        for (final p in f.points) {
          minX = math.min(minX, p.dx);
          maxX = math.max(maxX, p.dx);
          minY = math.min(minY, p.dy);
          maxY = math.max(maxY, p.dy);
        }
      }
      // 座標寫在 100 格裡，字身是 24–76
      expect(minX, 24);
      expect(maxX, 76);
      expect(minY, 24);
      expect(maxY, 76);
      expect(maxX - minX, maxY - minY, reason: '字身要是正方形，不然縮放會變形');
    });
  });

  testWidgets('畫得出來，而且尺寸是字身的大小', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: NtouMark(size: 48))),
    ));

    expect(tester.getSize(find.byType(NtouMark)), const Size(48, 48));
  });

  testWidgets('單色版也畫得出來', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: NtouMark(size: 24, color: Colors.white)),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:ntou_app/src/ui/timetable_grid.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: Scaffold(body: child),
      );

  group('TimetableGrid', () {
    testWidgets('沒有任何帶時段的課程時什麼都不畫', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(courses: [
          Course(name: '課A', slots: []),
          Course(name: '課B', slots: []),
        ])),
      );
      await tester.pumpAndSettle();

      // 沒有時段的課不進格子，但清單那邊還是會列 —— 見 TimetableGrid 的說明。
      expect(find.text('課A'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('連堂合成一塊，課名只出現一次', (tester) async {
      // 「102 103 104」是同一堂課上三節，不是三堂課。
      // 一格一格畫的話課名會重複三次，看起來像三門不同的課。
      await tester.pumpWidget(
        wrap(const TimetableGrid(
          today: 0,
          courses: [
            Course(
              name: '演算法',
              code: 'B5702P98',
              room: '電資201',
              slots: [TimeSlot(0, 2), TimeSlot(0, 3), TimeSlot(0, 4)],
            ),
          ],
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('演算法'), findsOneWidget);
      expect(find.text('電資201'), findsOneWidget);
    });

    testWidgets('中間斷開的節次各自一塊', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(
          today: 0,
          courses: [
            Course(
              name: '體育',
              code: 'B92A12P5',
              // 第 2 節和第 5 節，中間沒連著
              slots: [TimeSlot(0, 2), TimeSlot(0, 5)],
            ),
          ],
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('體育'), findsNWidgets(2));
    });

    testWidgets('平日只畫一到五，有週末課才擴', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(
          today: 0,
          courses: [
            Course(name: '演算法', code: 'A1', slots: [TimeSlot(0, 3)]),
          ],
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('一'), findsOneWidget);
      expect(find.text('五'), findsOneWidget);
      expect(find.text('六'), findsNothing);
      expect(find.text('日'), findsNothing);
    });

    testWidgets('有週末課程時動態擴展至週六或週日', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(
          today: 0,
          courses: [
            Course(
              name: '週末進修專題',
              code: 'W1',
              room: '海工B12',
              slots: [TimeSlot(5, 2), TimeSlot(6, 3)],
            ),
          ],
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('週末進修專題'), findsNWidgets(2));
      expect(find.text('六'), findsOneWidget);
      expect(find.text('日'), findsOneWidget);
    });

    testWidgets('螢幕閱讀器讀得出星期、節次範圍、課名和教室', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(
          today: 0,
          courses: [
            Course(
              name: '演算法',
              code: 'B5702P98',
              room: '電資201',
              slots: [TimeSlot(0, 2), TimeSlot(0, 3), TimeSlot(0, 4)],
            ),
          ],
        )),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('星期一第 2 到 4 節，演算法，電資201'),
        findsOneWidget,
      );
    });

  });

  group('課程顏色', () {
    test('由課號決定，不是清單順序', () {
      // 用順序決定的話，多加一門課就會讓所有顏色重排 ——
      // 使用者靠顏色認課，那等於每學期重新學一次。
      expect(
        TimetableGrid.colorFor('B5702P98'),
        TimetableGrid.colorFor('B5702P98'),
      );
      expect(
        TimetableGrid.colorFor('B5702P98'),
        isNot(TimetableGrid.colorFor('B5711M97')),
      );
    });

    test('顏色一定落在既有的模組色裡，不會冒出新顏色', () {
      for (final code in ['B5702P98', 'B5711M97', 'B57011RQ', '', '演算法']) {
        expect(NtouTheme.moduleColors, contains(TimetableGrid.colorFor(code)));
      }
    });
  });

  group('現在這一格', () {
    // 上學日掃一眼課表，最想知道的是「我現在該在哪」。標的是今天 × 現在
    // 這一節的交叉格，畫成一個外框（不是換底色）—— 底色會被課方塊蓋掉，
    // 外框畫在最上面，有課時框住那堂課、沒課時框住空格。
    const oneClass = TimetableGrid(
      today: 0, // 週一
      courses: [
        Course(
          name: '演算法',
          code: 'B5702P98',
          slots: [TimeSlot(0, 2), TimeSlot(0, 3), TimeSlot(0, 4)],
        ),
      ],
    );

    // 那個外框：primary 色、寬 2 的 Border。
    Finder nowBox() => find.byWidgetPredicate((w) {
          if (w is! DecoratedBox) return false;
          final d = w.decoration;
          return d is BoxDecoration &&
              d.border is Border &&
              (d.border as Border).top.width == 2;
        });

    testWidgets('現在正在上課的那一節被框起來', (tester) async {
      // 第 3 節（在課的範圍 2–4 裡）。
      await tester.pumpWidget(wrap(TimetableGrid(
        today: oneClass.today,
        nowPeriod: 3,
        courses: oneClass.courses,
      )));
      await tester.pumpAndSettle();
      expect(nowBox(), findsOneWidget);
    });

    testWidgets('下課時間（nowPeriod = null）不框任何一格', (tester) async {
      await tester.pumpWidget(wrap(TimetableGrid(
        today: oneClass.today,
        nowPeriod: null,
        courses: oneClass.courses,
      )));
      await tester.pumpAndSettle();
      expect(nowBox(), findsNothing);
    });

    testWidgets('今天沒被畫出來（假日）就不框', (tester) async {
      // 課表只畫一到五，今天是週日（today = 6）—— 沒有那一欄可框。
      await tester.pumpWidget(wrap(TimetableGrid(
        today: 6,
        nowPeriod: 3,
        courses: oneClass.courses,
      )));
      await tester.pumpAndSettle();
      expect(nowBox(), findsNothing);
    });

    testWidgets('現在這一節不在畫出來的範圍內就不框', (tester) async {
      // 格子只畫到第 4 節，現在是晚上第 12 節 —— 框出去會落在格子外。
      await tester.pumpWidget(wrap(TimetableGrid(
        today: oneClass.today,
        nowPeriod: 12,
        courses: oneClass.courses,
      )));
      await tester.pumpAndSettle();
      expect(nowBox(), findsNothing);
    });
  });
}

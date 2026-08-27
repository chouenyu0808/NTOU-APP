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

    test('顏色一定落在既有的 13 色裡，不會冒出新顏色', () {
      for (final code in ['B5702P98', 'B5711M97', 'B57011RQ', '', '演算法']) {
        expect(NtouTheme.moduleColors, contains(TimetableGrid.colorFor(code)));
      }
    });
  });
}

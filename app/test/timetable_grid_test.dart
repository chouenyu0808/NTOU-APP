import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/ui/timetable_grid.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: child),
      );

  group('TimetableGrid', () {
    testWidgets('沒有任何帶時段的課程時渲染 SizedBox.shrink()', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(courses: [
          Course(name: '課A', slots: []),
          Course(name: '課B', slots: []),
        ])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsNothing);
      expect(find.text('課A'), findsNothing);
    });

    testWidgets('有平日課程時正常渲染 DataTable，包含課名與教室', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(courses: [
          Course(
            name: '演算法',
            room: '電資201',
            slots: [TimeSlot(0, 3), TimeSlot(0, 4)],
          ),
          Course(
            name: '計算機結構',
            room: '綜一01',
            slots: [TimeSlot(2, 1)],
          ),
        ])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('演算法'), findsNWidgets(2)); // 第3節與第4節各一個
      expect(find.text('電資201'), findsNWidgets(2));
      expect(find.text('計算機結構'), findsOneWidget);
      expect(find.text('綜一01'), findsOneWidget);

      // 檢查星期表頭（至少一到五）
      expect(find.text('一'), findsOneWidget);
      expect(find.text('二'), findsOneWidget);
      expect(find.text('三'), findsOneWidget);
      expect(find.text('四'), findsOneWidget);
      expect(find.text('五'), findsOneWidget);
      // 無週末課程時不畫六、日
      expect(find.text('六'), findsNothing);
      expect(find.text('日'), findsNothing);
    });

    testWidgets('有週末課程時動態擴展至週六或週日', (tester) async {
      await tester.pumpWidget(
        wrap(const TimetableGrid(courses: [
          Course(
            name: '週末進修專題',
            room: '海工B12',
            slots: [TimeSlot(5, 2), TimeSlot(6, 3)], // 週六與週日
          ),
        ])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('週末進修專題'), findsNWidgets(2));
      expect(find.text('六'), findsOneWidget);
      expect(find.text('日'), findsOneWidget);
    });
  });
}

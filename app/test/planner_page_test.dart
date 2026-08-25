import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/planner/plan_models.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/planner_page.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

void main() {
  // 未登入時 PlannerPage 用民國年當 store 的 key（西元 - 1912）。
  // 測試用同一條公式算，不寫死某一年，才不會跨年就爛掉。
  String defaultYear() => '${DateTime.now().year - 1912}';

  late AppController controller;
  late PlanStore store;

  setUp(() async {
    controller = await newController();
    store = PlanStore(prefs: await SharedPreferences.getInstance());
  });

  Widget wrap() => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: PlannerPage(controller: controller, store: store),
      );

  Future<void> seed(List<PlannedCourse> courses) =>
      store.write(CoursePlan(
        year: defaultYear(),
        semester: '1',
        courses: courses,
      ));

  testWidgets('沒有預排課程時顯示空白引導', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('還沒有預排的課程'), findsOneWidget);
    expect(find.text('新增第一門課'), findsOneWidget);
  });

  testWidgets('新增課程：填課名送出後出現在清單，空白引導消失', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增課程')); // FAB
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, '課名 *'), '演算法');
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await tester.pumpAndSettle();

    expect(find.text('演算法'), findsOneWidget);
    expect(find.text('還沒有預排的課程'), findsNothing);
  });

  testWidgets('新增課程沒填課名會被擋下並提示', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增課程'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await tester.pumpAndSettle();

    // 驗證訊息出現，Dialog 沒有關掉。
    expect(find.text('請輸入課名'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '新增'), findsOneWidget);
  });

  testWidgets('新增的課程有寫進 store', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增課程'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, '課名 *'), '離散數學');
    await tester.tap(find.widgetWithText(FilledButton, '新增'));
    await tester.pumpAndSettle();

    final saved = await store.read(defaultYear(), '1');
    expect(saved, isNotNull);
    expect(saved!.courses.single.course.name, '離散數學');
  });

  testWidgets('有衝堂的預排會顯示紅色警告', (tester) async {
    // 兩門課共用（週一,第3節）。
    await seed(const [
      PlannedCourse(course: Course(name: '演算法'), slots: [TimeSlot(0, 3)]),
      PlannedCourse(course: Course(name: '計算機組織'), slots: [TimeSlot(0, 3)]),
    ]);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('衝堂'), findsOneWidget);
    expect(find.text('演算法'), findsWidgets);
    expect(find.text('計算機組織'), findsWidgets);
  });

  testWidgets('統計列出門數、學分，並把未填時段的課單獨標出來', (tester) async {
    await seed(const [
      PlannedCourse(
          course: Course(name: '演算法', credits: 3), slots: [TimeSlot(0, 3)]),
      PlannedCourse(
          course: Course(name: '計算機組織', credits: 3), slots: []), // 沒填時段
    ]);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('門課'), findsOneWidget);
    expect(find.text('學分'), findsOneWidget);
    expect(find.text('6.0'), findsOneWidget); // 3 + 3 學分
    // 沒填時段的課要單獨標出來 —— 那些排不進格子，也驗不了衝堂。
    expect(find.text('堂未填時段'), findsOneWidget);
  });

  testWidgets('刪除課程後從清單移除，並同步寫回 store', (tester) async {
    await seed(const [
      PlannedCourse(course: Course(name: '演算法'), slots: [TimeSlot(0, 3)]),
    ]);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    expect(find.text('演算法'), findsWidgets);

    await tester.tap(find.byTooltip('從預排移除'));
    await tester.pumpAndSettle();

    expect(find.text('演算法'), findsNothing);
    expect(find.text('還沒有預排的課程'), findsOneWidget);

    final saved = await store.read(defaultYear(), '1');
    expect(saved!.courses, isEmpty);
  });
}

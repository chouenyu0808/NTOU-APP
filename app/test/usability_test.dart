import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/planner/plan_models.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/auth_gate.dart';
import 'package:ntou_app/src/ui/home_page.dart';
import 'package:ntou_app/src/ui/login_page.dart';
import 'package:ntou_app/src/ui/planner_page.dart';
import 'package:ntou_app/src/ui/module_list_page.dart';
import 'package:ntou_app/src/ui/timetable_grid.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TimetableResult table(String year, String name) => TimetableResult(
    year: year,
    semester: '1',
    courses: [
      Course(name: name, slots: const [TimeSlot(0, 2)]),
    ],
    isEmpty: false,
    fetchedAt: DateTime(2026, 9, 14),
  );

  test('查閱舊學期不改變首頁當學期，重新開啟也讀同一份', () async {
    final c = await newController();
    c.defaultYear = '115';
    c.defaultSemester = '1';
    c.currentTimetable = table('115', '本學期課程');
    await c.repository.cache.saveCurrentSemester('115', '1');
    await c.repository.cache.write(c.currentTimetable!);
    await c.repository.cache.write(table('114', '去年的課程'));
    await c.selectSemester(newYear: '114', newSemester: '1');
    expect(c.timetable!.courses.single.name, '去年的課程');
    expect(c.homeTimetable!.courses.single.name, '本學期課程');
    await c.init();
    expect(c.homeTimetable!.courses.single.name, '本學期課程');
    c.dispose();
  });

  test('同一天不連續的同一門課分成兩段，中間不會被算成正在上課', () {
    final t = table('115', '測試');
    final segmented = HomePage.coursesOn(
      TimetableResult(
        year: t.year,
        semester: t.semester,
        isEmpty: false,
        fetchedAt: t.fetchedAt,
        courses: const [
          Course(
            name: '專題',
            slots: [TimeSlot(0, 2), TimeSlot(0, 3), TimeSlot(0, 7)],
          ),
        ],
      ),
      0,
    );
    expect(segmented.map((c) => c.slots.length), [2, 1]);
    expect(HomePage.periodLabel(segmented.last, 0), '第 7 節');
  });

  testWidgets('未登入仍可進主畫面與預排，取消登入會回原分頁', (tester) async {
    final c = await newController();
    await tester.pumpWidget(
      MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: AuthGate(
          controller: c,
          catalog: const MenuCatalog([]),
          planStore: PlanStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('交通'), findsOneWidget);
    await tester.tap(find.text('課表').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('預排').first);
    await tester.pumpAndSettle();
    expect(find.text('還沒有預排的課程'), findsOneWidget);
    await tester.tap(find.text('校務').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('登入').last);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('校務系統'), findsOneWidget);
    await unmount(tester);
    c.dispose();
  });

  testWidgets('刪除預排後可以復原完整時段與備註', (tester) async {
    final c = await newController();
    c.year = '115';
    c.semester = '1';
    final store = PlanStore(prefs: await SharedPreferences.getInstance());
    await store.write(
      const CoursePlan(
        year: '115',
        semester: '1',
        courses: [
          PlannedCourse(
            course: Course(name: '專題'),
            slots: [TimeSlot(0, 2)],
            note: '自己的備註',
            slotsAreManual: true,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: PlannerPage(controller: c, store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('從預排移除'));
    await tester.tap(find.byTooltip('從預排移除'));
    await tester.pumpAndSettle();
    expect((await store.read('115', '1'))!.courses, isEmpty);
    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();
    final restored = (await store.read('115', '1'))!.courses.single;
    expect(restored.slots, [const TimeSlot(0, 2)]);
    expect(restored.note, '自己的備註');
    await unmount(tester);
    c.dispose();
  });

  testWidgets('點課表可閱讀完整課名教室與時間', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: const Scaffold(
          body: TimetableGrid(
            courses: [
              Course(
                name: '非常長的課程名稱也能完整閱讀',
                room: '電資大樓非常長的教室名稱',
                teacher: '測試老師',
                slots: [TimeSlot(0, 2)],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('非常長的課程名稱也能完整閱讀'));
    await tester.pumpAndSettle();
    expect(find.text('教室　電資大樓非常長的教室名稱'), findsOneWidget);
    expect(find.text('星期一　第 2 節　09:20–10:10'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('小螢幕兩倍字體的服務清單不溢出，別稱也找得到功能', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await newController();
    await tester.pumpWidget(
      MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ModuleListPage(
          controller: c,
          catalog: const MenuCatalog([
            AisFunction(
              title: '缺曠課紀錄',
              path: 'GRD7050.aspx',
              trail: ['教務系統', '缺曠課紀錄'],
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), '缺課');
    await tester.pumpAndSettle();
    expect(find.text('缺曠課紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
    c.dispose();
  });
}

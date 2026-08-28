import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/planner/plan_models.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/course_browser_page.dart';
import 'package:ntou_app/src/ui/planner_page.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

void main() {
  // 未登入時 PlannerPage 用當下的學年度當 store 的 key。
  //
  // **借正式的那個函式，不要在這裡重抄一次公式。** 原本這裡寫死
  // `西元 - 1912`，跟正式碼裡那條錯的公式一模一樣 —— 兩邊一起錯，
  // 測試就永遠是綠的。學年度八月才換，八月到十二月那五個月
  // `- 1912` 會少算一年。
  String defaultYear() => '${PlannerPage.rocAcademicYear(DateTime.now())}';
  String defaultSemester() => PlannerPage.academicSemester(DateTime.now());

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
        semester: defaultSemester(),
        courses: courses,
      ));

  testWidgets('沒有預排課程時顯示空白引導', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('還沒有預排的課程'), findsOneWidget);
    expect(find.text('去挑第一門課'), findsOneWidget);
  });

  testWidgets('新增課程直接進課程瀏覽頁，不先問「你想用哪種方式找課」', (tester) async {
    // 以前 FAB 會先跳一層 bottom sheet 問「從學校課程選 / 手動輸入」。
    // 那層 sheet 逼每個人在「我要找課」之前先回答一個九成答案都一樣的問題；
    // 手動輸入是查不到時候的退路，不是入口，所以搬到瀏覽頁的 ⋮ 去了。
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增課程')); // FAB
    await tester.pumpAndSettle();

    expect(find.byType(CourseBrowserPage), findsOneWidget);
    // 中間那層選單不該再出現。（「從學校課程選」不能拿來驗 ——
    // 那是瀏覽頁自己的標題，本來就會在。）
    expect(find.text('手動輸入'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    await unmount(tester);
  });

  testWidgets('空白引導的按鈕跟 FAB 去同一個地方', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('去挑第一門課'));
    await tester.pumpAndSettle();

    expect(find.byType(CourseBrowserPage), findsOneWidget);
    await unmount(tester);
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

  group('時段格子的範圍', () {
    Future<void> openPicker(WidgetTester tester, List<TimeSlot> slots) async {
      await seed([
        PlannedCourse(course: const Course(name: '演算法'), slots: slots),
      ]);
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '編輯'));
      await tester.pumpAndSettle();
    }

    /// 只找對話框裡的格子 —— 後面那一頁的統計也是純數字，會誤中。
    Finder inPicker(String label) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(label),
        );

    testWidgets('格子讀得出「星期幾第幾節」', (tester) async {
      // 空格子只有底色，沒有 Semantics 的話螢幕閱讀器一片沉默 ——
      // 使用者不知道游標停在哪一格。
      await openPicker(tester, const [TimeSlot(0, 3)]);

      expect(
        find.bySemanticsLabel('星期一第 3 節'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('星期三第 5 節'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('預設只畫一～五、第 1–13 節', (tester) async {
      await openPicker(tester, const [TimeSlot(0, 3)]);

      expect(inPicker('一'), findsOneWidget);
      expect(inPicker('五'), findsOneWidget);
      expect(inPicker('1'), findsOneWidget);
      expect(inPicker('13'), findsOneWidget);

      // 學校的 Q_WEEK 有六日、Q_CLASS 有 00 和 14–16，但實際上幾乎沒課排在那裡。
      // 全部攤開的話手機上每一格會細到點不準。
      expect(inPicker('六'), findsNothing);
      expect(inPicker('日'), findsNothing);
      expect(inPicker('0'), findsNothing);
      expect(inPicker('14'), findsNothing);
    });

    testWidgets('有課排在第 14 節，格子就往下長出來', (tester) async {
      await openPicker(tester, const [TimeSlot(0, 14)]);

      expect(inPicker('14'), findsOneWidget);
      expect(inPicker('13'), findsOneWidget); // 中間不能跳號
      expect(inPicker('15'), findsNothing); // 只長到真的用到的那一節
    });

    testWidgets('有課排在第 0 節，格子就往上長出來', (tester) async {
      await openPicker(tester, const [TimeSlot(0, 0)]);

      expect(inPicker('0'), findsOneWidget);
      expect(inPicker('1'), findsOneWidget);
    });

    testWidgets('有課排在週六，欄位就往右長出來', (tester) async {
      await openPicker(tester, const [TimeSlot(5, 3)]);

      expect(inPicker('六'), findsOneWidget);
      expect(inPicker('日'), findsNothing); // 只長到用得到的那一天
    });

    testWidgets('自動帶入的怪時段點得掉 —— 畫不出來的格子等於刪不掉', (tester) async {
      // 只有「從學校課程自動帶入」會產生這種時段：parser 收得下 1–7 × 00–16，
      // 手動填的人只點得到畫得出來的格子。格子畫不出來的話，使用者看到的是
      // 「加進來了但格子是空的」，而且那一節還刪不掉。
      await openPicker(tester, const [TimeSlot(6, 16)]);

      expect(inPicker('日'), findsOneWidget);
      expect(inPicker('16'), findsOneWidget);

      // 選中的格子是打勾的那一格（不是最左邊的節次標題）。
      // 展開到 7 天 × 16 節之後格子超出畫面，先捲過去 —— 這也正是預設不畫滿的原因。
      final checked = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.check),
      );
      await tester.ensureVisible(checked);
      await tester.pumpAndSettle();
      await tester.tap(checked);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '儲存'));
      await tester.pumpAndSettle();

      expect(find.text('點此填入上課時間'), findsOneWidget);
    });
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

    final saved = await store.read(defaultYear(), defaultSemester());
    expect(saved!.courses, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/announcements.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/home_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TimetableResult result({
    required List<Course> courses,
    bool isEmpty = false,
  }) =>
      TimetableResult(
        year: '115',
        semester: '1',
        courses: courses,
        isEmpty: isEmpty,
        fetchedAt: DateTime(2026, 8, 27),
      );

  Widget wrap(AppController c) => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: HomePage(controller: c, onOpenTab: (_) {}),
      );

  group('今天是星期幾', () {
    test('DateTime 的 1 = 週一，要對齊 TimeSlot 的 0 = 週一', () {
      // 差一格的話整頁會顯示隔壁那天的課，而畫面上完全看不出來。
      expect(HomePage.todayIndex(DateTime(2026, 8, 24)), 0); // 週一
      expect(HomePage.todayIndex(DateTime(2026, 8, 27)), 3); // 週四
      expect(HomePage.todayIndex(DateTime(2026, 8, 30)), 6); // 週日
    });
  });

  group('挑出今天的課', () {
    test('只留今天有的，並照第一節排序', () {
      final t = result(courses: const [
        Course(name: '作業系統', slots: [TimeSlot(0, 5)]),
        Course(name: '演算法', slots: [TimeSlot(0, 2), TimeSlot(0, 3)]),
        Course(name: '計算機概論', slots: [TimeSlot(3, 2)]), // 週四，不是今天
      ]);

      expect(
        HomePage.coursesOn(t, 0).map((c) => c.name),
        ['演算法', '作業系統'],
      );
    });

    test('沒有課表就是空的，不要爆掉', () {
      expect(HomePage.coursesOn(null, 0), isEmpty);
    });
  });

  group('節次標籤', () {
    Course at(List<int> periods) => Course(
          name: 'x',
          slots: [for (final p in periods) TimeSlot(0, p)],
        );

    test('連續的收成範圍', () {
      expect(HomePage.periodLabel(at([2, 3, 4]), 0), '第 2-4 節');
    });

    test('只有一節就不要寫成範圍', () {
      expect(HomePage.periodLabel(at([2]), 0), '第 2 節');
    });

    test('不連續的要列出來，不能假裝是範圍', () {
      // 「第 2-5 節」會讓人以為中間兩節也要到，那是四節不是兩節。
      expect(HomePage.periodLabel(at([2, 5]), 0), '第 2、5 節');
    });

    test('那一天沒課就是空字串', () {
      expect(HomePage.periodLabel(at([2]), 3), isEmpty);
    });
  });

  group('今日課程的四種狀態', () {
    testWidgets('完全沒有課表資料', (tester) async {
      final c = await newController();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('還沒有課表資料'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('學校回「查無符合資料」時，不要編一個開學日期出來', (tester) async {
      final c = await newController(
        cached: result(courses: const [], isEmpty: true),
      );
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('這學期還沒有選課資料'), findsOneWidget);

      // 校園行事曆不在學校的學生選單裡 —— 我們沒有開學日這份資料。
      // 寫死一個日期今年看起來很貼心，明年就是錯的。
      // （頁首本來就會顯示今天的日期，那是真的；這裡防的是「開學日 X 月 X 日」
      // 那種我們根本沒有來源的資訊。）
      expect(find.textContaining('開學'), findsNothing);
      await unmount(tester);
    });

    testWidgets('有課表但今天沒課', (tester) async {
      // 把課排在「今天以外」的某一天，測試才不會跟著星期幾而時好時壞。
      final today = HomePage.todayIndex(DateTime.now());
      final other = (today + 1) % 7;
      final c = await newController(
        cached: result(courses: [
          Course(name: '演算法', slots: [TimeSlot(other, 2)]),
        ]),
      );
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.textContaining('沒有課'), findsOneWidget);
      expect(find.text('演算法'), findsNothing);
      await unmount(tester);
    });

    testWidgets('今天有課：課名、老師、教室都列出來', (tester) async {
      final today = HomePage.todayIndex(DateTime.now());
      final c = await newController(
        cached: result(courses: [
          Course(
            name: '計算機概論',
            teacher: '許為元',
            room: 'INS105',
            slots: [TimeSlot(today, 2), TimeSlot(today, 3), TimeSlot(today, 4)],
          ),
        ]),
      );
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('計算機概論'), findsOneWidget);
      expect(find.text('許為元 · INS105'), findsOneWidget);
      // 左邊那格是節次範圍
      expect(find.text('2-4'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('校園公告', () {
    testWidgets('沒登入時說明它是登入時順便拿到的', (tester) async {
      final c = await newController();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('登入後顯示校園公告'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('列出標題、日期和發布單位', (tester) async {
      final c = await newController();
      c.announcements = [
        Announcement(
          title: '學生宿舍開放入住首二日',
          unit: '學務處住宿輔導組',
          id: '9005901',
          date: DateTime(2026, 8, 26),
        ),
      ];
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('學生宿舍開放入住首二日'), findsOneWidget);
      // 年份對「最近的公告」沒有資訊量，位置留給標題
      expect(find.text('8/26  ·  學務處住宿輔導組'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('只列最近 5 則 —— 首頁是順手看一眼的地方', (tester) async {
      final c = await newController();
      c.announcements = [
        for (var i = 0; i < 12; i++)
          Announcement(title: '公告 $i', unit: '單位', date: DateTime(2026, 8, 26)),
      ];
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('公告 0'), findsOneWidget);
      expect(find.text('公告 4'), findsOneWidget);
      expect(find.text('公告 5'), findsNothing);
      await unmount(tester);
    });
  });

  group('快捷', () {
    testWidgets('三個快捷各自切到對應的分頁', (tester) async {
      final c = await newController();
      final opened = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: HomePage(controller: c, onOpenTab: opened.add),
      ));
      await tester.pumpAndSettle();

      for (final label in ['完整課表', '預排課表', '校務系統']) {
        // 公告區塊把快捷推到畫面外了 —— 捲過去再點，不然 tap 會靜靜地沒反應。
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(opened, [1, 2, 3]);
      await unmount(tester);
    });
  });
}

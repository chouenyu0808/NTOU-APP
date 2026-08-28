import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/config/period_times.dart';
import 'package:ntou_app/src/parsing/academic_calendar.dart';
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

  /// 今天，但時間固定在 [hour]:[minute]。
  ///
  /// 日期跟著今天走（課要排在「今天」才看得到），但**時鐘一定要固定**：
  /// 節次時間表填進去之後這一頁的內容就跟現在幾點有關，讀真正的時鐘的話
  /// 同一份測試早上綠、晚上紅，而失敗訊息完全看不出跟時間有關。
  DateTime todayAt(int hour, int minute) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, hour, minute);
  }

  Widget wrap(AppController c, {DateTime? now}) => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: HomePage(controller: c, now: now),
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

  group('已結束 / 下一堂 / 今天還有', () {
    // 節次時間表學校系統裡沒有（見 PeriodTimes 的說明），所以正式執行時
    // PeriodTimes.ntou 是空的。這裡塞一份假的進去測邏輯本身 ——
    // 資料到手的那天只要填 PeriodTimes.ntou，這些行為就會照著亮起來。
    const times = PeriodTimes({
      1: (start: 8 * 60 + 10, end: 9 * 60),
      2: (start: 9 * 60 + 10, end: 10 * 60),
      3: (start: 10 * 60 + 10, end: 11 * 60),
      4: (start: 11 * 60 + 10, end: 12 * 60),
    });

    Course at(String name, List<int> periods) =>
        Course(name: name, slots: [for (final p in periods) TimeSlot(0, p)]);

    test('上完的歸「已結束」，接下來那堂是 next', () {
      final today = [at('微積分', [1]), at('演算法', [3, 4])];

      // 09:30 —— 微積分（8:10–9:00）上完了，演算法還沒開始
      final r = HomePage.split(today, 0, times, 9 * 60 + 30);
      expect(r.done.map((c) => c.name), ['微積分']);
      expect(r.next!.name, '演算法');
      expect(r.later, isEmpty);
    });

    test('正在上的那堂算 next，不算已結束', () {
      // 10:30 落在演算法（第 3 節 10:10–11:00）之內。
      // 算成「已結束」的話，人還在教室裡，首頁卻說今天沒課了。
      final r = HomePage.split(
        [at('演算法', [3, 4])],
        0,
        times,
        10 * 60 + 30,
      );
      expect(r.done, isEmpty);
      expect(r.next!.name, '演算法');
    });

    test('連堂要整堂上完才算結束', () {
      // 11:30 —— 第 3 節結束了，但第 4 節（11:10–12:00）還在上。
      final r = HomePage.split(
        [at('演算法', [3, 4])],
        0,
        times,
        11 * 60 + 30,
      );
      expect(r.done, isEmpty);
      expect(r.next!.name, '演算法');
    });

    test('全部上完就沒有 next', () {
      final r = HomePage.split([at('微積分', [1])], 0, times, 23 * 60);
      expect(r.done.map((c) => c.name), ['微積分']);
      expect(r.next, isNull);
    });

    test('沒有節次時間表時全部算成還沒上', () {
      // 分不出來的時候就不要分。猜錯的代價是使用者看到「已結束」
      // 而錯過一堂還沒上的課 —— 而且畫面上完全看不出來是猜的。
      final today = [at('微積分', [1]), at('演算法', [3])];
      final r = HomePage.split(today, 0, PeriodTimes.unknown, 23 * 60);
      expect(r.done, isEmpty);
      expect(r.next!.name, '微積分');
      expect(r.later.map((c) => c.name), ['演算法']);
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

    testWidgets('有課但一門都沒有時間：不要說「今天沒有課」', (tester) async {
      // **這是真實資料的常態，不是例外。** 學校這個 UI 的選課清單檢視回的
      // 17 欄裡完全沒有上課時間和教室（2026-08-25 實測），所以正常登入的
      // 使用者拿到的每一門課 slots 都是空的。
      //
      // 舊的判斷只看「今天有沒有課」，而空 slots 永遠對不到今天 ——
      // 結果首頁會拿一個咖啡杯圖示對每一個人說「今天沒有課」，
      // 而他其實第二節就要進教室。編一個錯的答案比承認不知道糟得多。
      final c = await newController(
        cached: result(courses: const [
          Course(name: '演算法'),
          Course(name: '計算機組織'),
        ]),
      );
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.textContaining('今天沒有課'), findsNothing,
          reason: '我們不知道他今天有沒有課，不能說沒有');
      expect(find.textContaining('沒有上課時間'), findsOneWidget);
      // 有幾門課是我們真的知道的，講出來 —— 至少證明資料抓到了。
      expect(find.textContaining('2 門課'), findsOneWidget);
      await unmount(tester);
    });

    /// 今天第 2–4 節有一門課（09:20 開始、12:05 結束）。
    Future<AppController> withMorningClass() async {
      final today = HomePage.todayIndex(DateTime.now());
      return newController(
        cached: result(courses: [
          Course(
            name: '計算機概論',
            teacher: '許為元',
            room: 'INS105',
            slots: [TimeSlot(today, 2), TimeSlot(today, 3), TimeSlot(today, 4)],
          ),
        ]),
      );
    }

    testWidgets('還沒開始：說「下一堂」、幾點到幾點、還有多久', (tester) async {
      // 首頁真正要回答的問題只有一個：「等一下有什麼課、在哪間教室」。
      // 那不該是清單裡長得跟其他人一樣的第三列。
      await tester.pumpWidget(
        wrap(await withMorningClass(), now: todayAt(7, 0)),
      );
      await tester.pumpAndSettle();

      expect(find.text('計算機概論'), findsOneWidget);
      expect(find.text('第 2-4 節 · INS105 · 許為元'), findsOneWidget);
      expect(find.text('下一堂'), findsOneWidget);
      // 第 2 節是 09:20–10:10（教務處的節次時間對照表）
      expect(find.text('09:20–10:10'), findsOneWidget);
      // 07:00 到 09:20 是 140 分鐘
      expect(find.text('還有 2 小時 20 分'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('正在上：說「現在」，而且不要再倒數', (tester) async {
      // 09:40 落在第 2 節（09:20–10:10）之內。
      await tester.pumpWidget(
        wrap(await withMorningClass(), now: todayAt(9, 40)),
      );
      await tester.pumpAndSettle();

      expect(find.text('現在'), findsOneWidget);
      expect(find.text('下一堂'), findsNothing);
      // 已經開始了就沒有「還有幾分鐘」可言
      expect(find.textContaining('還有'), findsNothing);
      await unmount(tester);
    });

    testWidgets('連堂要整堂上完才算結束', (tester) async {
      // 11:30 —— 第 2、3 節結束了，但第 4 節（11:15–12:05）還在上。
      // 算成已結束的話，人還在教室裡，首頁卻說今天的課上完了。
      await tester.pumpWidget(
        wrap(await withMorningClass(), now: todayAt(11, 30)),
      );
      await tester.pumpAndSettle();

      expect(find.text('現在'), findsOneWidget);
      expect(find.text('今天已經上完 1 堂'), findsNothing);
      await unmount(tester);
    });

    testWidgets('全部上完：收成一行，不再有主角', (tester) async {
      await tester.pumpWidget(
        wrap(await withMorningClass(), now: todayAt(20, 0)),
      );
      await tester.pumpAndSettle();

      expect(find.text('今天已經上完 1 堂'), findsOneWidget);
      expect(find.text('現在'), findsNothing);
      expect(find.text('下一堂'), findsNothing);
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

  group('近期行事曆', () {
    CalendarEvent ev(String title, DateTime start, [DateTime? end]) =>
        CalendarEvent(title: title, start: start, end: end ?? start);

    testWidgets('抓不到就整區不畫，不要放一張「載入失敗」的卡', (tester) async {
      // 行事曆在學校官網上，官網掛掉或手機沒網路都會是空的。
      // 那時候放一張錯誤卡沒幫到任何人 —— 使用者也不能拿它做什麼。
      final c = await newController();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('近期行事曆'), findsNothing);
      await unmount(tester);
    });

    testWidgets('列出接下來幾筆，日期在左邊', (tester) async {
      final c = await newController();
      final now = DateTime.now();
      c.calendarEvents = [
        ev('開學', now.add(const Duration(days: 3))),
        ev('加退選', now.add(const Duration(days: 10)),
            now.add(const Duration(days: 17))),
      ];
      c.notifyListeners();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('近期行事曆'), findsOneWidget);
      expect(find.text('開學'), findsOneWidget);
      expect(find.text('加退選'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('進行中的要標出來 —— 光看日期會被當成過去了', (tester) async {
      final now = DateTime.now();
      final c = await newController();
      c.calendarEvents = [
        ev('選課', now.subtract(const Duration(days: 2)),
            now.add(const Duration(days: 5))),
      ];
      c.notifyListeners();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('選課'), findsOneWidget);
      // 副標是「到 X/Y · 進行中」——結束日和狀態併成一行，
      // 兩行疊在 leading 裡會把 ListTile 撐破。
      expect(find.textContaining('進行中'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('結束了的不再顯示', (tester) async {
      final c = await newController();
      c.calendarEvents = [
        ev('去年的事', DateTime(2020, 1, 1)),
      ];
      c.notifyListeners();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('去年的事'), findsNothing);
      await unmount(tester);
    });
  });

  group('快捷', () {
    testWidgets('只留「畢業必修」—— 其餘三張只是把底部分頁列再列一次', (tester) async {
      // 「完整課表」「預排課表」「校務系統」在分頁列上都各有一個入口。
      // 同一個目的地給兩個入口沒有讓人更快到，只是讓首頁更長。
      final c = await newController();
      await tester.pumpWidget(wrap(c));
      await tester.pumpAndSettle();

      expect(find.text('畢業必修'), findsOneWidget);
      expect(find.text('完整課表'), findsNothing);
      expect(find.text('預排課表'), findsNothing);
      expect(find.text('校務系統'), findsNothing);
      await unmount(tester);
    });
  });
}

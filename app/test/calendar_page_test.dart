import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/academic_calendar.dart';
import 'package:ntou_app/src/ui/calendar_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

/// 整學期行事曆頁。
void main() {
  final now = DateTime(2026, 9, 9);

  CalendarEvent ev(String title, DateTime start, [DateTime? end]) =>
      CalendarEvent(title: title, start: start, end: end ?? start);

  Future<void> pump(WidgetTester tester, List<CalendarEvent> events) =>
      tester.pumpWidget(MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: CalendarPage(events: events, now: now),
      ));

  testWidgets('接下來的直接看得到，已過去的收在摺疊區', (tester) async {
    await pump(tester, [
      ev('開學', DateTime(2026, 9, 7)), // 過去
      ev('加退選截止', DateTime(2026, 9, 19)), // 未來
    ]);
    await tester.pumpAndSettle();

    // 未來的直接可見；過去的先藏在「已過去的 1 筆」裡。
    expect(find.text('加退選截止'), findsOneWidget);
    expect(find.text('開學'), findsNothing);
    expect(find.textContaining('已過去的 1 筆'), findsOneWidget);
  });

  testWidgets('展開就看得到過去的事件', (tester) async {
    await pump(tester, [ev('開學', DateTime(2026, 9, 7))]);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('已過去的'));
    await tester.pumpAndSettle();
    expect(find.text('開學'), findsOneWidget);
  });

  testWidgets('全部都在未來時，不出現「已過去」摺疊區', (tester) async {
    await pump(tester, [ev('期末考', DateTime(2027, 1, 12))]);
    await tester.pumpAndSettle();
    expect(find.textContaining('已過去'), findsNothing);
    expect(find.text('期末考'), findsOneWidget);
  });

  testWidgets('照日期排序，不管傳進來的順序', (tester) async {
    // 學校那頁的按鈕是照版面排的，不保證是時間序。
    await pump(tester, [
      ev('晚的', DateTime(2026, 12, 1)),
      ev('早的', DateTime(2026, 10, 1)),
    ]);
    await tester.pumpAndSettle();

    final early = tester.getTopLeft(find.text('早的')).dy;
    final late = tester.getTopLeft(find.text('晚的')).dy;
    expect(early, lessThan(late), reason: '早的要排在上面');
  });

  testWidgets('進行中的事件標「進行中」，不當成過去', (tester) async {
    // 開始日在上禮拜、結束日在下禮拜 —— 光看開始日會被當成過去了。
    await pump(tester, [
      ev('選課週', DateTime(2026, 9, 5), DateTime(2026, 9, 15)),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('選課週'), findsOneWidget); // 在「接下來」，沒被收起來
    expect(find.textContaining('進行中'), findsOneWidget);
    expect(find.textContaining('已過去'), findsNothing);
  });

  testWidgets('跨年的一月不會跟去年一月併在同一個月標底下', (tester) async {
    await pump(tester, [
      ev('這學期', DateTime(2027, 1, 5)),
      // （沒有去年一月的事件，但月標的鍵要含年份才不會誤併 —— 這裡驗年份有印出來）
    ]);
    await tester.pumpAndSettle();
    expect(find.text('2027 年 1 月'), findsOneWidget);
  });
}

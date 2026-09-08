import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:ntou_app/src/ui/timetable_page.dart';

/// 課表頂端那條狀態列。邏輯在 class_status_test，這裡釘的是**畫出來的字**
/// —— 四種狀態各講什麼、時間怎麼寫。講錯不會報錯，只會讓人照著遲到。
void main() {
  // 2026-09-07 是星期一。用它加時刻組出各種「現在」。
  DateTime mon(int h, int m) => DateTime(2026, 9, 7, h, m);

  const courses = [
    Course(name: '演算法', code: 'A', slots: [
      TimeSlot(0, 2), // 09:20
      TimeSlot(0, 3),
      TimeSlot(0, 4), // …12:05
    ]),
    Course(name: '程式設計', code: 'B', slots: [TimeSlot(0, 7)]), // 14:10–15:00
  ];

  Future<void> pump(WidgetTester tester, DateTime now) => tester.pumpWidget(
        MaterialApp(
          theme: NtouTheme.of(Brightness.light),
          home: Scaffold(body: NowStatus(courses: courses, now: now)),
        ),
      );

  testWidgets('上課中：講課名和還有多久下課', (tester) async {
    await pump(tester, mon(10, 0)); // 演算法上到 12:05
    expect(find.textContaining('演算法'), findsOneWidget);
    expect(find.textContaining('下課'), findsOneWidget);
  });

  testWidgets('超過一小時寫「小時」，不是「125 分鐘」', (tester) async {
    await pump(tester, mon(10, 0)); // 到 12:05 還有 2 小時 5 分
    expect(find.textContaining('2 小時 5 分'), findsOneWidget);
    expect(find.textContaining('125'), findsNothing);
  });

  testWidgets('下課、還有下一堂：講下一堂和開始時間', (tester) async {
    await pump(tester, mon(12, 30)); // 下一堂 程式設計 14:10
    expect(find.textContaining('下一堂 程式設計'), findsOneWidget);
    expect(find.textContaining('14:10'), findsOneWidget);
  });

  testWidgets('都上完了', (tester) async {
    await pump(tester, mon(16, 0));
    expect(find.text('今天的課都上完了'), findsOneWidget);
  });

  testWidgets('假日沒有課', (tester) async {
    await pump(tester, DateTime(2026, 9, 6, 10, 0)); // 星期日
    expect(find.text('今天沒有課'), findsOneWidget);
  });

  testWidgets('自己不養計時器 —— 每分鐘重算是父層在做的', (tester) async {
    // 計時器放在課表頁的 _Body：一個就把這條狀態列和格子裡「現在這一格」
    // 的外框一起更新。這個 widget 自己開一個的話會變成兩個各跑各的。
    //
    // 驗法：不注入時間（正式行為）pump 過幾分鐘，結束時若有殘留的計時器，
    // testWidgets 會自己判定失敗。
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: NowStatus(courses: courses)),
    ));
    await tester.pump(const Duration(minutes: 2));
  });
}

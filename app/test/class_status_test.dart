import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/config/period_times.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/ui/class_status.dart';

/// 「現在課上到哪了」。這是「算錯不會報錯」的那一類 —— 每個邊界都要釘。
void main() {
  final t = PeriodTimes.ntou;
  int at(int h, int m) => h * 60 + m;

  // 週一：演算法 2–4 節（09:20–12:05，含中間 11:10–11:15 的下課），
  //       以及 程式設計 第 7 節（14:10–15:00）。
  const monday = [
    Course(name: '演算法', code: 'A', slots: [
      TimeSlot(0, 2),
      TimeSlot(0, 3),
      TimeSlot(0, 4),
    ]),
    Course(name: '程式設計', code: 'B', slots: [TimeSlot(0, 7)]),
  ];

  ClassStatus? status(int nowMinutes, {int weekday = 0}) => classStatus(
        courses: monday,
        times: t,
        weekday: weekday,
        nowMinutes: nowMinutes,
      );

  test('上課中：算到這一段連堂結束，不是這一節', () {
    // 第 3 節上到一半（10:00）。演算法連到第 4 節，12:05 才下課。
    final s = status(at(10, 0));
    expect(s, isA<InClass>());
    s as InClass;
    expect(s.course.name, '演算法');
    // 到 12:05 還有 125 分鐘 —— 不是到第 3 節結束（11:10）的 70 分鐘。
    expect(s.minutesLeft, at(12, 5) - at(10, 0));
  });

  test('**連堂中間那 5 分鐘的下課，仍然算在課內**', () {
    // 11:12 落在第 3 節（…11:10）和第 4 節（11:15…）之間。
    // periodAt 在這裡會回 null，但學生還在演算法的課堂上。
    final s = status(at(11, 12));
    expect(s, isA<InClass>(), reason: '連堂中間的下課不該被當成「下課了」');
    expect((s as InClass).course.name, '演算法');
  });

  test('下課、還有下一堂：報下一堂和幾分鐘後', () {
    // 12:30，演算法上完了，下一堂程式設計 14:10 開始。
    final s = status(at(12, 30));
    expect(s, isA<NextClass>());
    s as NextClass;
    expect(s.course.name, '程式設計');
    expect(s.minutesUntil, at(14, 10) - at(12, 30));
    expect(s.startMinute, at(14, 10));
  });

  test('第一堂還沒開始：一樣是「下一堂」', () {
    // 早上 08:00，第一堂 09:20。
    final s = status(at(8, 0));
    expect(s, isA<NextClass>());
    expect((s as NextClass).course.name, '演算法');
  });

  test('今天的課都上完了', () {
    // 16:00，最後一堂程式設計 15:00 已經結束。
    expect(status(at(16, 0)), isA<DoneForToday>());
  });

  test('剛好在下課那一刻算已經下課，不是還在課內', () {
    // 12:05 整 —— 區間是左閉右開 [.., 12:05)，所以 12:05 已經不在課內。
    final s = status(at(12, 5));
    expect(s, isA<NextClass>(), reason: '12:05 是演算法的結束時刻，不該還算上課中');
  });

  test('今天沒有排課（假日）', () {
    // 週日（weekday = 6），monday 的課都在週一。
    expect(status(at(10, 0), weekday: 6), isA<NoClassToday>());
  });

  test('沒有節次時間資料就回 null，什麼都不顯示', () {
    final s = classStatus(
      courses: monday,
      times: PeriodTimes.unknown,
      weekday: 0,
      nowMinutes: at(10, 0),
    );
    expect(s, isNull);
  });

  test('沒有帶時段的課不會被當成今天的課', () {
    final s = classStatus(
      courses: const [Course(name: '沒排進去的課', slots: [])],
      times: t,
      weekday: 0,
      nowMinutes: at(10, 0),
    );
    expect(s, isA<NoClassToday>());
  });
}

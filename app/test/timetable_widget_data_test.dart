import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/config/period_times.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/widget/timetable_widget_data.dart';

/// 桌面小組件的課表 payload。
///
/// 這裡驗的每一件事都屬於「猜錯不會有錯誤訊息」那一類 —— 畫面上會是一個
/// 看起來完全合理的東西，只是說的是別天、別堂、或別的時間。
void main() {
  // 2026-09-03 是星期四。**星期幾要寫死在測試裡**，
  // 用 DateTime.now().weekday 算的話這個測試自己就會跟著今天變。
  const thursday = 3; // 0 = 週一

  Course course(
    String name, {
    required List<int> periods,
    int weekday = thursday,
    String room = '',
  }) =>
      Course(
        name: name,
        room: room,
        slots: [for (final p in periods) TimeSlot(weekday, p)],
      );

  TimetableResult table(List<Course> courses) => TimetableResult(
        year: '114',
        semester: '1',
        courses: courses,
        isEmpty: false,
        fetchedAt: DateTime(2026, 9, 3, 7),
      );

  DateTime at(int hour, int minute) => DateTime(2026, 9, 3, hour, minute);

  group('沒有課可以顯示時說的話', () {
    test('還沒有課表，不能說成「今天沒有課」', () {
      final p = buildTimetableWidgetPayload(timetable: null, now: at(9, 0));

      // 這兩件事對使用者的意義完全相反：一個是「去開 App 登入」，
      // 一個是「今天可以睡晚一點」。
      expect(p.emptyMessage, contains('還沒有課表'));
      expect(p.emptyMessage, isNot(contains('今天沒有課')));
      expect(p.rows, isEmpty);
    });

    test('有課表但今天沒課', () {
      final p = buildTimetableWidgetPayload(
        // 課排在星期一，而「今天」是星期四。
        timetable: table([course('程式設計', periods: [2, 3], weekday: 0)]),
        now: at(9, 0),
      );

      expect(p.emptyMessage, '今天沒有課');
      expect(p.rows, isEmpty);
    });

    test('沒課的時候只排換日那一次', () {
      final p = buildTimetableWidgetPayload(timetable: null, now: at(9, 0));

      expect(p.updateTimes, [DateTime(2026, 9, 4)]);
    });
  });

  group('今天的課', () {
    test('照第一節排序，節次和時間都算好', () {
      final p = buildTimetableWidgetPayload(
        timetable: table([
          course('下午的課', periods: [6, 7], room: 'A101'),
          course('早上的課', periods: [2, 3, 4], room: 'B202'),
        ]),
        now: at(7, 0),
      );

      expect(p.rows.map((r) => r.name), ['早上的課', '下午的課']);
      expect(p.rows[0].period, '第 2-4 節');
      // 第 2 節 09:20 開始、第 4 節 12:05 結束。
      expect(p.rows[0].time, '09:20–12:05');
      expect(p.rows[0].room, 'B202');
      expect(p.rows[1].period, '第 6-7 節');
    });

    test('星期天的課不會跑到星期四來', () {
      // 週日是 6。這裡錯一格的話畫面上是隔壁那天的課，
      // 而使用者只會照著去上錯的課。
      final p = buildTimetableWidgetPayload(
        timetable: table([course('週日課', periods: [2], weekday: 6)]),
        now: at(9, 0),
      );

      expect(p.rows, isEmpty);
    });

    test('日期和星期用的是傳進來的那個時鐘', () {
      final p = buildTimetableWidgetPayload(
        timetable: null,
        now: at(9, 0),
      );

      expect(p.dateLabel, '9 月 3 日');
      expect(p.weekdayLabel, '星期四');
    });
  });

  group('哪一堂是現在、哪幾堂上完了', () {
    List<Course> threeCourses() => [
          course('第一堂', periods: [1, 2]), // 08:20–10:10
          course('第二堂', periods: [3, 4]), // 10:20–12:05
          course('第三堂', periods: [6, 7]), // 13:10–15:00
        ];

    test('上課前：第一堂反白，而且標「下一堂」', () {
      final p = buildTimetableWidgetPayload(
        timetable: table(threeCourses()),
        now: at(7, 30),
      );

      expect(p.highlightIndex, 0);
      expect(p.highlightStarted, isFalse);
      expect(p.rows.every((r) => !r.done), isTrue);
    });

    test('上課中：那一堂反白，而且標「現在」', () {
      final p = buildTimetableWidgetPayload(
        timetable: table(threeCourses()),
        now: at(10, 40), // 第 3 節之內
      );

      expect(p.highlightIndex, 1);
      expect(p.highlightStarted, isTrue);
      expect(p.rows[0].done, isTrue);
      expect(p.rows[1].done, isFalse);
    });

    test('下課空檔：下一堂反白，前面的標成上完了', () {
      final p = buildTimetableWidgetPayload(
        timetable: table(threeCourses()),
        now: at(12, 30), // 第 4 節結束、第 6 節還沒開始
      );

      expect(p.highlightIndex, 2);
      expect(p.highlightStarted, isFalse);
      expect(p.rows[0].done, isTrue);
      expect(p.rows[1].done, isTrue);
      expect(p.rows[2].done, isFalse);
    });

    test('今天上完了：沒有東西反白', () {
      final p = buildTimetableWidgetPayload(
        timetable: table(threeCourses()),
        now: at(20, 0),
      );

      expect(p.highlightIndex, -1);
      expect(p.rows.every((r) => r.done), isTrue);
    });
  });

  group('沒有節次時間表的時候不要猜', () {
    test('全部算成還沒上，時間欄留白', () {
      final p = buildTimetableWidgetPayload(
        timetable: table([
          course('第一堂', periods: [1, 2]),
          course('第二堂', periods: [3, 4]),
        ]),
        now: at(20, 0), // 照真實時間算的話兩堂都該上完了
        times: PeriodTimes.unknown,
      );

      // 分不出來的時候不要分：說「已結束」而使用者其實還沒上，
      // 比什麼都不說糟得多。
      expect(p.timesKnown, isFalse);
      expect(p.rows.every((r) => !r.done), isTrue);
      expect(p.rows.every((r) => r.time.isEmpty), isTrue);
      expect(p.highlightIndex, 0);
      expect(p.highlightStarted, isFalse);
    });

    test('一整天不會變，所以只排換日那一次', () {
      final p = buildTimetableWidgetPayload(
        timetable: table([course('課', periods: [1, 2])]),
        now: at(7, 0),
        times: PeriodTimes.unknown,
      );

      expect(p.updateTimes, [DateTime(2026, 9, 4)]);
    });
  });

  group('什麼時候要重畫', () {
    test('只排每堂課的開始和結束，加上換日', () {
      final p = buildTimetableWidgetPayload(
        timetable: table([course('課', periods: [1, 2])]), // 08:20–10:10
        now: at(7, 0),
      );

      expect(p.updateTimes, [
        DateTime(2026, 9, 3, 8, 20),
        DateTime(2026, 9, 3, 10, 10),
        DateTime(2026, 9, 4),
      ]);
    });

    test('已經過去的時刻不排', () {
      // 排下去的話鬧鐘會立刻響一次，畫出來的東西跟現在這張一模一樣。
      final p = buildTimetableWidgetPayload(
        timetable: table([course('課', periods: [1, 2])]),
        now: at(9, 0), // 已經開始了
      );

      expect(p.updateTimes, [
        DateTime(2026, 9, 3, 10, 10),
        DateTime(2026, 9, 4),
      ]);
    });

    test('由近到遠，而且不重複', () {
      // 兩堂課背靠背時，前一堂的結束和後一堂的開始可能是同一分鐘。
      final p = buildTimetableWidgetPayload(
        timetable: table([
          course('早', periods: [3]), // 10:20–11:10
          course('晚', periods: [4]), // 11:15–12:05
        ]),
        now: at(7, 0),
      );

      final sorted = [...p.updateTimes]..sort();
      expect(p.updateTimes, sorted);
      expect(p.updateTimes.toSet().length, p.updateTimes.length);
    });

    test('validUntil 就是最近的那一個', () {
      final p = buildTimetableWidgetPayload(
        timetable: table([course('課', periods: [1, 2])]),
        now: at(7, 0),
      );

      expect(p.validUntil, DateTime(2026, 9, 3, 8, 20));
    });
  });
}

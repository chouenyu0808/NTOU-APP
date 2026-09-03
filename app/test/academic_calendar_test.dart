import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/academic_calendar.dart';

/// 學校官網的行事曆頁（`https://www.ntou.edu.tw/calendar`）。
///
/// **這份 fixture 進版控**，跟 `spike/fixtures/` 那些不一樣 ——
/// 那些是從真實帳號抓的、含個資所以預設不上傳；這一頁是不用登入的公開頁面，
/// 裡面沒有任何跟人有關的東西。進版控的話任何人 clone 下來測試都跑得動。
final _page = File('test/data/ntou_calendar.html');

void main() {
  final missing = _page.existsSync() ? null : '沒有 ${_page.path}';
  late List<CalendarEvent> events;

  setUpAll(() {
    if (missing == null) events = parseAcademicCalendar(_page.readAsStringSync());
  });

  group('解析真實的行事曆頁', () {
    test('解得出整年的事件', () {
      expect(events, isNotEmpty);
      // 一個學年的行事曆大概百來筆。抓到個位數代表 selector 沒對上。
      expect(events.length, greaterThan(50));
    }, skip: missing);

    test('導覽列上的按鈕不能被當成事件', () {
      // 這一頁的 navbar 有兩顆 <button>，內容是「使用者選單」「主選單」。
      // 對 <button> 一網打盡的話它們會變成兩筆沒有日期的行事曆事件。
      expect(
        events.where((e) => e.title.contains('選單')),
        isEmpty,
      );
    }, skip: missing);

    test('單日事件：起訖同一天', () {
      final e = events.firstWhere((e) => e.title.contains('復學生註冊'));
      expect(e.start, DateTime(2026, 8, 19));
      expect(e.end, DateTime(2026, 8, 19));
      expect(e.isSingleDay, isTrue);
    }, skip: missing);

    test('多日事件：開始日要自己從天數推回去', () {
      // 頁面只給結束日（8/10）和天數（6），沒有直接給開始日。
      final e = events.firstWhere((e) => e.title.contains('研究所新生住宿'));
      expect(e.start, DateTime(2026, 8, 5));
      expect(e.end, DateTime(2026, 8, 10));
    }, skip: missing);

    test('標題不含螢幕閱讀器和日期範圍那幾個 span', () {
      final e = events.firstWhere((e) => e.title.contains('研究所新生住宿'));
      // 「(已完成事項)2026年8月」「(5~10) 」「 (8/5~8/10，共6天)」
      expect(e.title, '研究所新生住宿電腦抽籤申請');
    }, skip: missing);

    test(r'同一天多筆事件用 \; 分開，不是一筆長標題', () {
      // 8/1 是「學年度第1學期開始\;就學貸款申辦開始日」兩件事。
      final onFirst = events.where((e) => e.start == DateTime(2026, 8, 1));
      expect(onFirst.map((e) => e.title), containsAll(<String>[
        '學年度第1學期開始',
        '就學貸款申辦開始日',
      ]));
      expect(events.where((e) => e.title.contains(r'\;')), isEmpty);
    }, skip: missing);

    test('照開始日排序', () {
      for (var i = 1; i < events.length; i++) {
        expect(
          events[i].start.isBefore(events[i - 1].start),
          isFalse,
          reason: '${events[i]} 排在 ${events[i - 1]} 後面',
        );
      }
    }, skip: missing);
  });

  group('挑出接下來的幾筆', () {
    final sample = [
      CalendarEvent(
        title: '已經過去了',
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 1),
      ),
      CalendarEvent(
        title: '正在進行中',
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 9, 5),
      ),
      CalendarEvent(
        title: '還沒開始',
        start: DateTime(2026, 9, 10),
        end: DateTime(2026, 9, 10),
      ),
    ];

    test('進行中的算「接下來」—— 那正是最需要看到的', () {
      // 只留 start >= today 的話，選課週第一天過後那條就消失了，
      // 而它還有一個禮拜才截止。
      final r = upcoming(sample, DateTime(2026, 8, 25));
      expect(r.map((e) => e.title), ['正在進行中', '還沒開始']);
    });

    test('結束了的不再顯示', () {
      final r = upcoming(sample, DateTime(2026, 9, 20));
      expect(r, isEmpty);
    });

    test('最多只給指定的筆數', () {
      final r = upcoming(sample, DateTime(2026, 7, 1), limit: 2);
      expect(r, hasLength(2));
    });
  });

  group('存進本機再讀回來', () {
    test('日期不會在來回一趟之後跑掉', () {
      final e = CalendarEvent(
        title: '選課',
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 9, 5),
      );
      final back = CalendarEvent.fromJson(e.toJson());
      expect(back.title, e.title);
      expect(back.start, e.start);
      expect(back.end, e.end);
    });
  });

  _classStartTests();
}

void _classStartTests() {
  group('nearestClassStart', () {
    CalendarEvent ev(String title, int y, int m, int d) =>
        CalendarEvent(title: title, start: DateTime(y, m, d), end: DateTime(y, m, d));

    // 真實資料（2026-09-03 抓的行事曆）：整學年就這兩筆帶「開始上課」。
    final events = [
      ev('115學年度第1學期新生電腦選課', 2026, 9, 3),
      ev('開始上課、舊生註冊、舊生就學貸款申辦截止、學雜費減免申辦截止日', 2026, 9, 7),
      ev('本校73週年校慶（全校正常上班上課）', 2026, 10, 17),
      ev('115學年度第2學期開始上課、舊生註冊、學貸款申辦截止，學雜費減免申辦截止', 2027, 2, 22),
    ];

    test('開學前抓到的是這學期的 9/7，不是下學期的 2/22', () {
      expect(nearestClassStart(events, DateTime(2026, 9, 3)), DateTime(2026, 9, 7));
    });

    test('開學後仍然是 9/7 —— 不能跳到下學期', () {
      // 用「下一筆」的話這裡會回 2027/02/22，首頁就會說「還有 168 天開始上課」。
      expect(nearestClassStart(events, DateTime(2026, 9, 8)), DateTime(2026, 9, 7));
      expect(nearestClassStart(events, DateTime(2026, 11, 1)), DateTime(2026, 9, 7));
    });

    test('寒假期間抓到的是下學期', () {
      expect(nearestClassStart(events, DateTime(2027, 1, 20)), DateTime(2027, 2, 22));
    });

    test('「正常上班上課」不算 —— 那是校慶，不是開學', () {
      expect(nearestClassStart([ev('本校73週年校慶（全校正常上班上課）', 2026, 10, 17)],
          DateTime(2026, 10, 1)), isNull);
    });

    test('沒有行事曆就回 null，不要編一個日期', () {
      expect(nearestClassStart(const [], DateTime(2026, 9, 3)), isNull);
    });
  });
}

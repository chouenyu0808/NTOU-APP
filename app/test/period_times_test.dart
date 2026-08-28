import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/config/period_times.dart';

/// 對照教務處的節次時間對照表：
/// <https://academic.ntou.edu.tw/p/412-1005-1133.php>
///
/// 這份資料是寫死的，所以測試的作用不是「驗程式」，是**把數字釘住**：
/// 節次之間的間隔不規則（多半 10 分鐘，但 3→4 和 8→9 是 5 分鐘、
/// 9→10 是 35 分鐘），看起來像打錯的地方其實是對的。有人「順手修正」
/// 的話這裡會紅。
void main() {
  group('海大的節次時間', () {
    const t = PeriodTimes.ntou;

    test('第 0 節到第 14 節都在', () {
      expect(t.isKnown, isTrue);
      for (var p = 0; p <= 14; p++) {
        expect(t[p], isNotNull, reason: '第 $p 節沒有時間');
      }
    });

    test('每一節的起訖跟官方表一致', () {
      String range(int p) =>
          '${PeriodTimes.hhmm(t[p]!.start)}~${PeriodTimes.hhmm(t[p]!.end)}';

      expect(range(0), '06:20~08:10');
      expect(range(1), '08:20~09:10');
      expect(range(2), '09:20~10:10');
      expect(range(3), '10:20~11:10');
      expect(range(4), '11:15~12:05');
      expect(range(5), '12:10~13:00');
      expect(range(6), '13:10~14:00');
      expect(range(7), '14:10~15:00');
      expect(range(8), '15:10~16:00');
      expect(range(9), '16:05~16:55');
      expect(range(10), '17:30~18:20');
      expect(range(11), '18:30~19:20');
      expect(range(12), '19:25~20:15');
      expect(range(13), '20:20~21:10');
      expect(range(14), '21:15~22:05');
    });

    test('節次之間的間隔不規則，而那是對的', () {
      // 下課時間有三種：10 分、5 分、還有第 9→10 節那個 35 分的晚餐時間。
      // 沒有規律可循 —— 所以整張列出來，不要用「其餘都是 10 分」帶過。
      // （寫這條測試的時候我就先假設錯了一次：以為只有 3→4 和 8→9 是 5 分。）
      const expected = {
        0: 10, // 08:10 → 08:20
        1: 10,
        2: 10,
        3: 5, //  11:10 → 11:15
        4: 5, //  12:05 → 12:10
        5: 10,
        6: 10,
        7: 10,
        8: 5, //  16:00 → 16:05
        9: 35, // 16:55 → 17:30，晚餐
        10: 10,
        11: 5, // 19:20 → 19:25
        12: 5,
        13: 5,
      };
      expected.forEach((a, minutes) {
        expect(
          t[a + 1]!.start - t[a]!.end,
          minutes,
          reason: '第 $a→${a + 1} 節',
        );
      });
    });

    test('第 1 到 14 節都是 50 分鐘，第 0 節是加長的', () {
      for (var p = 1; p <= 14; p++) {
        expect(t[p]!.end - t[p]!.start, 50, reason: '第 $p 節');
      }
      // 第 0 節 06:20–08:10 是 110 分鐘 —— 那不是打錯。
      expect(t[0]!.end - t[0]!.start, 110);
    });
  });

  group('拿時間來問問題', () {
    const t = PeriodTimes.ntou;
    int at(int h, int m) => h * 60 + m;

    test('現在落在哪一節', () {
      expect(t.periodAt(at(9, 40)), 2);
      expect(t.periodAt(at(8, 20)), 1, reason: '開始的那一分鐘算在裡面');
      // 09:10 是第 1 節的結束時間 —— 結束那一刻已經不在課裡了，
      // 而下一節還沒開始，所以是下課時間。
      expect(t.periodAt(at(9, 10)), isNull);
      expect(t.periodAt(at(23, 0)), isNull);
    });

    test('這一節上完了沒', () {
      expect(t.hasEnded(1, at(9, 10)), isTrue);
      expect(t.hasEnded(1, at(9, 9)), isFalse);
    });

    test('還有幾分鐘', () {
      expect(t.minutesUntil(2, at(9, 0)), 20);
      // 已經開始的不倒數 —— 「還有 -5 分鐘」不是話。
      expect(t.minutesUntil(2, at(9, 30)), isNull);
    });

    test('沒有資料的時候什麼都不回答', () {
      const u = PeriodTimes.unknown;
      expect(u.isKnown, isFalse);
      expect(u[2], isNull);
      expect(u.periodAt(at(9, 40)), isNull);
      expect(u.hasEnded(1, at(23, 0)), isFalse);
      expect(u.minutesUntil(2, at(9, 0)), isNull);
    });
  });

  test('minutesOf 和 hhmm 對得起來', () {
    expect(PeriodTimes.minutesOf(DateTime(2026, 8, 28, 9, 5)), at9_05);
    expect(PeriodTimes.hhmm(at9_05), '09:05');
    expect(PeriodTimes.hhmm(0), '00:00');
  });
}

const at9_05 = 9 * 60 + 5;

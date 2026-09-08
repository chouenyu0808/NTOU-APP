/// 「現在這一刻，課上到哪了」。給課表頁頂端那條狀態列用。
///
/// **這一整個檔案是純函式，而且測得很兇** —— 它算的是「還有 N 分鐘下課」
/// 這種東西，而那正是 CLAUDE.md 反覆講的「算錯不會報錯」：畫面上「還有
/// 8 分鐘」長得跟真的一模一樣，使用者只會照著遲到。
library;

import '../config/period_times.dart';
import '../parsing/models.dart';

/// 課表頁頂端狀態列的四種狀態。
sealed class ClassStatus {
  const ClassStatus();
}

/// 正在上課。[minutesLeft] 是到**這一段連堂結束**還有幾分鐘 ——
/// 不是到這一節結束。連堂課（2–4 節）中間那 5 分鐘的下課仍然在課內。
class InClass extends ClassStatus {
  const InClass({required this.course, required this.minutesLeft});
  final Course course;
  final int minutesLeft;
}

/// 今天還有課，但現在是下課／還沒開始。[minutesUntil] 是到下一堂開始還有
/// 幾分鐘，[startMinute] 是它幾點開始（當天的分鐘數）。
class NextClass extends ClassStatus {
  const NextClass({
    required this.course,
    required this.minutesUntil,
    required this.startMinute,
  });
  final Course course;
  final int minutesUntil;
  final int startMinute;
}

/// 今天有課，但都上完了。
class DoneForToday extends ClassStatus {
  const DoneForToday();
}

/// 今天沒有排課（假日，或這一天本來就沒課）。
class NoClassToday extends ClassStatus {
  const NoClassToday();
}

/// 今天某一段連堂課在時間軸上佔的區間。
typedef _Span = ({Course course, int start, int end});

/// 算出現在的狀態。拿不到節次時間（[PeriodTimes.unknown]）就回 null ——
/// 那時候什麼都不顯示，不猜。
///
/// [weekday] 0 = 週一。[nowMinutes] 是當天從 00:00 起算的分鐘數。
ClassStatus? classStatus({
  required List<Course> courses,
  required PeriodTimes times,
  required int weekday,
  required int nowMinutes,
}) {
  if (!times.isKnown) return null;

  // **用時間區間，不用「現在第幾節」。**
  //
  // periodAt 在連堂課中間那 5 分鐘的下課會回 null（它嚴格落在兩節之間），
  // 但學生其實還在同一堂課裡。改成把今天每一段連堂課換算成一個時間區間
  // `[開始, 結束)`，「在不在課內」就是「now 落不落在某個區間裡」——
  // 那 5 分鐘自然被含在區間內。
  final spans = _todaySpans(courses, times, weekday);
  if (spans.isEmpty) return const NoClassToday();

  for (final s in spans) {
    if (nowMinutes >= s.start && nowMinutes < s.end) {
      return InClass(course: s.course, minutesLeft: s.end - nowMinutes);
    }
  }

  for (final s in spans) {
    if (s.start > nowMinutes) {
      return NextClass(
        course: s.course,
        minutesUntil: s.start - nowMinutes,
        startMinute: s.start,
      );
    }
  }

  return const DoneForToday();
}

/// 今天的每一段連堂課，換算成時間區間，照開始時間排好。
List<_Span> _todaySpans(
  List<Course> courses,
  PeriodTimes times,
  int weekday,
) {
  final spans = <_Span>[];
  for (final c in courses) {
    final periods = [
      for (final s in c.slots)
        if (s.weekday == weekday) s.period,
    ]..sort();
    if (periods.isEmpty) continue;

    void flush(int startPeriod, int endPeriod) {
      final a = times[startPeriod];
      final b = times[endPeriod];
      // 認不得的節次代碼放不進時間軸 —— 寧可漏掉那一段，不要擺到錯的時間。
      // parser 只產出 0–14，而那些都在表裡，所以正常不會走到這裡。
      if (a != null && b != null) {
        spans.add((course: c, start: a.start, end: b.end));
      }
    }

    var start = periods.first;
    var prev = periods.first;
    for (final p in periods.skip(1)) {
      if (p == prev + 1) {
        prev = p;
        continue;
      }
      flush(start, prev);
      start = p;
      prev = p;
    }
    flush(start, prev);
  }

  spans.sort((a, b) => a.start.compareTo(b.start));
  return spans;
}

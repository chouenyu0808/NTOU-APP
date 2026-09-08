import '../config/period_times.dart';
import '../parsing/models.dart';
import '../parsing/timetable.dart' show kWeekdays;
import '../ui/home_page.dart';

/// 桌面小組件上的一列課。
///
/// 全部是**已經算好的字串**。小組件那一端（背景 isolate 畫圖、之後可能換成
/// 原生排版）只負責把它們貼上去 —— 任何「第幾節換算成幾點」「這堂上完了沒」
/// 的判斷都在這裡做完，因為那些判斷錯了畫面上完全看不出來
/// （見 [PeriodTimes] 的說明）。
class TimetableWidgetRow {
  const TimetableWidgetRow({
    required this.period,
    required this.time,
    required this.name,
    required this.room,
    required this.done,
  });

  /// 「第 2-4 節」。
  final String period;

  /// 「09:20–12:05」。節次時間表不可用時是空字串 —— 那時候不寫時間，
  /// 不是寫一個猜的。
  final String time;

  final String name;
  final String room;

  /// 今天這堂已經上完了。畫面上會變淡。
  final bool done;
}

/// 課表小組件要顯示的一整份東西。
///
/// **不含網路，不含登入。** 資料全部來自 [TimetableCache] 已經抓下來的那份，
/// 所以學校系統掛掉、session 被電腦端佔住的時候小組件照樣是對的 ——
/// 那正是課表快取原本要救的情境。
class TimetableWidgetPayload {
  const TimetableWidgetPayload({
    required this.dateLabel,
    required this.weekdayLabel,
    required this.rows,
    required this.highlightIndex,
    required this.highlightStarted,
    required this.timesKnown,
    required this.updateTimes,
    this.emptyMessage,
    this.showingTomorrow = false,
  });

  /// 「9 月 4 日」。
  final String dateLabel;

  /// 「星期四」。
  final String weekdayLabel;

  final List<TimetableWidgetRow> rows;

  /// 哪一列要反白。-1 = 沒有（今天的課都上完了，或今天沒課）。
  final int highlightIndex;

  /// 反白那堂是**已經開始**（「現在」）還是還沒（「下一堂」）。
  ///
  /// 節次時間表不可用時一律是 false，而且標的字會是「今天第一堂」——
  /// 分不出來的時候不要分，跟 [HomePage] 那張卡片同一套規則。
  final bool highlightStarted;

  /// 節次時間表可不可用。false 的時候整份 payload 的 [TimetableWidgetRow.done]
  /// 全是 false、[highlightStarted] 是 false。
  final bool timesKnown;

  /// 畫面上這一份是**明天**的課，不是今天的。
  ///
  /// 今天的課全部上完之後就切過去 —— 那時候「今天還剩什麼」的答案是
  /// 「沒有了」，而使用者接著要問的是明天早上幾點要出門。
  ///
  /// **切過去的時候標題的日期和星期也一起換成明天的**，右上角還會標「明天」。
  /// 只換內容不換日期的話，畫面上會是一份「今天」的課表列著明天的課 ——
  /// 那是最糟的一種錯，因為它看起來完全正常。
  final bool showingTomorrow;

  /// 沒有課可以顯示時要說的那句話。null = 有課。
  ///
  /// **「還沒有課表」和「今天沒有課」是兩件事**，使用者的下一步完全不同
  /// （一個是去開 App 登入，一個是可以睡晚一點）。
  final String? emptyMessage;

  /// 今天剩下要重畫的所有時刻，由近到遠。最後一個一定是換日。
  ///
  /// 小組件是一張圖，反白不會自己移動 —— 要靠鬧鐘在這些時間點叫醒我們重畫。
  ///
  /// **一定要一次給完整的一串，不能只給下一個。**
  /// `HomeWidget.scheduleWidgetUpdates` 是「整批取代」的語意，
  /// 只給一個的話會把其他時刻全部洗掉 —— 症狀是小組件更新一次之後
  /// 就再也不動了，而且完全不會報錯。
  ///
  /// 這裡回**絕對時刻**而不是「第幾節」，原生那端就完全不需要知道節次表
  /// 長什麼樣子。
  final List<DateTime> updateTimes;

  /// 下一次要重畫的時刻。原生存這個來判斷手上那張圖過期了沒有。
  DateTime get validUntil => updateTimes.first;

  bool get isEmpty => rows.isEmpty;
}

/// [TimetableResult] → 小組件要顯示的東西。
///
/// [now] 一定要傳進來，不要在裡面讀 `DateTime.now()` —— 這整段的行為跟時間
/// 有關（哪幾堂上完了、下一次什麼時候重畫），讀時鐘的話測試就變成早上綠、
/// 晚上紅，而失敗訊息完全看不出跟時間有關。
///
/// [times] 同理，預設是 [PeriodTimes.ntou]，測試可以塞 [PeriodTimes.unknown]
/// 驗「不知道時間就不要分」那條路。
TimetableWidgetPayload buildTimetableWidgetPayload({
  required TimetableResult? timetable,
  required DateTime now,
  PeriodTimes times = PeriodTimes.ntou,
}) {
  final weekday = HomePage.todayIndex(now);
  final dateLabel = '${now.month} 月 ${now.day} 日';
  final weekdayLabel = '星期${kWeekdays[weekday.clamp(0, 6)]}';
  final midnight = DateTime(now.year, now.month, now.day + 1);

  if (timetable == null) {
    return TimetableWidgetPayload(
      dateLabel: dateLabel,
      weekdayLabel: weekdayLabel,
      rows: const [],
      highlightIndex: -1,
      highlightStarted: false,
      timesKnown: times.isKnown,
      // **不要說「今天沒有課」** —— 我們根本還沒拿到課表，那句話會讓
      // 使用者以為今天可以睡晚一點。
      emptyMessage: '還沒有課表\n打開 App 登入後就會出現',
      updateTimes: [midnight],
    );
  }

  final today = HomePage.coursesOn(timetable, weekday);
  if (today.isEmpty) {
    return TimetableWidgetPayload(
      dateLabel: dateLabel,
      weekdayLabel: weekdayLabel,
      rows: const [],
      highlightIndex: -1,
      highlightStarted: false,
      timesKnown: times.isKnown,
      emptyMessage: '今天沒有課',
      updateTimes: [midnight],
    );
  }

  final nowMin = PeriodTimes.minutesOf(now);
  // 分堆用 HomePage 那一套，不要在這裡重寫一次 —— 它已經被測試釘著，
  // 而且「節次時間表不可用時全部算成還沒上」那條規則只寫在那裡。
  final split = HomePage.split(today, weekday, times, nowMin);

  // 今天的課全部上完了 —— 換成明天的。
  //
  // 「今天結束」是實話但沒有用：使用者接著要問的是明天早上幾點要出門，
  // 而那個答案要開 App 翻課表才找得到。
  //
  // **節次時間表不可用的時候永遠不會走到這裡**：那時候 [HomePage.split]
  // 會把每一堂都算成「還沒上」，`next` 不可能是 null。分不出哪幾堂上完了
  // 就跳到明天，等於在一個還沒下課的下午把今天的課藏起來。
  if (split.next == null) {
    return _tomorrow(timetable, now, times, midnight);
  }

  final rows = <TimetableWidgetRow>[];
  var highlightIndex = -1;
  for (final c in today) {
    if (identical(c, split.next)) highlightIndex = rows.length;
    rows.add(
      TimetableWidgetRow(
        period: HomePage.periodLabel(c, weekday),
        time: _timeLabel(c, weekday, times),
        name: c.name,
        room: c.room,
        done: split.done.contains(c),
      ),
    );
  }

  // 反白那堂是不是已經開始了。跟 HomePage 那張卡片同一個判斷 ——
  // 兩邊講的話要一致，使用者在 App 裡看到「現在」、桌面上看到「下一堂」
  // 是會讓人以為其中一邊壞了的。
  final firstOfNext = split.next == null
      ? null
      : times[_firstPeriodOf(split.next!, weekday)];
  final started =
      times.isKnown && firstOfNext != null && nowMin >= firstOfNext.start;

  return TimetableWidgetPayload(
    dateLabel: dateLabel,
    weekdayLabel: weekdayLabel,
    rows: rows,
    highlightIndex: highlightIndex,
    highlightStarted: started,
    timesKnown: times.isKnown,
    emptyMessage: null,
    updateTimes: _updateTimes(today, weekday, times, now, midnight),
  );
}

/// 明天的課表。
///
/// [midnight] 是今天結束的那一刻 —— **也是唯一要重畫的時刻**：過了午夜
/// 「明天」就變成「今天」了，那時候要整份重算。中間不會有任何變化，
/// 所以不排其他鬧鐘。
TimetableWidgetPayload _tomorrow(
  TimetableResult timetable,
  DateTime now,
  PeriodTimes times,
  DateTime midnight,
) {
  // 用 midnight 當「明天」：它就是 DateTime(年, 月, 日 + 1)，
  // 跨月跨年由 DateTime 自己處理。
  final weekday = HomePage.todayIndex(midnight);
  final courses = HomePage.coursesOn(timetable, weekday);

  return TimetableWidgetPayload(
    dateLabel: '${midnight.month} 月 ${midnight.day} 日',
    weekdayLabel: '星期${kWeekdays[weekday.clamp(0, 6)]}',
    rows: [
      for (final c in courses)
        TimetableWidgetRow(
          period: HomePage.periodLabel(c, weekday),
          time: _timeLabel(c, weekday, times),
          name: c.name,
          room: c.room,
          // 明天的課**一堂都還沒上**。照今天的時間去判斷「上完了沒」
          // 會把明天早上的課標成已結束。
          done: false,
        ),
    ],
    // 明天的第一堂就是使用者接下來要上的那一堂。
    highlightIndex: courses.isEmpty ? -1 : 0,
    // 明天的課現在一定還沒開始，所以不會是「現在」。
    highlightStarted: false,
    timesKnown: times.isKnown,
    emptyMessage: courses.isEmpty ? '明天沒有課' : null,
    showingTomorrow: true,
    updateTimes: [midnight],
  );
}

/// 「09:20–12:05」。節次時間表不可用、或這門課今天的節次查不到時間，就回空字串。
String _timeLabel(Course c, int weekday, PeriodTimes times) {
  if (!times.isKnown) return '';
  final ps = c.slots.where((s) => s.weekday == weekday).map((s) => s.period);
  if (ps.isEmpty) return '';
  final start = times[ps.reduce((a, b) => a < b ? a : b)];
  final end = times[ps.reduce((a, b) => a > b ? a : b)];
  if (start == null || end == null) return '';
  return '${PeriodTimes.hhmm(start.start)}–${PeriodTimes.hhmm(end.end)}';
}

int _firstPeriodOf(Course c, int weekday) => c.slots
    .where((s) => s.weekday == weekday)
    .map((s) => s.period)
    .reduce((a, b) => a < b ? a : b);

/// 今天剩下要重畫的時刻，由近到遠，結尾一定是換日。
///
/// 會讓畫面變的只有兩種時刻：某堂課開始（「下一堂」變成「現在」）和某堂課
/// 結束（那一列變淡、反白往下移）。所以只排這些點，**不是每分鐘叫醒一次**
/// —— 一天三堂課大概六次，加上換日那一次。
///
/// [times] 不可用時所有列都是「還沒上」，一整天不會變 —— 只排換日那一次。
List<DateTime> _updateTimes(
  List<Course> today,
  int weekday,
  PeriodTimes times,
  DateTime now,
  DateTime midnight,
) {
  if (!times.isKnown) return [midnight];

  final nowMin = PeriodTimes.minutesOf(now);
  final minutes = <int>{};
  for (final c in today) {
    final ps =
        c.slots.where((s) => s.weekday == weekday).map((s) => s.period).toList();
    if (ps.isEmpty) continue;
    final start = times[ps.reduce((a, b) => a < b ? a : b)]?.start;
    final end = times[ps.reduce((a, b) => a > b ? a : b)]?.end;
    for (final m in [start, end]) {
      // 已經過去的時刻不排。排下去的話鬧鐘會立刻響一次，
      // 而畫出來的東西跟現在這張一模一樣。
      if (m != null && m > nowMin) minutes.add(m);
    }
  }

  final sorted = minutes.toList()..sort();
  return [
    for (final m in sorted)
      DateTime(now.year, now.month, now.day, m ~/ 60, m % 60),
    midnight,
  ];
}

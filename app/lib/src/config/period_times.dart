/// 節次 ↔ 時鐘時間。
///
/// AIS 的學生選單裡沒有這份資料 —— 課表、課程查詢、必修科目表給的都是節次
/// 代碼（`102 103 104`），時鐘時間是教務處另外公告的東西。
///
/// 所以 [ntou] 是**寫死的**，來源是教務處的「節次時間對照表」：
/// <https://academic.ntou.edu.tw/p/412-1005-1133.php>
///
/// 寫死是有意識的取捨。替代方案是去爬那一頁，但那要為一份**幾乎不會變**的
/// 資料多養一個爬蟲和一份快取，而它一改我們還是得改程式（頁面結構會變）。
/// 寫死的版本至少是「錯了看得出來、改一行就好」。
///
/// **不要憑印象調整這裡的任何一個數字。** 節次之間的間隔是不規則的
/// （多半 10 分鐘，但第 3→4 節是 5 分鐘、第 8→9 節是 5 分鐘、第 9→10 節
/// 是 35 分鐘），看起來像打錯的地方其實是對的。時間錯了畫面上完全看不出來
/// ——「還有 8 分鐘」長得跟真的一模一樣，使用者只會照著遲到。
/// 要改的話對著上面那一頁重新抄一次。
///
/// 沒有資料時（[unknown]）用到它的地方會自己收起來，不會顯示錯的時間 ——
/// 那些地方都問過 [isKnown]。
class PeriodTimes {
  const PeriodTimes(this.table);

  /// 節次 → 一天當中的起訖分鐘數（00:00 起算）。
  ///
  /// 用分鐘而不是 `TimeOfDay`：要拿來跟「現在」比大小、算差幾分鐘，
  /// 整數最直接。
  final Map<int, ({int start, int end})> table;

  /// 還沒有資料。
  static const PeriodTimes unknown = PeriodTimes({});

  /// 海大的節次時間。抄自教務處的節次時間對照表（見上面的連結）。
  ///
  /// 第 0 節（06:20–08:10）和第 12–14 節（晚上）都收進來了 —— 實際上很少
  /// 有課排在那裡，但 parser 收得下那些代碼，畫面上就得認得。
  static const PeriodTimes ntou = PeriodTimes({
    0: (start: 6 * 60 + 20, end: 8 * 60 + 10),
    1: (start: 8 * 60 + 20, end: 9 * 60 + 10),
    2: (start: 9 * 60 + 20, end: 10 * 60 + 10),
    3: (start: 10 * 60 + 20, end: 11 * 60 + 10),
    4: (start: 11 * 60 + 15, end: 12 * 60 + 5),
    5: (start: 12 * 60 + 10, end: 13 * 60),
    6: (start: 13 * 60 + 10, end: 14 * 60),
    7: (start: 14 * 60 + 10, end: 15 * 60),
    8: (start: 15 * 60 + 10, end: 16 * 60),
    9: (start: 16 * 60 + 5, end: 16 * 60 + 55),
    10: (start: 17 * 60 + 30, end: 18 * 60 + 20),
    11: (start: 18 * 60 + 30, end: 19 * 60 + 20),
    12: (start: 19 * 60 + 25, end: 20 * 60 + 15),
    13: (start: 20 * 60 + 20, end: 21 * 60 + 10),
    14: (start: 21 * 60 + 15, end: 22 * 60 + 5),
  });

  bool get isKnown => table.isNotEmpty;

  ({int start, int end})? operator [](int period) => table[period];

  /// [now]（當天的分鐘數）落在哪一節。不在任何一節之內就回 null（下課時間）。
  int? periodAt(int now) {
    for (final e in table.entries) {
      if (now >= e.value.start && now < e.value.end) return e.key;
    }
    return null;
  }

  /// 這一節已經上完了嗎。
  bool hasEnded(int period, int now) {
    final t = table[period];
    return t != null && now >= t.end;
  }

  /// 從現在到 [period] 開始還有幾分鐘。已經開始或不知道就回 null。
  int? minutesUntil(int period, int now) {
    final t = table[period];
    if (t == null || now >= t.start) return null;
    return t.start - now;
  }

  /// 「10:10」。
  static String hhmm(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 給一天當中的分鐘數。抽出來是為了測試好塞一個固定的「現在」。
  static int minutesOf(DateTime t) => t.hour * 60 + t.minute;
}

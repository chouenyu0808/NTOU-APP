/// 節次 ↔ 時鐘時間。
///
/// **這份資料我們目前沒有。**
///
/// 學校的學生選單裡沒有任何一頁列出「第 2 節是幾點到幾點」——
/// 課表、課程查詢、必修科目表給的都是節次代碼（`102 103 104`），
/// 時鐘時間是校方公告的另一份東西。
///
/// 所以這裡預設是空的，而**不是猜一組看起來合理的時間**。猜錯的話畫面上
/// 完全看不出來（「下一堂 10:10 開始，還有 8 分鐘」長得跟真的一模一樣），
/// 使用者只會照著遲到。寧可不顯示時間，也不要顯示一個錯的。
///
/// 拿得到之後填 [ntou] 就好，用到它的地方（首頁的「下一堂」、「還有幾分鐘」）
/// 會自己亮起來 —— 那些地方都問過 [isKnown] 了。
class PeriodTimes {
  const PeriodTimes(this.table);

  /// 節次 → 一天當中的起訖分鐘數（00:00 起算）。
  ///
  /// 用分鐘而不是 `TimeOfDay`：要拿來跟「現在」比大小、算差幾分鐘，
  /// 整數最直接。
  final Map<int, ({int start, int end})> table;

  /// 還沒有資料。
  static const PeriodTimes unknown = PeriodTimes({});

  /// 海大的節次時間。**目前是空的** —— 見上面的說明。
  static const PeriodTimes ntou = unknown;

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

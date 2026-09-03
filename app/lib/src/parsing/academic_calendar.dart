import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 校園行事曆的一筆事件。
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;

  /// 起訖都是「那一天」，不含時間 —— 行事曆給的就是日期，沒有時鐘時間。
  final DateTime start;
  final DateTime end;

  bool get isSingleDay => start == end;

  /// 這個事件在 [day] 當天有沒有效（含頭含尾）。
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  static CalendarEvent fromJson(Map<String, dynamic> j) => CalendarEvent(
        title: j['title'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
      );

  @override
  String toString() => '$title（${start.month}/${start.day}'
      '${isSingleDay ? '' : '–${end.month}/${end.day}'}）';
}

/// 解析 `https://www.ntou.edu.tw/calendar`。
///
/// **這一頁不在 AIS 上，是學校官網的公開頁面** —— 不用登入、也不該帶著 AIS
/// 的 session cookie 去要（見 `AcademicCalendarSource`）。
///
/// 每一筆事件長這樣：
/// ```html
/// <button class="Expired" data-end_date="2026/08/10" data-days_count="6">
///   <span class="sr-only">(已完成事項)2026年8月</span>
///   <span class='event_title_append_before'>(5~10) </span>
///   研究所新生住宿電腦抽籤申請
///   <span class='event_title_append_after'> (8/5~8/10，共6天)</span>
/// </button>
/// ```
///
/// 幾個踩得到的坑：
///
/// 1. **不能對 `<button>` 一網打盡。** 這一頁的導覽列上還有兩顆
///    `navbar-toggler`，內容是「使用者選單」「主選單」。靠 `data-end_date`
///    在不在來認，不是靠標籤名。
///
/// 2. **開始日期要自己算。** 頁面只給結束日和天數，
///    起日 = 結束日 −（天數 − 1）。
///
/// 3. **三個 `<span>` 全部要丟掉。** `sr-only` 是螢幕閱讀器用的
///    「(已完成事項)2026年8月」，另外兩個是把日期範圍再寫一次
///    （「(5~10) 」和「 (8/5~8/10，共6天)」）—— 那些資訊 `start`/`end`
///    已經有了，留著只會讓標題變成一長串重複的東西。
///
/// 4. **同一天多筆事件用 `\;` 分隔**（真的是反斜線加分號，學校自己的分隔符）。
///    不拆的話會得到「學年度第1學期開始\;就學貸款申辦開始日」這種標題。
List<CalendarEvent> parseAcademicCalendar(String html) {
  final doc = html_parser.parse(html);
  final out = <CalendarEvent>[];

  for (final btn in doc.querySelectorAll('button[data-end_date]')) {
    final end = _parseDate(btn.attributes['data-end_date']);
    if (end == null) continue;

    final days = int.tryParse(btn.attributes['data-days_count'] ?? '') ?? 1;
    final start = end.subtract(Duration(days: days > 0 ? days - 1 : 0));

    for (final title in _titles(btn)) {
      out.add(CalendarEvent(title: title, start: start, end: end));
    }
  }

  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// 按鈕裡的標題，把裝飾用的 span 拿掉之後再依 `\;` 拆開。
Iterable<String> _titles(dom.Element btn) {
  final buf = StringBuffer();
  for (final node in btn.nodes) {
    if (node is dom.Element) {
      final cls = node.className;
      if (cls.contains('sr-only') ||
          cls.contains('event_title_append_before') ||
          cls.contains('event_title_append_after')) {
        continue;
      }
      buf.write(node.text);
    } else if (node.nodeType == dom.Node.TEXT_NODE) {
      buf.write(node.text ?? '');
    }
  }

  return buf
      .toString()
      .split(r'\;')
      .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((s) => s.isNotEmpty);
}

/// `2026/08/10`。
DateTime? _parseDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(raw.trim());
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

/// 從 [now] 起算，接下來的幾筆。
///
/// 「接下來」包含**正在進行中**的（選課週已經開始了還沒結束）——
/// 那些正是使用者最需要看到的。只看 `start >= now` 的話，
/// 選課期間第一天過後那條就消失了。
List<CalendarEvent> upcoming(
  List<CalendarEvent> all,
  DateTime now, {
  int limit = 4,
}) {
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (final e in all)
      if (!e.end.isBefore(today)) e,
  ].take(limit).toList();
}

/// 行事曆裡代表「這學期開始上課」的字樣。
///
/// 學校寫的是「開始上課」，不是「開學」——
/// 真實資料：`2026/09/07 開始上課、舊生註冊、舊生就學貸款申辦截止…`
/// 以及 `2027/02/22 115學年度第2學期開始上課、舊生註冊…`。
///
/// 放在這裡而不是 `selectors.json`：那一份收的是 **AIS** 會因改版而爛掉的字串，
/// 而行事曆是學校官網的公開頁面，這個檔案裡本來就寫著它的版面假設。
const List<String> kClassStartMarkers = ['開始上課'];

/// 離 [now] 最近的一次「開始上課」。認不出來就回 null。
///
/// **一份行事曆涵蓋整學年，所以會有兩筆**（上下學期各一）。取離 [now] 最近的
/// 那一筆，而不是「下一筆」——用「下一筆」的話，開學隔天就會抓到下學期的
/// 日期，然後首頁會說「還有 168 天開始上課」。
///
/// 回傳的日期**晚於今天**就代表這學期還沒開始上課。
DateTime? nearestClassStart(
  List<CalendarEvent> events,
  DateTime now, {
  List<String> markers = kClassStartMarkers,
}) {
  final today = DateTime(now.year, now.month, now.day);

  DateTime? best;
  var bestGap = -1;
  for (final e in events) {
    if (!markers.any(e.title.contains)) continue;
    final gap = e.start.difference(today).inDays.abs();
    if (best == null || gap < bestGap) {
      best = e.start;
      bestGap = gap;
    }
  }
  return best;
}

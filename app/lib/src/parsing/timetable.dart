import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_text.dart';
import 'models.dart';
import 'tables.dart';

const List<String> kWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

// 課表解析的門檻值。全部是啟發式的猜測，不是規格 ——
// 猜錯只該少顯示欄位，不該讓整張表掛掉。
const int _teacherNameMin = 2; // 「王小明」
const int _teacherNameMax = 8; // 到「Christopher」
const int _weekdayHeaderMax = 4; // 「週一」「星期一」可以，「第一節課程」不行
const int _minWeekdayColumns = 4; // 認得出四天以上才當成課表
const int _minTimetableRows = 2; // 至少要有表頭 + 一列

/// 常見教室代碼：綜一01、電資305、海工B12 之類
final RegExp _roomRe = RegExp(r'^[A-Za-z一-鿿]{1,6}[A-Za-z]?-?\d{2,4}[A-Za-z]?$');

// ---------- 選課清單（v1 主要路徑） ----------

/// 「選課清單」（`QUERY_BTN1`）回來的 `<table id="DataGrid">`。
///
/// 為什麼用清單而不是「選課課表」（`QUERY_BTN3`）：後者掛在 Crystal Reports 上，
/// 輸出可能根本不是 HTML 表格 —— 沒驗證過的東西不放進 v1。
///
/// 欄位用**表頭文字**對應，不用欄位位置。學校在中間插一欄不會害整排錯位。
List<Course> parseCourseList(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('table#DataGrid');
  final rows = table != null
      ? _rowsOf(table)
      : (pickTable(html, ['課號']) ?? pickTable(html, ['課程']) ?? const []);
  if (rows.length < 2) return const [];

  final out = <Course>[];
  for (final rec in tableToRecords(rows)) {
    final name = firstOf(rec, ['課名', '課程名稱', '科目名稱', '科目']);
    if (name.isEmpty) continue;

    final timeText = firstOf(rec, ['上課時間', '時間', '上課時段', '星期節次', '節次']);
    out.add(Course(
      name: name,
      code: firstOf(rec, ['課號', '科目代號', '選課代號']),
      teacher: firstOf(rec, ['授課老師', '教師', '老師']),
      room: firstOf(rec, ['教室', '上課教室']),
      credits: toDouble(firstOf(rec, ['學分', '學分數'])),
      classLabel: firstOf(rec, ['年級班別', '班別']),
      selectionType: firstOf(rec, ['選別']),
      slots: parseTimeSlots(timeText),
      raw: rec,
    ));
  }
  return out;
}

/// `<table id="DataGrid">` 的表頭順序，UI 拿來決定 [Course.raw] 怎麼排。
List<String> courseListColumns(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('table#DataGrid');
  final rows = table != null ? _rowsOf(table) : const <List<String>>[];
  return rows.isEmpty ? const [] : rows.first;
}

List<List<String>> _rowsOf(dom.Element table) {
  final rows = <List<String>>[];
  for (final tr in table.querySelectorAll('tr')) {
    final cells = tr.querySelectorAll('td, th').map((c) => clean(c.text)).toList();
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows;
}

// ---------- 上課時間 ----------

final RegExp _weekdayTokenRe = RegExp(r'(?:星期|週|周)?([一二三四五六日七天])');

/// 把「上課時間」欄的文字解析成 [TimeSlot]。
///
/// **這個函式刻意不猜。** 支援的是明確的寫法：
/// ```
/// 一3,4      一 3-4     (一)3~4     週一第3節      一3
/// ```
/// 不支援連在一起的數字串（`一34`）—— 因為那是真的分不出來：
/// 海大的節次編號是 00–16（`Q_CLASS` 的選項），所以 `34` 可以是「第3、第4節」，
/// 也可以是「第34節」不存在因而應讀成 3 和 4，而 `12` 到底是「第12節」
/// 還是「第1、2節」**沒有任何線索可以判斷**。
///
/// 猜錯的代價不對稱：把課排到錯的格子，使用者看不出來，就這樣去錯的教室。
/// 所以分不出來時回空陣列 —— 課照樣列在清單裡，只是不畫進格子，
/// 原始文字仍然顯示在 [Course.raw] 裡。
///
/// > 這個帳號目前沒有修課資料（轉學生），所以**還沒有人拿真實的「上課時間」欄
/// > 對過這個函式**。選課之後第一件事就是回來補上真實格式。
List<TimeSlot> parseTimeSlots(String text) {
  final t = clean(text);
  if (t.isEmpty) return const [];

  final slots = <TimeSlot>{};
  final matches = _weekdayTokenRe.allMatches(t).toList();

  for (var i = 0; i < matches.length; i++) {
    final wd = _weekdayIndex(matches[i].group(1)!);
    if (wd == null) continue;
    final from = matches[i].end;
    final to = i + 1 < matches.length ? matches[i + 1].start : t.length;
    for (final p in _periodsIn(t.substring(from, to))) {
      slots.add(TimeSlot(wd, p));
    }
  }

  final list = slots.toList()..sort();
  return list;
}

int? _weekdayIndex(String ch) {
  final i = kWeekdays.indexOf(ch);
  if (i >= 0) return i;
  if (ch == '七' || ch == '天') return 6; // 週日的其他寫法
  return null;
}

final RegExp _numberRe = RegExp(r'\d+');
final RegExp _rangeRe = RegExp(r'(\d+)\s*[-~－〜–]\s*(\d+)');

/// 從一段文字裡抓節次。看得懂就回，看不懂就回空的（見 [parseTimeSlots] 的說明）。
List<int> _periodsIn(String segment) {
  final s = segment.trim();
  if (s.isEmpty) return const [];

  // 3-4 / 3~4：範圍
  final range = _rangeRe.firstMatch(s);
  if (range != null) {
    final a = int.parse(range.group(1)!);
    final b = int.parse(range.group(2)!);
    if (a <= b && b - a < 12) return [for (var p = a; p <= b; p++) p];
    return const [];
  }

  final numbers = _numberRe.allMatches(s).map((m) => m.group(0)!).toList();
  if (numbers.isEmpty) return const [];

  // 3,4 / 3 4 / 第3節第4節：有分隔，每個數字各自是一節
  if (numbers.length > 1) {
    return [for (final n in numbers) int.parse(n)];
  }

  // 只有一串數字。一位數沒有歧義；多位數分不出來（34 = 3和4？還是第34節？）
  final only = numbers.single;
  return only.length == 1 ? [int.parse(only)] : const [];
}

// ---------- 課程詳細頁 ----------

/// `__doPostBack('DataGrid$ctl02$COSID','')` 裡的目標。反斜線是可選的。
final RegExp _postBackTargetRe =
    RegExp(r"""__doPostBack\(\s*\\?['"]([^'"\\]+)""");

/// 查詢結果裡「課號」那一格的 `__doPostBack` 目標 —— 點下去會進課程詳細頁。
///
/// **一定要走 DOM，不能拿正則去比原始 HTML。** 頁面上的引號是 HTML 實體：
/// ```
/// href="javascript:__doPostBack(&#39;DataGrid$ctl02$COSID&#39;,&#39;&#39;)"
/// ```
/// 用 `__doPostBack\('…'` 去比原始碼**一列都對不到**，而且錯得很安靜：
/// 使用者看到的是「加進預排了，只是沒有上課時間」，看不出是解析失敗。
/// （`AisSession.autoPostBackFields` 為了同一件事也刻意走 DOM。）
///
/// **同一個課號常常有好幾列，而且上課時間不一樣。** 真實資料裡
/// `B57011RQ 計算機概論` 就同時有「1年A班／許為元」和「1年B班／林韓禹」。
/// 只比課號的話會固定拿第一列 —— 使用者加的是 B 班、填進去的卻是 A 班的時間，
/// 而且畫面上完全看不出來（有時間、看起來很正常，只是錯的）。
/// 所以要再用班別和老師把那一列認出來。
String? courseDetailTarget(
  String html,
  String code, {
  String classLabel = '',
  String teacher = '',
}) {
  final wanted = clean(code);
  if (wanted.isEmpty) return null;

  final doc = html_parser.parse(html);
  final hits = <({String target, String row})>[];
  for (final a in doc.querySelectorAll('a')) {
    if (clean(a.text) != wanted) continue;
    final href = a.attributes['href'] ?? a.attributes['onclick'] ?? '';
    final m = _postBackTargetRe.firstMatch(href);
    if (m != null) hits.add((target: m.group(1)!, row: clean(_rowTextOf(a))));
  }
  if (hits.isEmpty) return null;
  if (hits.length == 1) return hits.first.target;

  // 班別和老師都對得上的那一列最準；只對得上一個，也還是比「隨便拿第一列」好。
  final marks =
      [clean(classLabel), clean(teacher)].where((s) => s.isNotEmpty).toList();
  for (var need = marks.length; need >= 1; need--) {
    for (final h in hits) {
      if (marks.where(h.row.contains).length >= need) return h.target;
    }
  }
  return hits.first.target;
}

/// 課程內容頁上「上課時間」那一格。
///
/// 先認 id（`M_SEG`），再退而求其次認 `CNAME="時間"` —— 兩個都是頁面自己的宣告，
/// 學校改版時比「第幾格」可靠。
dom.Element? _timeFieldByCname(dom.Document doc) {
  for (final el in doc.querySelectorAll('span, td')) {
    final cname = el.attributes['cname'] ?? el.attributes['CNAME'];
    if (cname == '時間') return el;
  }
  return null;
}

/// 課程內容頁上放上課時間的欄位 id。
const String kCourseTimeFieldId = 'M_SEG';

/// 點課號之後真正要去的那一頁。
///
/// **點課號不會換頁。** 回應是同一份 HTML，只多注入一行
/// `fn_open('<PKNO>','<LESSON_TYPE>')`（其餘一個 byte 都沒變），瀏覽器據此
/// 開一個 FancyBox。真正的課程內容在 `TKE2240_03.aspx`，而且是**普通的 GET**。
///
/// 不知道這件事的話，會在查詢結果頁上找「上課時間」—— 而那一頁的「上課時間」
/// 全是分頁標籤「上課時間查詢」，永遠找不到值，症狀看起來像「這門課沒排時間」。
///
/// `PKNO` 是**純 9 碼數字**（例如 `137171415`），不是課號。
String? courseDetailUrl(String html) {
  final m = _fnOpenRe.firstMatch(html);
  if (m == null) return null;
  return '$kCourseDetailPath?PKNO=${m.group(1)}&LESSON_TYPE=${m.group(2)}';
}

const String kCourseDetailPath = 'Application/TKE/TKE22/TKE2240_03.aspx';

/// 定義本身（`function fn_open(pkno, lesson_type)`）的參數沒有引號，不會誤中。
final RegExp _fnOpenRe =
    RegExp(r"""fn_open\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]*)['"]\s*\)""");

/// 這個連結所在的那一列的文字。認不出 `<tr>` 就退回連結自己的文字。
String _rowTextOf(dom.Element el) {
  for (dom.Element? n = el; n != null; n = n.parent) {
    if (n.localName == 'tr') return n.text;
  }
  return el.text;
}

/// 學校的上課時間代碼：`102 103 104` = 週一第 2、3、4 節。
///
/// 第一碼是星期，跟查詢頁的 `Q_WEEK` 同一套（1 = 週一）；後兩碼是節次，
/// 跟 `Q_CLASS` 同一套（`00`–`16` —— 海大有第 0 節，所以不能從 01 起算）。
///
/// [TimeSlot.weekday] 是 **0 起算**的，所以第一碼要減一。少減這一格，
/// 整張課表會整個往後挪一天，而畫面上完全看不出來 ——
/// 使用者就照著錯的格子去上課了。
List<TimeSlot> parseTimeCodes(String text) {
  final slots = <TimeSlot>{};
  for (final m in _timeCodeRe.allMatches(text)) {
    slots.add(TimeSlot(int.parse(m.group(1)!) - 1, int.parse(m.group(2)!)));
  }
  return slots.toList()..sort();
}

/// 一個代碼。前後不能再接數字，不然「1102」會被切成「110」。
final RegExp _timeCodeRe =
    RegExp(r'(?<![0-9])([1-7])(0[0-9]|1[0-6])(?![0-9])');

/// 連在一起的一串代碼（兩個以上）。
final RegExp _timeCodeGroupRe = RegExp(
  r'(?<![0-9])[1-7](?:0[0-9]|1[0-6])'
  r'(?:[\s,、;/]+[1-7](?:0[0-9]|1[0-6]))+(?![0-9])',
);

/// 「上課時間」在不同頁面上的幾種寫法。
const List<String> _timeLabels = ['上課時間', '上課時段', '授課時間', '星期節次'];

/// 標籤那一格後面**緊接著**的一串代碼（「上課時間：102 103 104 上課教室 …」）。
/// 遇到第一個非數字就停 —— 再過去就是教室了，而「綜一301」裡的 301
/// 長得跟時間代碼一模一樣。
final RegExp _codesRightAfterLabelRe =
    RegExp(r'^[\s:：]*((?:[0-9]{3}[\s,、;/]*)+)');

/// 從課程詳細頁抓上課時間。
///
/// **只有看得見的文字算數，`<script>` 要先拿掉。** 課程查詢頁的 JS 驗證區塊裡
/// 就寫著 `case "5": //上課時間`，而且在整份 HTML 的最前面 ——
/// 直接對原始碼 `indexOf('上課時間')` 會先撞到那個註解，然後在一段 JavaScript
/// 裡面找節次代碼。結果是永遠抓不到，但看起來像「這門課沒有排時間」。
///
/// 抓法是「找標籤那一格，讀它旁邊那一格」，不是「往後掃一段文字」——
/// 隔壁欄就是教室，掃過頭會把教室代碼當成上課時間。
///
/// 完全找不到標籤時退一步找**連在一起的一串**代碼。單獨一個三位數不算：
/// 人數、教室、學號都長那樣，猜錯會把課排到完全無關的格子裡。
List<TimeSlot> parseCourseTimeSlots(String html) {
  final doc = html_parser.parse(html);
  for (final el in doc.querySelectorAll('script, style')) {
    el.remove();
  }

  // 課程內容頁把上課時間放在一個有 id 的欄位裡：
  //     <span id="M_SEG" CNAME="時間">102,103,104</span>
  //
  // **優先讀它，不要掃文字。** 它隔壁那一格是上課地點，真實資料長這樣：
  //     <span id="M_CLSSRM_ID" CNAME="教室代號">INS105,INS105,INS105</span>
  // `INS105` 裡的 105 就是合法的時間代碼（週一第 5 節）—— 掃文字會憑空
  // 多排一節課出來，而使用者看到的是一門「多上一節」的課，不會知道哪裡錯了。
  // **有 `M_SEG` 就完全以它為準：有值就是值，空的就是「這門課沒排時間」。**
  //
  // 特別不要在它是空的時候退回掃文字。課程內容頁在 PKNO 不對時會回一份
  // `Mode=ADD` 的空殼（每一格都是空的），那時候掃文字等於拿頁面上任何一個
  // 三位數來當上課時間 —— 寧可回「沒有時間」讓使用者自己填，
  // 也不要給一個看起來很正常、其實是亂猜的時段。
  final byId = doc.querySelector('#$kCourseTimeFieldId');
  if (byId != null) return parseTimeCodes(clean(byId.text));

  // 沒有那個 id 才退而求其次認 `CNAME` —— 這個比對比較鬆，所以只在
  // 真的解出東西時才採用。
  final byName = _timeFieldByCname(doc);
  if (byName != null) {
    final slots = parseTimeCodes(clean(byName.text));
    if (slots.isNotEmpty) return slots;
  }

  for (final cell in doc.querySelectorAll('th, td, dt, label, span')) {
    final rest = _afterTimeLabel(clean(cell.text));
    if (rest == null) continue;

    // 標籤和值擠在同一格：「上課時間：102 103 104」
    if (rest.isNotEmpty) {
      final m = _codesRightAfterLabelRe.firstMatch(rest);
      final slots = m == null ? const <TimeSlot>[] : parseTimeCodes(m.group(1)!);
      if (slots.isNotEmpty) return slots;
      continue;
    }

    // 這一格只是標籤，值在隔壁那一格
    final next = cell.nextElementSibling;
    if (next == null) continue;
    final slots = parseTimeCodes(clean(next.text));
    if (slots.isNotEmpty) return slots;
  }

  final group = _timeCodeGroupRe.firstMatch(clean(_visibleText(doc)));
  return group == null ? const [] : parseTimeCodes(group.group(0)!);
}

/// 這一格是不是「上課時間」的標籤；是的話回標籤後面剩下的字。
///
/// 要求**開頭**就是標籤，不是「有出現」—— 不然整個 `<td>` 的外層容器也會中，
/// 而那一格的文字連隔壁的教室都吃進來了。
String? _afterTimeLabel(String text) {
  for (final label in _timeLabels) {
    if (text.startsWith(label)) return text.substring(label.length).trim();
  }
  return null;
}

/// 攤平可見文字，**每個元素之間補一個空白**。
///
/// `Element.text` 會把相鄰兩格直接黏起來：`<td>65</td><td>102</td>` 變成
/// `65102`，於是「102」這個代碼就這樣消失了。
String _visibleText(dom.Document doc) {
  final buf = StringBuffer();
  void walk(dom.Node node) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        buf.write(child.text);
      } else if (child is dom.Element) {
        buf.write(' ');
        walk(child);
        buf.write(' ');
      }
    }
  }

  final body = doc.body ?? doc.documentElement;
  if (body != null) walk(body);
  return buf.toString();
}

// ---------- 課表格線 ----------

/// 表頭文字 -> {欄索引: 星期索引}（0 = 週一）。
///
/// 用文字比對而不是假設「第一欄是節次、後面七欄依序是一到日」——
/// 有些課表把週六日放前面、有些沒有週日、有些節次欄在最右邊。
///
/// 「第一節」「第三節」這種會誤中「一」「三」，所以含「節」的欄位一律排除。
Map<int, int> weekdayColumns(List<String> header) {
  final out = <int, int>{};
  for (var col = 0; col < header.length; col++) {
    final text = header[col];
    if (text.isEmpty || text.contains('節') || text.length > _weekdayHeaderMax) {
      continue;
    }
    for (var wd = 0; wd < kWeekdays.length; wd++) {
      if (text.contains(kWeekdays[wd])) {
        out[col] = wd;
        break;
      }
    }
  }
  return out;
}

/// 課表格子裡通常是「課名 / 老師 / 教室」擠在一起，用 `<br>` 分行。
///
/// 刻意寫得寬鬆 —— 這裡猜錯只是少顯示一個欄位，不該讓整張課表掛掉。
({String name, String teacher, String room}) parseTimetableCell(String text) {
  final parts = text
      .split(RegExp(r'[\n/｜|]+'))
      .map(clean)
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return (name: '', teacher: '', room: '');

  var room = '';
  var teacher = '';
  for (final p in parts.skip(1)) {
    if (room.isEmpty && _roomRe.hasMatch(p)) {
      room = p;
    } else if (teacher.isEmpty &&
        p.length >= _teacherNameMin &&
        p.length <= _teacherNameMax) {
      teacher = p;
    }
  }
  return (name: parts.first, teacher: teacher, room: room);
}

/// 從畫成格子的課表頁抓課（教師課表、選課課表那種）。
///
/// 用 [expandGrid] 攤平 rowspan / colspan —— 連堂課是用 rowspan 表示的，
/// 照位置逐格讀的話，兩小時的課只會出現在第一節。
///
/// 節次欄不假設在第 0 欄，而是「表頭認不出是星期的那一欄」。
List<Course> parseTimetableGrid(String html) {
  final doc = html_parser.parse(html);

  for (final table in doc.querySelectorAll('table')) {
    final grid = expandGrid(table);
    if (grid.length < _minTimetableRows) continue;

    final header = [for (final c in grid.first) c == null ? '' : clean(c.text)];
    final wdCols = weekdayColumns(header);
    if (wdCols.length < _minWeekdayColumns) continue;

    var periodCol = 0;
    for (var i = 0; i < header.length; i++) {
      if (!wdCols.containsKey(i)) {
        periodCol = i;
        break;
      }
    }

    final courses = <String, Course>{};
    final slots = <String, Set<TimeSlot>>{};

    for (var r = 1; r < grid.length; r++) {
      final row = grid[r];
      final periodCell = periodCol < row.length ? row[periodCol] : null;
      final period = periodCell == null ? null : _periodOf(clean(periodCell.text));

      wdCols.forEach((col, wd) {
        if (col >= row.length) return;
        final cell = row[col];
        if (cell == null) return;
        final raw = _cellLines(cell);
        if (clean(raw).isEmpty) return;

        final parsed = parseTimetableCell(raw);
        if (parsed.name.isEmpty) return;

        final key = '${parsed.name}|${parsed.teacher}';
        courses.putIfAbsent(
          key,
          () => Course(
            name: parsed.name,
            teacher: parsed.teacher,
            room: parsed.room,
          ),
        );
        if (period != null) {
          (slots[key] ??= <TimeSlot>{}).add(TimeSlot(wd, period));
        }
      });
    }

    if (courses.isNotEmpty) {
      final out = [
        for (final e in courses.entries)
          e.value.copyWith(slots: (slots[e.key]?.toList() ?? <TimeSlot>[])..sort()),
      ];
      out.sort((a, b) {
        final sa = a.slots.isEmpty ? const TimeSlot(99, 99) : a.slots.first;
        final sb = b.slots.isEmpty ? const TimeSlot(99, 99) : b.slots.first;
        final c = sa.compareTo(sb);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
      return out;
    }
  }
  return const [];
}

/// `<br>` 要變成換行，不然課名和老師會黏成一串。
String _cellLines(dom.Element cell) {
  final buf = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buf.write(node.text);
    } else if (node is dom.Element) {
      if (node.localName == 'br') {
        buf.write('\n');
      } else {
        node.nodes.forEach(walk);
      }
    }
  }

  cell.nodes.forEach(walk);
  return buf.toString();
}

/// 節次欄可能是 `1`、`第1節`、`A`、`08:10~09:00`。抓得到數字就用。
int? _periodOf(String text) {
  final m = _numberRe.firstMatch(text);
  return m == null ? null : int.parse(m.group(0)!);
}

// ---------- 「選課課表」的格子（QUERY_BTN3） ----------

/// 「選課課表」那張格子的 table id。
const String kGridTableId = 'table2';

/// 格子裡的一門課。
///
/// 跟「選課清單」（`QUERY_BTN1`）互補：清單有學分、選別、授課老師，但
/// **一欄時間都沒有**（16 欄逐欄看過，2026-09-03 實測）；這張格子有時間和
/// 教室，卻沒有學分和老師。兩邊靠課號合併。
class GridCourse {
  const GridCourse({
    required this.code,
    required this.name,
    this.unit = '',
    this.classLabel = '',
    this.room = '',
    this.slots = const [],
  });

  final String code;
  final String name;

  /// 開課單位。
  final String unit;

  /// 格子裡寫的是短班別（`1A`），選課清單寫的是長的（`1年A班`）——
  /// 所以**不能拿它跟清單比對**，合併一律用課號。
  final String classLabel;

  final String room;
  final List<TimeSlot> slots;

  GridCourse withSlots(List<TimeSlot> s) => GridCourse(
        code: code,
        name: name,
        unit: unit,
        classLabel: classLabel,
        room: room,
        slots: s,
      );
}

/// 解析「選課課表」回的那張格子，回傳「課號 → 這門課」。
///
/// 跟 [parseTimetableGrid] 的差別：那個是通用的格子解析（教師課表那種），
/// 靠啟發式猜哪一段是老師、哪一段是教室；這一頁的格子每一段的意義是固定的，
/// 而且**帶課號** —— 有課號才能跟選課清單合併，所以另外寫一個。
///
/// 頁面結構（真實資料，見
/// `spike/fixtures/…TKE2240_01__QUERY_BTN3_115_1.html`）：
/// ```html
/// <table id='table2'>
///   <tr><td>&nbsp;</td><td>星期一</td>…<td>星期日</td></tr>
///   <tr><td>第二節<br/>09:20<br/>~<br/>10:10<br/></td>
///       <td><a href='javascript:fn_open("…");'>計算機概論<br>B57011RQ<br>
///           資訊工程學系<br>1A<br>INS105</a></td>
///       …
/// ```
///
/// **星期是從表頭對出來的，不是靠欄位索引硬數。** 這張表的標記是壞的
/// （每個 `<td>` 後面多一個 `</td>`），解析器補救的方式不保證跨版本一樣 ——
/// 靠索引的話某次改版就會讓整張課表平移一天，而畫面上完全看不出來
/// （每一格都有課、看起來很正常，只是全錯）。表頭對不到就不猜，回空的。
Map<String, GridCourse> parseEnrolledGrid(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('#$kGridTableId');
  if (table == null) return const {};

  final rows = table.querySelectorAll('tr');
  if (rows.length < 2) return const {};

  // 表頭：欄位索引 → 星期（0 = 週一）。
  final weekdayOfColumn = <int, int>{};
  final headers = rows.first.querySelectorAll('td');
  for (var i = 0; i < headers.length; i++) {
    final w = _weekdayOfHeader(clean(headers[i].text));
    if (w != null) weekdayOfColumn[i] = w;
  }
  if (weekdayOfColumn.isEmpty) return const {};

  final byCode = <String, GridCourse>{};
  final slotsByCode = <String, Set<TimeSlot>>{};

  for (final row in rows.skip(1)) {
    final cells = row.querySelectorAll('td');
    final period = _gridPeriodOf(clean(cells.isEmpty ? '' : cells.first.text));
    if (period == null) continue;

    for (var i = 1; i < cells.length; i++) {
      final weekday = weekdayOfColumn[i];
      // 表頭沒有對應的欄就跳過，不要猜。
      if (weekday == null) continue;

      // 同一格可能不只一門課（同時段擋修、或學校排錯）。
      for (final link in cells[i].querySelectorAll('a')) {
        final g = _gridCourseOf(link);
        if (g == null) continue;
        byCode.putIfAbsent(g.code, () => g);
        (slotsByCode[g.code] ??= <TimeSlot>{}).add(TimeSlot(weekday, period));
      }
    }
  }

  return {
    for (final e in byCode.entries)
      e.key: e.value.withSlots(
        (slotsByCode[e.key]?.toList() ?? <TimeSlot>[])..sort(),
      ),
  };
}

/// 一格裡的 `<a>`：`課名<br>課號<br>開課單位<br>班別<br>教室`。
///
/// 用 `innerHtml` 拆 `<br>` 而不是讀 `.text` —— `.text` 會把五段黏成一串
/// （`計算機概論B57011RQ資訊工程學系1AINS105`），拆不開。
GridCourse? _gridCourseOf(dom.Element link) {
  final parts = link.innerHtml
      .split(RegExp(r'<br\s*/?>', caseSensitive: false))
      .map((s) => clean(s.replaceAll(RegExp(r'<[^>]*>'), '')))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length < 2) return null;

  // 課號沒有就沒辦法跟選課清單合併，這一格等於用不上。
  final code = parts[1];
  if (code.isEmpty) return null;

  return GridCourse(
    code: code,
    name: parts[0],
    unit: parts.length > 2 ? parts[2] : '',
    classLabel: parts.length > 3 ? parts[3] : '',
    room: parts.length > 4 ? parts[4] : '',
  );
}

/// 「星期一」→ 0。認不得就回 null。
int? _weekdayOfHeader(String text) {
  for (var i = 0; i < kWeekdays.length; i++) {
    if (text.contains('星期${kWeekdays[i]}') || text == kWeekdays[i]) return i;
  }
  return null;
}

/// 「第二節」→ 2、「第0節」→ 0、「第十四節」→ 14。
///
/// 不能用通用的 [_periodOf]（抓文字裡第一個數字）—— 這一頁的節次欄同時寫著
/// 時鐘時間（`第二節09:20~10:10`），抓到的會是 `09`，整張課表平移七節。
///
/// 學校在同一張表裡混用兩種寫法：第 0 節是阿拉伯數字，其餘是國字。
int? _gridPeriodOf(String text) {
  final m = RegExp(r'第\s*([0-9〇零一二三四五六七八九十]+)\s*節').firstMatch(text);
  return m == null ? null : _cjkNumber(m.group(1)!);
}

/// 0–19 的國字或阿拉伯數字。這張表只到 14，不必處理「二十一」那種。
int? _cjkNumber(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;

  final arabic = int.tryParse(t);
  if (arabic != null) return arabic;

  const digits = <String, int>{
    '〇': 0, '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  if (t == '十') return 10;
  if (t.startsWith('十') && t.length == 2) {
    final d = digits[t.substring(1)];
    return d == null ? null : 10 + d;
  }
  return t.length == 1 ? digits[t] : null;
}

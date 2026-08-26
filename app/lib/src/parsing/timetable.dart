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
/// 同一個課號可能有好幾列（不同班別開的同一門課），這裡回**第一列**。
String? courseDetailTarget(String html, String code) {
  final wanted = clean(code);
  if (wanted.isEmpty) return null;

  final doc = html_parser.parse(html);
  for (final a in doc.querySelectorAll('a')) {
    if (clean(a.text) != wanted) continue;
    final href = a.attributes['href'] ?? a.attributes['onclick'] ?? '';
    final m = _postBackTargetRe.firstMatch(href);
    if (m != null) return m.group(1);
  }
  return null;
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

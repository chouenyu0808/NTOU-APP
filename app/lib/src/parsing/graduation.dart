/// 「查詢畢業資格」（`ENRG010`）解出來的東西。
///
/// **這一頁回答的是「我還差什麼才能畢業」**，不是成績單。它把系上的必修課目
/// 表和你實際修過的課擺在同一列上對照 —— 左半邊是你修的（修課學年期、
/// 原修課程名稱、成績），右半邊是要求（第幾學期、必修課目、幾學分）。
///
/// 所以還沒修的課，那一列的左半邊就是**整排空白**。這不是解析失敗，是
/// 「這門課你還沒修」—— 兩者在畫面上必須分得出來。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_text.dart';

/// 一門必修課目，以及你修過它沒有。
class RequiredCourse {
  const RequiredCourse({
    required this.term,
    required this.name,
    this.credits,
    this.takenTerm,
    this.takenName,
    this.grade,
    this.review,
  });

  /// 建議修課學期，學校寫成「一上」「三下」。
  final String term;

  /// 必修課目名稱。可能是具體課名（「計算機概論」），也可能是一個領域
  /// （「12-國文領域」「11-博雅課程」）—— 後者是「這個領域修滿 N 學分」，
  /// 不是某一門特定的課。
  final String name;

  /// 要求學分。**0 是有意義的值**（游泳畢業門檻、體育課程），不是缺值 ——
  /// 那種要求是「通過」而不是「拿到學分」。
  final int? credits;

  /// 你實際修這門課的學年期（`1141`）。還沒修就是 null。
  final String? takenTerm;

  /// 你實際修的那門課的名稱。跟 [name] 不一定一樣 ——
  /// 領域型的要求（「11-博雅課程」）底下修的是某一門具體的課。
  final String? takenName;

  /// 成績。學校用 `＊` 表示不及格、`＋` 表示成績未到（頁面下方的說明）。
  final String? grade;

  /// 審核結果（抵免、承認之類的批註）。
  final String? review;

  /// 修過了沒。
  ///
  /// 判斷用「有沒有修課學年期」而不是「有沒有成績」—— 這學期正在修的課
  /// 有學年期但還沒有成績，那也是「修了」。
  bool get taken => (takenTerm ?? '').isNotEmpty;
}

/// 一個科目類別的學分統計（`DataGrid_CRD` 上的一列）。
class CreditSummary {
  const CreditSummary({
    required this.category,
    this.required_,
    this.earned,
    this.inProgress,
    this.failed,
    this.failedCourses,
  });

  final String category;

  /// 應修學分。選修那一列學校給的是 `-`，那時候是 null。
  final int? required_;
  final int? earned;
  final int? inProgress;

  /// 還沒通過的學分與科目數。**這兩個才是使用者真正要看的數字。**
  final int? failed;
  final int? failedCourses;
}

/// 一個科目類別（共同教育課程、系訂專業必修…）底下的全部要求。
class RequirementGroup {
  const RequirementGroup({
    required this.category,
    required this.courses,
    this.summary,
  });

  final String category;
  final List<RequiredCourse> courses;
  final CreditSummary? summary;

  int get takenCount => courses.where((c) => c.taken).length;
}

/// 整頁的結果。
class GraduationStatus {
  const GraduationStatus({
    required this.groups,
    this.otherSummaries = const [],
  });

  final List<RequirementGroup> groups;

  /// `DataGrid_CRD` 上沒有對應課目清單的那幾列（選修、其他原修課程…）。
  final List<CreditSummary> otherSummaries;

  bool get isEmpty => groups.isEmpty && otherSummaries.isEmpty;
}

/// 表頭裡第一個叫 [name] 的欄。找不到回 -1。
int _columnIndex(List<String> header, String name) => header.indexOf(name);

/// [after] 這一欄後面緊接著的那個 [name] 欄。
///
/// **表頭裡「學分」出現兩次** —— 一次在「成績」後面（你實得的），一次在
/// 「必修課目」後面（要求的）。只用 `indexOf('學分')` 會永遠拿到第一個，
/// 於是「要求幾學分」那一欄整欄讀成空的，而畫面上看起來只是「這門課沒有
/// 標學分」。
int _columnAfter(List<String> header, String after, String name) {
  final base = header.indexOf(after);
  if (base < 0) return -1;
  final at = header.indexOf(name, base + 1);
  // 必須是緊接著的下一欄，不然就是撞到表格另一頭同名的欄位。
  return at == base + 1 ? at : -1;
}

String? _cell(List<String> cells, int index) {
  if (index < 0 || index >= cells.length) return null;
  final v = cells[index].trim();
  return v.isEmpty ? null : v;
}

int? _intCell(List<String> cells, int index) {
  final v = _cell(cells, index);
  if (v == null) return null;
  return int.tryParse(v.replaceAll(RegExp(r'[^\d-]'), ''));
}

List<String> _rowCells(dom.Element row) =>
    row.querySelectorAll('td, th').map((c) => clean(c.text)).toList();

/// 解析「查詢畢業資格」那一頁。
GraduationStatus parseGraduation(String html) {
  final doc = html_parser.parse(html);

  // ---- 各類別的必修課目 ----
  //
  // 巢狀表格的 id 是 `DataList_ctl00_DataGrid_FIELD`、`ctl01`…，類別名稱
  // （「共同教育課程」）在它上層那個儲存格的第一段文字裡 —— DataList 的
  // item 樣板就是「標題 + 一張表」。
  final groups = <RequirementGroup>[];
  for (final table in doc.querySelectorAll('table[id]')) {
    final id = table.id;
    if (!RegExp(r'^DataList_ctl\d+_DataGrid_FIELD$').hasMatch(id)) continue;

    final rows = table.querySelectorAll('tr');
    if (rows.length < 2) continue;

    final header = _rowCells(rows.first);
    final termAt = _columnIndex(header, '學期');
    final nameAt = _columnIndex(header, '必修課目');
    final creditAt = _columnAfter(header, '必修課目', '學分');
    final takenTermAt = _columnIndex(header, '修課學年期');
    final takenNameAt = _columnIndex(header, '原修課程名稱');
    final gradeAt = _columnIndex(header, '成績');
    final reviewAt = _columnIndex(header, '審核結果');

    final courses = <RequiredCourse>[];
    for (final row in rows.skip(1)) {
      final cells = _rowCells(row);
      final name = _cell(cells, nameAt);
      // 沒有課目名稱的列是小計或表格自己的裝飾，跳過。
      if (name == null) continue;
      courses.add(RequiredCourse(
        term: _cell(cells, termAt) ?? '',
        name: name,
        credits: _intCell(cells, creditAt),
        takenTerm: _cell(cells, takenTermAt),
        takenName: _cell(cells, takenNameAt),
        grade: _cell(cells, gradeAt),
        review: _cell(cells, reviewAt),
      ));
    }
    if (courses.isEmpty) continue;

    groups.add(RequirementGroup(
      category: _categoryOf(table) ?? id,
      courses: courses,
    ));
  }

  // ---- 學分統計，貼回各自的類別 ----
  final summaries = _parseCredits(doc);
  final byCategory = {for (final s in summaries) s.category: s};
  final used = <String>{};

  final merged = [
    for (final g in groups)
      RequirementGroup(
        category: g.category,
        courses: g.courses,
        summary: () {
          final s = byCategory[g.category];
          if (s != null) used.add(g.category);
          return s;
        }(),
      ),
  ];

  return GraduationStatus(
    groups: merged,
    otherSummaries: [
      for (final s in summaries)
        if (!used.contains(s.category)) s,
    ],
  );
}

/// 巢狀表格所屬的類別名稱。
///
/// DataList 的 item 樣板是「標題 + 一張表」，所以類別名（「共同教育課程」）
/// 是這張表**前面**的那段文字。
///
/// **不能用 `parent.text`** —— 那是整個後代的文字串接，表格自己的內容
/// 也在裡面，切不出標題（第一版就是這樣，結果每個類別的名字都變成
/// `DataList_ctl00_DataGrid_FIELD` 這種 id）。
///
/// **標題離表格很遠。** DataList 的 item 是一個 `<td>`，而表格被
/// bootstrap 的版面包在五層 div 裡（`col-md-12` → `table-responsive` →
/// `dataTables_wrapper` → `grid-scroll` → …）。所以「看表格前面的兄弟節點」
/// 一路都是空的 —— 要先往上找到那個 td，再從它的開頭走到表格為止。
String? _categoryOf(dom.Element table) {
  dom.Element? holder = table.parent;
  while (holder != null && holder.localName != 'td') {
    holder = holder.parent;
  }
  if (holder == null) return null;

  String? title;
  var reached = false;

  void walk(dom.Node node) {
    if (reached) return;
    if (identical(node, table)) {
      reached = true;
      return;
    }
    if (node is dom.Text) {
      final t = clean(node.data);
      if (t.isNotEmpty) title ??= t;
    }
    for (final child in node.nodes) {
      walk(child);
      if (reached) return;
    }
  }

  walk(holder);
  return title;
}

/// `DataGrid_CRD`：總計學分表。
List<CreditSummary> _parseCredits(dom.Document doc) {
  final table = doc.querySelector('table#DataGrid_CRD');
  if (table == null) return const [];

  final rows = table.querySelectorAll('tr');
  if (rows.length < 2) return const [];

  final header = _rowCells(rows.first);
  final requiredAt = _columnIndex(header, '應修學分');
  final earnedAt = _columnIndex(header, '已得學分(1)');
  final progressAt = _columnIndex(header, '修讀中學分(2)');
  final failedAt = _columnIndex(header, '未通過學分');
  final failedCoursesAt = _columnIndex(header, '未通過科目');

  return [
    for (final row in rows.skip(1))
      if (_rowCells(row).isNotEmpty && _rowCells(row).first.isNotEmpty)
        () {
          final cells = _rowCells(row);
          return CreditSummary(
            category: cells.first,
            required_: _intCell(cells, requiredAt),
            earned: _intCell(cells, earnedAt),
            inProgress: _intCell(cells, progressAt),
            failed: _intCell(cells, failedAt),
            failedCourses: _intCell(cells, failedCoursesAt),
          );
        }(),
  ];
}

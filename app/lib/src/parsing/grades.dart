/// 成績單（`GRD5010_02`）。
///
/// 「查詢各式成績」按下查詢回來的是一列**學生清單**，成績在「詳」點進去的
/// 明細頁 —— 而那一頁的 HTML 裡一張表都沒有，成績是它載入後自己發一發
/// `__doPostBack('ReQuery','')` 才補回來的。App 不跑 JS，所以那一步要自己做
/// （見 `AisRepository.openGrades`）。少了它拿到的是一份**看起來很正常的空殼**：
/// 欄位全空、零筆成績，跟「這個帳號沒有成績」長得一模一樣。
library;

import 'package:html/parser.dart' as html_parser;

import 'data_grid.dart';
import 'html_text.dart';
import 'label_value.dart';

/// 「學期總成績」那一欄。
///
/// **它不是數字。** 學校在同一欄裡混著分數和狀態記號，頁尾的圖例寫著：
///
/// ```
/// ＊表不及格　＋表成績未到　W表期中退選　抵表抵免
/// ```
///
/// 所以這裡存的是原始字串，數字只是其中一種可能。當成數字解析、解不到就
/// 給 0 的話，一個「成績未到」的學期會變成「平均 0 分」。
class GradeMark {
  const GradeMark({required this.raw, this.score, this.note});

  /// 學校原本寫在那一格的東西。認不得的時候照它顯示。
  final String raw;

  /// 分數的部分，沒有就 null。**刻意留字串** —— 這一欄也可能是
  /// 「甲」「通過」這種等第，轉成數字等於把認不得的東西變成 0。
  final String? score;

  /// 記號的意思（「成績未到」「抵免」…）。認不得的記號是 null，
  /// 那時候畫面上照 [raw] 顯示，不要自己編一個說法。
  final String? note;

  bool get isPending => note == _pending;
  bool get isTransferred => note == _transferred;
  bool get isFailed => note == _failed;
  bool get isWithdrawn => note == _withdrawn;

  /// 還沒有結果可言 —— 成績未到、期中退選。
  bool get hasNoScore => score == null;

  /// 這門課算不算過了。
  ///
  /// **靠學校自己的記號判斷，不自己訂及格分數。** 學校在不及格的成績上會標
  /// `＊`（頁尾圖例寫著），所以「沒有被標不及格」就是過了。自己訂一條
  /// 60 分的線反而會錯：研究所是 70，而且這一欄還可能是「甲」「通過」
  /// 這種等第 —— 那些用數字比大小一律會判成不及格。
  ///
  /// 抵免算過。成績未到和期中退選不算 —— 那兩個都還沒有結果。
  bool get isPassed {
    if (isFailed || isWithdrawn || isPending) return false;
    return isTransferred || score != null;
  }

  static const _pending = '成績未到';
  static const _transferred = '抵免';
  static const _failed = '不及格';
  static const _withdrawn = '期中退選';
}

/// **半形和全形都要收。**
///
/// 頁尾圖例印的是全形（`＊` U+FF0A、`＋` U+FF0B），但**儲存格裡是半形**
/// （`+` U+002B，2026-09-16 實測 6 筆全是）。照圖例上的字元去比對，
/// 永遠不會命中 —— 而畫面上不會報錯，只會出現一個沒有任何說明的裸 `+`，
/// 使用者不知道那是「還沒登記」還是「零分」。
const Map<String, String> _marks = {
  '*': GradeMark._failed,
  '＊': GradeMark._failed,
  '+': GradeMark._pending,
  '＋': GradeMark._pending,
  'W': GradeMark._withdrawn,
  'w': GradeMark._withdrawn,
  'Ｗ': GradeMark._withdrawn,
  '抵': GradeMark._transferred,
};

/// 把「學期總成績」那一格拆成分數和記號。
GradeMark parseGradeMark(String raw) {
  final text = clean(raw);
  if (text.isEmpty) return const GradeMark(raw: '');

  // 記號單獨出現（目前手上的真實資料全是這種）。
  final whole = _marks[text];
  if (whole != null) return GradeMark(raw: text, note: whole);

  // 記號黏在分數前後（`*55`）。圖例說「＊表不及格」但沒說它怎麼跟分數並存，
  // **所以兩種擺法都認，而且分數照原樣留著** —— 猜錯擺法的代價是把
  // 一個有分數的儲存格判成沒分數。
  for (final entry in _marks.entries) {
    if (text.length <= entry.key.length) continue;
    if (text.startsWith(entry.key) || text.endsWith(entry.key)) {
      final rest = clean(text.replaceAll(entry.key, ''));
      if (rest.isEmpty) continue;
      return GradeMark(raw: text, score: rest, note: entry.value);
    }
  }

  // 認不得的就是分數本身（數字、或是「甲」「通過」這種等第）。
  return GradeMark(raw: text, score: text);
}

/// 「詳」那一列要送到哪、送什麼。
class GradeDetailRequest {
  const GradeDetailRequest({required this.page, required this.fields});

  /// 目標頁的檔名，**相對於當前這個功能頁**（功能頁埋在
  /// `Application/GRD/GRD50/`，用網站根目錄去解會跑到別的地方）。
  final String page;

  final Map<String, String> fields;
}

final RegExp _doEditRe = RegExp(
  """doEdit1_2\\(\\s*['"][^'"]*['"]\\s*,\\s*['"]([^'"]+)['"]\\s*,"""
  """\\s*['"]([^'"]+)['"]\\s*\\)""",
);
final RegExp _viewPageRe = RegExp("""\\bviewpage\\s*=\\s*['"]([^'"]+)['"]""");

/// 查詢結果那一列的「詳」。沒有就回 null。
///
/// **查詢回來的不是成績，是一份清單。** 按下查詢拿到的是一列
/// 「部別／系所／年級／班級／學號／姓名」，成績在明細頁 `GRD5010_02.aspx`。
/// 而「詳」是 `<a href="#">`，DOM 上看不出任何目標 —— 真正的動作在頁尾
/// 注入的這一行：
///
/// ```js
/// var viewpage = "GRD5010_02.aspx";
/// doEdit1_2('', 'STNO|B10900000', 'Mod');
/// ```
///
/// 照學校 `PageScript.js` 的實作：keyStr 依 `名稱|值|名稱|值…` 拆開，
/// 配上 `Mode=<type 大寫>`，然後當場建一個 `method="POST"` 的表單送出去。
/// 所以這是 **POST 不是 GET**，而且**沒有 `__VIEWSTATE`**（表單是 JS 現做的）。
/// 拼成 query string 去 GET 會拿到一頁空表單，而且不會報錯。
GradeDetailRequest? parseGradeDetailRequest(String html) {
  final key = _doEditRe.firstMatch(html);
  final view = _viewPageRe.firstMatch(html);
  if (key == null || view == null) return null;

  final parts = key.group(1)!.split('|');
  final fields = <String, String>{'Mode': key.group(2)!.toUpperCase()};
  for (var i = 0; i + 1 < parts.length; i += 2) {
    fields[parts[i]] = parts[i + 1];
  }
  return GradeDetailRequest(page: view.group(1)!, fields: fields);
}

/// 一門課的成績。
class CourseGrade {
  const CourseGrade({
    required this.term,
    required this.name,
    required this.mark,
    this.code = '',
    this.classNo = '',
    this.kind = '',
    this.teacher = '',
    this.credits,
  });

  /// 學年期，例如 `1151`。**同一份成績單裡會有不只一期**（抵免會掛在
  /// 未來的學期上：2026-09-16 實測 1151 有 21 筆、1152 有 4 筆）。
  final String term;

  final String name;
  final String code;
  final String classNo;

  /// 選別：必修 / 選修 / 通識。
  final String kind;

  final String teacher;

  /// 學分數。**0 是真的有意義的值**（體育就是 0 學分），所以解不到時是 null，
  /// 不是 0 —— 那兩件事在畫面上要講不一樣的話。
  final int? credits;

  final GradeMark mark;
}

/// 整份成績單。
class GradeReport {
  const GradeReport({
    required this.courses,
    this.totals = const {},
  });

  final List<CourseGrade> courses;

  /// 上面那排統計（歷年累計學分、實得學分、平均、排名…）。
  ///
  /// **只收有值的。** 學校在還沒有成績的時候把這些欄位留空，
  /// 空的收進來再顯示成 0，等於告訴使用者「你的平均是 0 分」。
  final Map<String, String> totals;

  bool get isEmpty => courses.isEmpty;

  /// 出現過的學年期，新的在前面。
  List<String> get terms {
    final seen = <String>{for (final c in courses) c.term};
    final list = seen.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<CourseGrade> inTerm(String term) =>
      [for (final c in courses) if (c.term == term) c];
}

/// 上面那排統計欄的標籤。畫面上照這個順序排。
const List<String> _totalLabels = [
  '實得學分',
  '目前平均成績',
  '總修學分',
  '歷年累計學分',
  '抵免學分',
  '班排名',
  '系排名',
];

/// 欄位名。
///
/// **表頭那一列才是權威，不要照頁面 JS 裡的 `columnNameAry1` 對欄。**
/// 那個陣列是「欄位篩選選單」的全部選項（12 欄，含期中評量、期末扣考…），
/// 而實際 render 出來只有 9 欄。照它去對，「學期總成績」會落在一個不存在的
/// 位置上，解出空字串 —— 畫面上就是每一門課都沒有成績。
const _colTerm = '學年期';
const _colCode = '課號';
const _colClassNo = '開課班別';
const _colCredits = '學分數';
const _colKind = '選別';
const _colName = '課程名稱';
const _colTeacher = '教師姓名';
const _colScore = '學期總成績';

/// 解析成績單。
GradeReport parseGrades(String html) {
  final grid = parseDataGrid(html);
  final doc = html_parser.parse(html);

  final totals = <String, String>{};
  for (final label in _totalLabels) {
    final v = labelledText(doc, label);
    if (v.isNotEmpty) totals[label] = v;
  }

  final courses = <CourseGrade>[];
  for (final r in grid.records) {
    // 課程名稱是這一列的主角 —— 沒有它就不是一門課（合計列之類）。
    final name = clean(r[_colName] ?? '');
    if (name.isEmpty) continue;

    courses.add(CourseGrade(
      term: clean(r[_colTerm] ?? ''),
      name: name,
      code: clean(r[_colCode] ?? ''),
      classNo: clean(r[_colClassNo] ?? ''),
      kind: clean(r[_colKind] ?? ''),
      teacher: clean(r[_colTeacher] ?? ''),
      credits: int.tryParse(clean(r[_colCredits] ?? '')),
      mark: parseGradeMark(r[_colScore] ?? ''),
    ));
  }

  return GradeReport(courses: courses, totals: totals);
}

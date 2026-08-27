import 'package:html/parser.dart' as html_parser;

import 'data_grid.dart' show findDataGrid;
import 'html_text.dart';

/// 必修科目表裡的一列。
class RequiredCourse {
  const RequiredCourse({
    required this.category,
    required this.name,
    this.codes = const [],
    this.credits = 0,
    this.byTerm = const {},
    this.note = '',
  });

  /// 「共同教育課程」或「系訂專業必修」。
  ///
  /// 表格用 `rowspan` 把它跨在好幾列上，只有該類別的**第一列**有這一格，
  /// 後面的列要自己接下去 —— 不接的話那些科目會變成沒有類別。
  final String category;

  /// 科目名稱。課號已經拆掉了（頁面上是 `微積分B5711M97、B5721M97` 黏在一起）。
  final String name;

  /// 課號，可能好幾個（上下學期各一個），也可能一個都沒有。
  ///
  /// **沒有課號的是「類別型」要求**：`12-國文領域`、`11-博雅課程`
  /// 這種是「這個領域修滿幾學分即可」，不是指定某一門課。
  /// 兩者對「還缺什麼」的意義完全不同，不能混在一起算。
  final List<String> codes;

  final double credits;

  /// 建議修課學期 -> 那一格的原文。
  ///
  /// key 是 **0 = 一上、1 = 一下、2 = 二上**…一路到 9 = 五下。
  /// 值保留原文而不是轉成數字，因為博雅課程那種會寫 `2,2`（兩門各兩學分）。
  final Map<int, String> byTerm;

  final String note;

  /// 指定了某一門課，而不是「這個領域修滿學分就好」。
  bool get isSpecificCourse => codes.isNotEmpty;
}

/// 一整份必修科目表。
class RequiredCourses {
  const RequiredCourses({
    this.courses = const [],
    this.categoryTotals = const {},
    this.requiredCredits,
    this.electiveMinimum,
    this.graduationMinimum,
    this.notes = const [],
  });

  final List<RequiredCourse> courses;

  /// 各類別的學分小計（「共同教育課程」-> 28）。
  final Map<String, double> categoryTotals;

  /// 必修總學分數。
  final double? requiredCredits;

  /// 選修最低學分數。
  final double? electiveMinimum;

  /// 畢業最低學分數。**這是畢業審核真正的門檻。**
  final double? graduationMinimum;

  /// 表格最後那幾條說明（選修規定、軍訓體育不計入…）。照原文保留，
  /// 那些是規則，改寫或摘要都可能失真。
  final List<String> notes;

  bool get isEmpty => courses.isEmpty;
}

/// 解析「查詢必修科目表」（`ENRA120_01.aspx`）的查詢結果。
///
/// 表格長這樣（真實資料見
/// `spike/fixtures/…ENRA120_01__QUERY_BTN1_115_1_0_0507_01.html`）：
/// ```
/// 科目類別 | 科目名稱 | 學分數 | 跨領域數 | 第一學年 … 第五學年 | 備註
///                                          上 下 上 下 …
/// 共同教育課程 | 12-國文領域          | 4 | 不限 | 2 2 … | 修足學分即可
///              | 計算機概論B57011RQ   | 3 | 不限 | 3 …   |
/// 共同教育課程學分小計 | 28 | …
/// …
/// 必修總學分數   | 78
/// 選修最低學分數 | 57
/// 畢業最低學分數 | 135
/// ```
///
/// 靠**格數**分辨列的種類，不是靠內容猜：
///   - 15 格：這一類別的第一列（多出來的那格是 `rowspan` 的類別名）
///   - 14 格：同一類別的後續科目，或是小計
///   -  2 格：最後的總結（必修/選修/畢業學分、備註）
RequiredCourses parseRequiredCourses(String html) {
  final doc = html_parser.parse(html);
  final table = findDataGrid(doc);
  if (table == null) return const RequiredCourses();

  final courses = <RequiredCourse>[];
  final totals = <String, double>{};
  final notes = <String>[];
  double? required;
  double? elective;
  double? graduation;

  var category = '';

  for (final tr in table.querySelectorAll('tr')) {
    final cells = tr.querySelectorAll('td, th');
    final text = [for (final c in cells) clean(c.text)];

    // 兩列表頭（第二列是「上 下 上 下…」）
    if (text.length == 10) continue;

    if (text.length == 2) {
      final value = _toDouble(text[1]);
      switch (text[0]) {
        case '必修總學分數':
          required = value;
        case '選修最低學分數':
          elective = value;
        case '畢業最低學分數':
          graduation = value;
        default:
          if (text[1].isNotEmpty) notes.add('${text[0]}：${text[1]}');
      }
      continue;
    }

    if (text.length < 14) continue;

    // 15 格 = 這一格是新的類別名（rowspan 的起點）
    var i = 0;
    if (text.length >= 15) {
      category = text[0];
      i = 1;
    }

    final label = text[i];

    // 小計和總計不是科目，但學分數要留著
    if (label.contains('小計') || label.contains('總學分')) {
      totals[label] = _toDouble(text[i + 1]) ?? 0;
      continue;
    }

    final codes = _codeRe.allMatches(label).map((m) => m.group(0)!).toList();
    courses.add(RequiredCourse(
      category: category,
      name: _stripCodes(label, codes),
      codes: codes,
      credits: _toDouble(text[i + 1]) ?? 0,
      byTerm: {
        for (var t = 0; t < 10; t++)
          if (i + 3 + t < text.length && text[i + 3 + t].isNotEmpty)
            t: text[i + 3 + t],
      },
      note: i + 13 < text.length ? text[i + 13] : '',
    ));
  }

  return RequiredCourses(
    courses: courses,
    categoryTotals: totals,
    requiredCredits: required,
    electiveMinimum: elective,
    graduationMinimum: graduation,
    notes: notes,
  );
}

/// 課號：一個英文字母加七碼英數（`B57011RQ`、`B5711M97`）。
///
/// 頁面上課號是**直接黏在課名後面**的，中間沒有分隔（`計算機概論B57011RQ`）。
/// 一門課上下學期各一個課號時用「、」隔開。
final RegExp _codeRe = RegExp(r'[A-Z][0-9A-Z]{7}');

String _stripCodes(String label, List<String> codes) {
  var out = label;
  for (final c in codes) {
    out = out.replaceAll(c, '');
  }
  // 拿掉課號之後會留下夾在中間的頓號
  return out.replaceAll(RegExp(r'[、,]+$'), '').replaceAll('、、', '').trim();
}

double? _toDouble(String s) => double.tryParse(clean(s));

/// 這一列的第幾個學期 —— 0 = 一上、1 = 一下、2 = 二上…9 = 五下。
///
/// 抽成函式是為了讓 UI 顯示時不用自己算「第幾學年第幾學期」。
String termLabel(int index) {
  const years = ['一', '二', '三', '四', '五'];
  final year = years[(index ~/ 2).clamp(0, 4)];
  return '$year${index.isEven ? '上' : '下'}';
}

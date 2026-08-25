import 'package:html/dom.dart' as dom;

import '../parsing/html_text.dart';
import 'forms.dart';
import 'page.dart';

/// 一個查詢欄位長什麼樣。
enum FieldKind { select, text, number, date, hidden }

class SchemaField {
  const SchemaField({
    required this.name,
    required this.label,
    required this.kind,
    this.value = '',
    this.options = const [],
    this.maxLength,
  });

  final String name;

  /// 中文標籤。**從頁面上的 `CNAME` 屬性讀來的**，不是我們翻譯的 ——
  /// 學校改欄位名的時候，標籤會自己跟著改。
  final String label;

  final FieldKind kind;
  final String value;
  final List<SelectOption> options;
  final int? maxLength;

  /// 沒有任何選項的下拉。
  ///
  /// **這種欄位不能送。** 瀏覽器完全不送它，我們送空字串的話 ASP.NET 的
  /// event validation 會判定「這個值不是我渲染出來的」而拋例外 ——
  /// 表面上只是一句通用的 403，完全看不出是哪個欄位害的。
  ///
  /// 實際案例：教師查詢的 `Q_LECTR_TCH_CH` 初始 0 個選項，
  /// 要先選系所觸發連動 postback 才會填入。
  bool get needsCascade => kind == FieldKind.select && options.isEmpty;
}

/// 一顆送出按鈕。
class SchemaButton {
  const SchemaButton({
    required this.name,
    required this.label,
    this.value = '',
    this.isPrint = false,
  });

  final String name;

  /// 中文標籤，從按鈕的 `ml` 屬性讀來（`CB_查詢` -> `查詢`）。
  final String label;
  final String value;

  /// 列印／報表類的按鈕。這些多半掛在 Crystal Reports 上，
  /// 輸出不一定是 HTML，所以 UI 要另外處理而不是當成查詢結果。
  final bool isPrint;
}

/// 一組查詢條件。
///
/// 有些功能頁是分頁式的（jQuery UI tabs）：同一頁擺了好幾套互不相干的查詢條件，
/// 每套自己一顆送出鈕。**攤平成一張表單是不能用的** ——
/// 課程課表查詢有六組，攤平之後畫面上會出現六顆都叫「查詢」的按鈕，
/// 而且十幾個欄位混在一起，使用者不知道哪個配哪個。
class SchemaGroup {
  const SchemaGroup({
    required this.label,
    required this.index,
    required this.fields,
    required this.buttons,
  });

  /// 標籤名稱，例如「單位查詢」。沒有分頁的頁面是空字串。
  final String label;

  /// jQuery UI 的 **0-based** 索引，送出時要放進 `hdnSelectedTab` ——
  /// 伺服器靠它決定要用哪一組條件。
  ///
  /// 頁面上的容器 id 是 `tabs-1` 起跳（1-based），這裡存的是減一之後的值，
  /// 因為 `tabs_init()` 寫進去的是 `$('#tabs').tabs('option', 'active')`。
  final int index;

  final List<SchemaField> fields;
  final List<SchemaButton> buttons;

  List<SchemaField> get visibleFields =>
      fields.where((f) => f.kind != FieldKind.hidden).toList();

  List<SchemaButton> get queryButtons =>
      buttons.where((b) => !b.isPrint).toList();
}

/// 從一頁 WebForms 功能頁讀出來的「這一頁能做什麼」。
///
/// **這是「全部原生」能成立的關鍵。** 這個系統的 50 個功能頁都是同一套產生器
/// 做出來的，而且每個欄位都帶著中文名（`CNAME`）、每顆按鈕都帶著中文標籤（`ml`）、
/// 頁面標題帶著功能名稱。所以不需要為每一頁寫一個 parser ——
/// 讀頁面自己的宣告，就能畫出正確的中文表單。
///
/// 學校改版加一個欄位，這裡自動就多一個欄位，不用改 App。
class FunctionSchema {
  const FunctionSchema({
    required this.title,
    required this.fields,
    required this.buttons,
    required this.groups,
  });

  /// 功能名稱，從 `<title>` 讀來。
  ///
  /// **可能是空的。** 格式通常是 `TKE2211_課程課表查詢`，但不是每一頁都有填 ——
  /// 個人課表那頁的 title 就只有 `TKE2240_`，底線後面什麼都沒有。
  ///
  /// 所以 UI 不能只靠這個：選單（`menu_tree.json`）本來就有每個功能的中文名，
  /// 那個才是可靠來源。這裡拿到的只是「頁面自己說它是什麼」，有就用來對照。
  final String title;

  final List<SchemaField> fields;
  final List<SchemaButton> buttons;

  /// 依標籤頁分好的組。沒有分頁的頁面只有一組（label 是空字串）。
  final List<SchemaGroup> groups;

  bool get isTabbed => groups.length > 1;

  /// 使用者要填的欄位（隱藏的不算）。
  List<SchemaField> get visibleFields =>
      fields.where((f) => f.kind != FieldKind.hidden).toList();

  /// 查詢按鈕（排掉列印和清除）。
  List<SchemaButton> get queryButtons =>
      buttons.where((b) => !b.isPrint).toList();

  static FunctionSchema fromPage(AisPage page) => fromDocument(page.doc);

  static FunctionSchema fromDocument(dom.Document doc) {
    final rawTitle = clean(doc.querySelector('title')?.text ?? '');
    // `TKE2211_課程課表查詢` -> `課程課表查詢`。
    // 底線後面是空的（`TKE2240_`）就回空字串，不要把功能代碼當成名字顯示給使用者。
    final underscore = rawTitle.indexOf('_');
    final title =
        underscore >= 0 ? rawTitle.substring(underscore + 1).trim() : rawTitle;

    final forms = doc.querySelectorAll('form');
    final scope = forms.isEmpty ? doc.documentElement! : forms.first;

    final labels = _visibleLabels(scope);

    final fields = <SchemaField>[];
    for (final el in scope.querySelectorAll('select')) {
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;
      if (_isInternal(name)) continue;
      final label = _labelOf(el, labels);
      if (label == null) continue;
      fields.add(SchemaField(
        name: name,
        label: label,
        kind: FieldKind.select,
        value: selectedOption(doc, name) ?? '',
        options: selectOptions(doc, name),
      ));
    }

    for (final el in scope.querySelectorAll('input')) {
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = (el.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'submit' || type == 'button' || type == 'image' ||
          type == 'reset' || type == 'hidden') {
        continue;
      }
      if (_isInternal(name)) continue;
      final label = _labelOf(el, labels);
      if (label == null) continue;
      fields.add(SchemaField(
        name: name,
        label: label,
        kind: type == 'number' ? FieldKind.number : FieldKind.text,
        value: el.attributes['value'] ?? '',
        maxLength: int.tryParse(el.attributes['maxlength'] ?? ''),
      ));
    }

    final buttons = <SchemaButton>[];
    for (final el in scope.querySelectorAll('input')) {
      final type = (el.attributes['type'] ?? '').toLowerCase();
      if (type != 'submit') continue;
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;

      final label = _buttonLabel(el);
      if (label == null) continue;
      // 「清除／還原」只是把表單清空的前端動作，不是查詢
      if (label.contains('清除') || label.contains('還原')) continue;

      buttons.add(SchemaButton(
        name: name,
        label: label,
        value: el.attributes['value'] ?? '',
        isPrint: label.contains('列印') || label.contains('報表'),
      ));
    }

    return FunctionSchema(
      title: title,
      fields: fields,
      buttons: buttons,
      groups: _group(doc, fields, buttons),
    );
  }

  /// `tabs-3` -> 2。往上找最近的分頁容器，找不到就回 null。
  static int? _tabIndexOf(dom.Element el) {
    for (dom.Element? node = el; node != null; node = node.parent) {
      final id = node.attributes['id'];
      if (id == null) continue;
      final m = _tabIdRe.firstMatch(id);
      if (m != null) return int.parse(m.group(1)!) - 1;
    }
    return null;
  }

  /// 把欄位和按鈕分到各自的標籤頁底下。
  ///
  /// 分組依據是 DOM 的祖先容器（`<div id="tabs-N">`），標籤文字來自標籤列的
  /// `<a href="#tabs-N">單位查詢</a>` —— 兩邊都是頁面自己宣告的，
  /// 所以學校多加一個標籤頁，App 自動就多一個。
  static List<SchemaGroup> _group(
    dom.Document doc,
    List<SchemaField> fields,
    List<SchemaButton> buttons,
  ) {
    final labels = <int, String>{};
    for (final a in doc.querySelectorAll('a')) {
      final m = _tabHrefRe.firstMatch(a.attributes['href'] ?? '');
      final text = clean(a.text);
      if (m != null && text.isNotEmpty) {
        labels[int.parse(m.group(1)!) - 1] = text;
      }
    }
    if (labels.isEmpty) {
      return [
        SchemaGroup(label: '', index: 0, fields: fields, buttons: buttons),
      ];
    }

    int? tabOf(String name) {
      final el = doc.querySelector('[name="$name"]');
      return el == null ? null : _tabIndexOf(el);
    }

    final byTab = <int, List<SchemaField>>{};
    final btnByTab = <int, List<SchemaButton>>{};
    final looseFields = <SchemaField>[];
    final looseButtons = <SchemaButton>[];

    for (final f in fields) {
      final i = tabOf(f.name);
      if (i == null) {
        looseFields.add(f);
      } else {
        (byTab[i] ??= []).add(f);
      }
    }
    for (final b in buttons) {
      final i = tabOf(b.name);
      if (i == null) {
        looseButtons.add(b);
      } else {
        (btnByTab[i] ??= []).add(b);
      }
    }

    final indexes = labels.keys.toList()..sort();
    return [
      for (final i in indexes)
        SchemaGroup(
          label: labels[i]!,
          index: i,
          // 不屬於任何分頁的欄位（例如共用的學年學期）每一組都要看得到，
          // 不然使用者切到第二個標籤頁就找不到它了。
          fields: [...looseFields, ...?byTab[i]],
          buttons: [...?btnByTab[i], ...looseButtons],
        ),
    ];
  }

  static final RegExp _tabIdRe = RegExp(r'^tabs-(\d+)$');
  static final RegExp _tabHrefRe = RegExp(r'^#tabs-(\d+)$');

  /// 欄位的中文名。
  ///
  /// 兩個來源，都是頁面自己宣告的：
  ///   1. 欄位上的 `CNAME` 屬性 —— 大部分欄位有
  ///   2. 前面那個 `<span ml="PL_節次">節次</span>` —— 畫面上真正顯示的標籤
  ///
  /// 需要第二個來源是因為**學校並沒有每個欄位都填 `CNAME`**：
  /// 課程查詢的節次（`Q_CLASS`）就沒有。只認 `CNAME` 的話，那一格會整個消失，
  /// 而使用者只會覺得「時間查詢只能選星期，不能選節次」。
  static String? _labelOf(dom.Element el, Map<String, String> fallback) {
    final cname = el.attributes['cname'] ?? el.attributes['CNAME'];
    final label = cname == null ? '' : clean(cname);
    if (label.isNotEmpty) return label;

    final name = el.attributes['name'];
    return name == null ? null : fallback[name];
  }

  /// 掃一遍文件，把每個欄位對到它前面最近的可見標籤。
  ///
  /// 版面是 Bootstrap 的兩欄格線：標籤一個 div、欄位一個 div，
  /// 所以「前面最近的 `PL_` 標籤」就是這一格的名字。
  static Map<String, String> _visibleLabels(dom.Element scope) {
    final out = <String, String>{};
    String? pending;
    for (final el in scope.querySelectorAll('*')) {
      final ml = el.attributes['ml'] ?? el.attributes['ML'];
      if (ml != null && ml.startsWith('PL_')) {
        final text = clean(el.text);
        if (text.isNotEmpty) pending = text;
        continue;
      }
      final tag = el.localName;
      if (tag == 'select' || tag == 'input' || tag == 'textarea') {
        final name = el.attributes['name'];
        if (name != null && name.isNotEmpty && pending != null) {
          out.putIfAbsent(name, () => pending!);
          pending = null;
        }
      }
    }
    return out;
  }

  /// 頁面自己的狀態控制項，不是給使用者填的。
  static bool _isInternal(String name) =>
      name.startsWith('PC\$') ||
      name.startsWith('PC2\$') ||
      name.startsWith('hdn') ||
      name.startsWith('__');

  /// 按鈕標籤：優先用 `ml`（`CB_查詢` -> `查詢`），退而求其次用 `value`。
  static String? _buttonLabel(dom.Element el) {
    final ml = el.attributes['ml'] ?? el.attributes['ML'];
    if (ml != null && ml.isNotEmpty) {
      final stripped = clean(ml).replaceFirst(RegExp(r'^CB_'), '');
      if (stripped.isNotEmpty) return stripped;
    }
    final value = clean(el.attributes['value'] ?? '');
    return value.isEmpty ? null : value;
  }
}

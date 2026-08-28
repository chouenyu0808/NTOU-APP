import 'package:html/dom.dart' as dom;

import '../parsing/html_text.dart';
import 'forms.dart';
import 'page.dart';

/// 一個查詢欄位長什麼樣。
///
/// 這個系統的表單不是只有下拉和文字框。維護新生資料那一頁上就有 2 個
/// `<textarea>`（自傳 2000 字）、9 個 radio、37 個 checkbox ——
/// 只認得 select / text 的話，那一頁 151 個欄位全部會被畫成文字框或整個消失。
enum FieldKind {
  select,
  text,
  number,
  date,
  hidden,

  /// `<textarea>`。自傳、備註那一類，要多行。
  textarea,

  /// 一組 `<input type="radio">`，同名的算一組。單選。
  radio,

  /// 一組 `<input type="checkbox">`（ASP.NET 的 CheckBoxList，
  /// 名字是 `群組$0`、`群組$1`…）。複選。
  checkboxes,

  /// `<input type="password">`。畫面上要遮起來。
  password,

  /// `<input type="file">`。**App 還不能上傳檔案** ——
  /// 畫成文字框的話使用者會在裡面打字，然後送出一個伺服器看不懂的值。
  file,
}

class SchemaField {
  const SchemaField({
    required this.name,
    required this.label,
    required this.kind,
    this.value = '',
    this.options = const [],
    this.maxLength,
    this.readOnly = false,
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

  /// 學校那邊標成 `disabled` 的欄位（自己的性別、學生類別那一類）。
  ///
  /// **瀏覽器完全不送 disabled 的欄位。** 我們照樣送的話，輕則被
  /// event validation 擋成一句看不懂的 403，重則真的把一個使用者
  /// 根本不該改的欄位寫進去。畫面上要顯示（那是他的資料）但不能編輯。
  final bool readOnly;

  /// 複選群組裡選中的那幾個 —— 存的是各自的欄位名（`M_PRESENT_TYPE\$0`）。
  ///
  /// 用換行分隔而不是逗號：ASP.NET 的欄位名裡有 `\$`，但不會有換行。
  static const String checkedSeparator = '\n';

  static List<String> splitChecked(String value) =>
      value.isEmpty ? const [] : value.split(checkedSeparator);

  static String joinChecked(Iterable<String> names) =>
      names.join(checkedSeparator);
}

/// 一顆送出按鈕。
class SchemaButton {
  const SchemaButton({
    required this.name,
    required this.label,
    this.value = '',
    this.action = '',
    this.isPrint = false,
  });

  final String name;

  /// 中文標籤，從按鈕的 `ml` 屬性讀來（`CB_查詢` -> `查詢`）。
  final String label;
  final String value;

  /// 這顆按鈕的 `onclick`。
  ///
  /// 用來分辨「同一個動作放了兩次」和「兩個看起來一樣的不同動作」：
  ///   - 維護新生資料的 `SAVE_BTN1` / `SAVE_BTN2` 都是「存檔」，`onclick`
  ///     也都是 `return doSave();` —— 長表單上下各放一顆，同一個動作。
  ///   - 課程課表查詢的六顆「查詢」看起來一樣，但 `onclick` 分別是
  ///     `doQuery('1')`…`doQuery('6')` —— 是六個不同的查詢，一顆都不能少。
  ///
  /// 只看標籤分不出這兩種情況。
  final String action;

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

    final fields = _collectFields(doc, scope, labels);

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
        action: clean(el.attributes['onclick'] ?? ''),
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

  /// 掃出這一頁使用者要填的欄位，**照文件順序**。
  ///
  /// 原本是先掃完所有 `<select>` 再掃所有 `<input>`，畫面上的順序就跟學校那一頁
  /// 對不起來 —— 使用者照著網頁的記憶去找某一格會找錯位置。一次走完整棵樹
  /// 順便解決那件事。
  ///
  /// 認得的控制項（以前只有 select 和 text）：
  ///   - `<textarea>` —— **以前整個不存在**。維護新生資料的「自傳」（2000 字）
  ///     和「兄弟姐妹備註」都是 textarea，畫面上找不到那兩格。
  ///   - 一組同名的 `<input type="radio">` 收成一個單選欄位。以前是一個 radio
  ///     一個文字框：「自我認同性別」在畫面上是**三個一模一樣的文字框**。
  ///   - ASP.NET 的 CheckBoxList（`群組$0`、`群組$1`…）收成一個複選欄位。
  ///     以前「目前身分」那 37 個 checkbox 是一個文字框。
  ///   - `type="password"` 要遮起來（修改密碼那一頁）。
  ///   - `type="file"` 標成不支援 —— 畫成文字框的話使用者會在裡面打字。
  static List<SchemaField> _collectFields(
    dom.Document doc,
    dom.Element scope,
    Map<String, String> labels,
  ) {
    final fields = <SchemaField>[];
    final done = <String>{};

    for (final el in scope.querySelectorAll('*')) {
      final tag = el.localName;
      final name = el.attributes['name'];

      if (tag == 'select') {
        if (name == null || name.isEmpty || _isInternal(name)) continue;
        if (!done.add(name)) continue;
        final label = _labelOf(el, labels);
        if (label == null) continue;
        fields.add(SchemaField(
          name: name,
          label: label,
          kind: FieldKind.select,
          value: selectedOption(doc, name) ?? '',
          options: selectOptions(doc, name),
          readOnly: _isDisabled(el),
        ));
        continue;
      }

      if (tag == 'textarea') {
        if (name == null || name.isEmpty || _isInternal(name)) continue;
        if (!done.add(name)) continue;
        final label = _labelOf(el, labels);
        if (label == null) continue;
        fields.add(SchemaField(
          name: name,
          label: label,
          kind: FieldKind.textarea,
          // `<textarea>` 的值是它的內容，不是 value 屬性。
          value: el.text,
          maxLength: int.tryParse(el.attributes['maxlength'] ?? ''),
          readOnly: _isDisabled(el),
        ));
        continue;
      }

      if (tag != 'input') continue;
      if (name == null || name.isEmpty) continue;
      final type = (el.attributes['type'] ?? 'text').toLowerCase();
      if (type == 'submit' ||
          type == 'button' ||
          type == 'image' ||
          type == 'reset' ||
          type == 'hidden') {
        continue;
      }

      if (type == 'radio') {
        // 同名的 radio 是**一組**，不是好幾個欄位。
        if (_isInternal(name) || !done.add(name)) continue;
        final group = [
          for (final r in scope.querySelectorAll('input'))
            if ((r.attributes['type'] ?? '').toLowerCase() == 'radio' &&
                r.attributes['name'] == name)
              r,
        ];
        final label = _groupLabel(scope, name, name, labels);
        if (label == null) continue;
        final checked =
            group.where((r) => r.attributes.containsKey('checked')).firstOrNull;
        fields.add(SchemaField(
          name: name,
          label: label,
          kind: FieldKind.radio,
          value: checked?.attributes['value'] ?? '',
          options: [
            for (final r in group)
              (value: r.attributes['value'] ?? '', label: _optionLabel(scope, r)),
          ],
          // 一組裡有一顆是 disabled，整組就是唯讀（學校是整組一起關的）。
          readOnly: group.any(_isDisabled),
        ));
        continue;
      }

      if (type == 'checkbox') {
        // `M_PRESENT_TYPE$0` -> 群組 `M_PRESENT_TYPE`。沒有編號的就是自己一組。
        final groupName = _checkboxGroup(name);
        if (_isInternal(groupName) || !done.add(groupName)) continue;
        final group = [
          for (final c in scope.querySelectorAll('input'))
            if ((c.attributes['type'] ?? '').toLowerCase() == 'checkbox' &&
                _checkboxGroup(c.attributes['name'] ?? '') == groupName)
              c,
        ];
        final label = _groupLabel(scope, groupName, name, labels);
        if (label == null) continue;
        fields.add(SchemaField(
          // 群組本身不是表單欄位名 —— 送出時要展開成各自的 `群組$N`，
          // 見 [AisRepository.sendableValues]。
          name: groupName,
          label: label,
          kind: FieldKind.checkboxes,
          value: SchemaField.joinChecked([
            for (final c in group)
              if (c.attributes.containsKey('checked'))
                c.attributes['name'] ?? '',
          ]),
          options: [
            for (final c in group)
              (
                value: c.attributes['name'] ?? '',
                label: _optionLabel(scope, c),
              ),
          ],
          readOnly: group.any(_isDisabled),
        ));
        continue;
      }

      if (_isInternal(name) || !done.add(name)) continue;
      final label = _labelOf(el, labels);
      if (label == null) continue;
      fields.add(SchemaField(
        name: name,
        label: label,
        kind: switch (type) {
          'number' => FieldKind.number,
          'password' => FieldKind.password,
          'file' => FieldKind.file,
          _ => FieldKind.text,
        },
        value: el.attributes['value'] ?? '',
        maxLength: int.tryParse(el.attributes['maxlength'] ?? ''),
        readOnly: _isDisabled(el),
      ));
    }

    return fields;
  }

  /// `M_PRESENT_TYPE$3` -> `M_PRESENT_TYPE`。
  static String _checkboxGroup(String name) {
    final i = name.lastIndexOf(r'$');
    if (i <= 0) return name;
    // 只有後面全是數字才算 CheckBoxList 的編號 —— 學校的欄位名裡
    // `$` 也可能是控制項階層（`PC$PageSize`），那不是同一回事。
    final suffix = name.substring(i + 1);
    if (suffix.isEmpty || int.tryParse(suffix) == null) return name;
    return name.substring(0, i);
  }

  /// radio / checkbox 每一顆自己的說明文字（`<label for="...">Male(男)</label>`）。
  static String _optionLabel(dom.Element scope, dom.Element input) {
    final id = input.attributes['id'];
    if (id != null && id.isNotEmpty) {
      for (final l in scope.querySelectorAll('label')) {
        if (l.attributes['for'] == id) {
          final text = clean(l.text);
          if (text.isNotEmpty) return text;
        }
      }
    }
    // 沒有 label 就退回值本身 —— 至少看得出兩個選項不一樣。
    return input.attributes['value'] ?? '';
  }

  /// 一組 radio / checkbox 的標題。
  ///
  /// ASP.NET 把 `CNAME` 放在**包住整組的那個 `<span id="群組名">`** 上，
  /// 不是每一顆 input 上（見 `spike/fixtures/…ENR3030_01.html`）。
  /// 只找 input 的話這一組會沒有名字，整組被丟掉。
  static String? _groupLabel(
    dom.Element scope,
    String groupName,
    String firstFieldName,
    Map<String, String> labels,
  ) {
    for (final el in scope.querySelectorAll('[id="$groupName"]')) {
      final cname = el.attributes['cname'] ?? el.attributes['CNAME'];
      if (cname != null && clean(cname).isNotEmpty) return clean(cname);
    }
    return labels[firstFieldName] ?? labels[groupName];
  }

  /// 這個欄位是不是被關掉了。
  ///
  /// **要往上找**：學校是把 `disabled` 放在包住整組的 `<span>` 上，
  /// 個別的 input 有時候有、有時候沒有。
  static bool _isDisabled(dom.Element el) {
    for (dom.Element? n = el; n != null; n = n.parent) {
      if (n.attributes.containsKey('disabled')) return true;
      if (n.localName == 'form') break;
    }
    return false;
  }

  /// 同一組裡重複的按鈕只留一顆。
  ///
  /// 這個系統的長表單會**把同一顆送出鈕放在最上面和最下面各一次**。
  /// 維護新生資料的 `SAVE_BTN1` 和 `SAVE_BTN2` 標籤都是「存檔」，
  /// `onclick` 也都是 `return doSave();` —— 同一個動作，只是排版方便。
  ///
  /// 我們的畫面只有一份表單、按鈕集中在一起，兩顆一模一樣的「存檔」對使用者
  /// 只是雜訊；而那一頁會真的寫學籍資料，看不出差別更糟。
  ///
  /// **標籤和動作都一樣才算重複。** 課程課表查詢那六顆「查詢」標籤一樣，
  /// 但 `onclick` 分別是 `doQuery('1')`…`doQuery('6')`，是六個不同的查詢，
  /// 一顆都不能少。「刪除選取」「暫存」也是各自不同的動作。
  ///
  /// **只在同一組裡比對** —— 每個標籤頁都有自己的存檔鈕，跨組去重會把
  /// 第二頁之後的存檔全部吃掉。
  static List<SchemaButton> _dedupe(List<SchemaButton> buttons) {
    // 用 record 做鍵：不用拼字串，也就沒有「分隔符剛好出現在標籤裡」的問題。
    final seen = <(String, String)>{};
    return [
      for (final b in buttons)
        if (seen.add((b.label, b.action))) b,
    ];
  }

  /// `tabs-3` -> 2。往上找最近的分頁容器，找不到就回 null。
  static int? _tabIndexOf(dom.Element el) {
    for (dom.Element? node = el; node != null; node = node.parent) {
      final id = node.attributes['id'];
      if (id == null) continue;
      final m = _tabIdRe.firstMatch(id) ?? _tabCntRe.firstMatch(id);
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
    // 第二種分頁。維護新生資料（`ENR3030`）沒有 `#tabs-N` 錨點，改用一排
    //     <input type="button" id="TabBtn1" ml="CB_基本資料">
    // 當標籤，內容放在 `<div id="TabCnt1">`（非作用中的是 `display: none`）。
    //
    // **不認得它的代價很具體**：那一頁有 8 組條件、16 顆按鈕，攤平之後畫面上
    // 出現 14 顆一模一樣的「存檔」，而使用者實際看得見的只有 3 顆。
    // 那還是一頁會真的寫學籍資料的表單。
    if (labels.isEmpty) {
      for (final el in doc.querySelectorAll('input')) {
        final id = el.attributes['id'] ?? el.attributes['name'] ?? '';
        final m = _tabBtnRe.firstMatch(id);
        if (m == null) continue;
        final label = _buttonLabel(el);
        if (label != null && label.isNotEmpty) {
          labels[int.parse(m.group(1)!) - 1] = label;
        }
      }
    }

    if (labels.isEmpty) {
      return [
        SchemaGroup(
          label: '',
          index: 0,
          fields: fields,
          buttons: _dedupe(buttons),
        ),
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
          // 每組各自判斷重名 —— 分頁式的頁面每組通常只剩一顆「查詢」，
          // 不能因為整頁有 6 顆同名就被加上編號。
          buttons: _dedupe([...?btnByTab[i], ...looseButtons]),
        ),
    ];
  }

  static final RegExp _tabIdRe = RegExp(r'^tabs-(\d+)$');

  /// 第二種分頁：內容容器 `TabCnt1`、標籤按鈕 `TabBtn1`（都是 1-based）。
  static final RegExp _tabCntRe = RegExp(r'^TabCnt(\d+)$');
  static final RegExp _tabBtnRe = RegExp(r'^TabBtn(\d+)$');
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
  ///
  /// 前綴不只有 `CB_`。維護新生資料那一頁上就有一顆 `ml="PL_填寫範例說明"`，
  /// 只剝 `CB_` 的話畫面上會直接出現「PL_填寫範例說明」—— 學校內部的欄位命名
  /// 漏到使用者眼前。所以剝掉任何「大寫前綴 + 底線」。
  static final RegExp _mlPrefixRe = RegExp(r'^[A-Z][A-Z0-9]*_');

  static String? _buttonLabel(dom.Element el) {
    final ml = el.attributes['ml'] ?? el.attributes['ML'];
    if (ml != null && ml.isNotEmpty) {
      final stripped = clean(ml).replaceFirst(_mlPrefixRe, '');
      if (stripped.isNotEmpty) return stripped;
    }
    final value = clean(el.attributes['value'] ?? '');
    return value.isEmpty ? null : value;
  }
}

import 'package:html/dom.dart' as dom;

import 'exceptions.dart';

/// WebForms 每次 postback 都要原封不動帶回去的隱藏欄位。
/// 少帶任何一個都可能被丟回登入頁。
const List<String> kHiddenFields = [
  '__VIEWSTATE',
  '__VIEWSTATEGENERATOR',
  '__VIEWSTATEENCRYPTED',
  '__EVENTVALIDATION',
  '__PREVIOUSPAGE',
  '__LASTFOCUS',
];

/// 按鈕 onclick 裡「順手設一個隱藏欄位」的慣例。
///
/// `onclick="return doQuery('1')"` 對應到 JS 裡的
/// `_i(0, "QUERY_TYPE").value = type;` —— 不送這個欄位伺服器直接拋例外，
/// 而且只回一句通用的 403「系統發生錯誤, 請通知系統管理人員」。
///
/// 目前只有這一組，但這個系統很愛這樣寫，之後遇到新的加在這裡就好。
const Map<String, String> kOnclickFieldSetters = {'doQuery': 'QUERY_TYPE'};

/// 抓頁面上的隱藏狀態欄位。每次 postback 後 `__VIEWSTATE` 都會變，一定要重抓。
Map<String, String> scrapeHiddenFields(dom.Document doc) {
  final out = <String, String>{};
  for (final name in kHiddenFields) {
    final el = doc.querySelector('input[name="$name"]');
    final value = el?.attributes['value'];
    if (value != null) out[name] = value;
  }
  return out;
}

/// 把頁面上某個 `<form>` 的所有欄位現值撈出來當 postback 的基底。
///
/// WebForms 很多控制項的狀態靠這些欄位維持，漏帶會出現「怎麼按都沒反應」。
Map<String, String> formFields(dom.Document doc, {int formIndex = 0}) {
  final forms = doc.querySelectorAll('form');
  if (forms.isEmpty) return {};
  final form = forms[formIndex < forms.length ? formIndex : forms.length - 1];

  final out = <String, String>{};

  for (final el in form.querySelectorAll('input')) {
    final name = el.attributes['name'];
    if (name == null || name.isEmpty) continue;
    final type = (el.attributes['type'] ?? 'text').toLowerCase();
    // 這些只在「你按的那顆」才送
    if (type == 'submit' || type == 'button' || type == 'image' || type == 'reset') {
      continue;
    }
    if ((type == 'checkbox' || type == 'radio') &&
        !el.attributes.containsKey('checked')) {
      continue;
    }
    out[name] = el.attributes['value'] ?? '';
  }

  for (final el in form.querySelectorAll('select')) {
    final name = el.attributes['name'];
    if (name == null || name.isEmpty) continue;
    final options = el.querySelectorAll('option');
    dom.Element? chosen;
    for (final o in options) {
      if (o.attributes.containsKey('selected')) {
        chosen = o;
        break;
      }
    }
    chosen ??= options.isNotEmpty ? options.first : null;
    if (chosen == null) {
      // 沒有任何 <option> 的 select，瀏覽器**完全不送這個欄位**。
      // 送空字串的話 event validation 會判定「這個值不是我渲染出來的」而拋例外
      // —— 表面上是一句通用的資料庫錯誤（403），完全看不出是哪個欄位害的。
      continue;
    }
    out[name] = chosen.attributes['value'] ?? chosen.text.trim();
  }

  for (final el in form.querySelectorAll('textarea')) {
    final name = el.attributes['name'];
    if (name != null && name.isNotEmpty) out[name] = el.text;
  }

  return out;
}

/// 從按鈕的 onclick 推出它會順手設哪些隱藏欄位。
Map<String, String> onclickSideEffects(dom.Element? button) {
  if (button == null) return {};
  final onclick = button.attributes['onclick'] ?? '';
  final out = <String, String>{};
  kOnclickFieldSetters.forEach((fn, fieldName) {
    // 函式名用 escape 包起來，之後有人加一個帶點的名字進 kOnclickFieldSetters
    // 也不會變成萬用字元。
    final re = RegExp(RegExp.escape(fn) + r'''\(\s*['"]([^'"]*)['"]\s*\)''');
    final m = re.firstMatch(onclick);
    if (m != null) out[fieldName] = m.group(1)!;
  });
  return out;
}

/// 一個 `<select>` 的選項。
typedef SelectOption = ({String value, String label});

/// 讀某個下拉選單的選項。
///
/// 學年下拉的範圍（105–116）不寫死在 App 裡，每年都要改一次的東西
/// 就該從頁面上讀。使用者選得到什麼，完全跟著學校給的一致。
List<SelectOption> selectOptions(dom.Document doc, String name) {
  final sel = doc.querySelector('select[name="$name"]');
  if (sel == null) return const [];
  return [
    for (final o in sel.querySelectorAll('option'))
      (value: o.attributes['value'] ?? o.text.trim(), label: o.text.trim()),
  ];
}

/// 某個下拉目前選中的值（沒有 selected 就是第一個，跟瀏覽器一樣）。
String? selectedOption(dom.Document doc, String name) {
  final sel = doc.querySelector('select[name="$name"]');
  if (sel == null) return null;
  final options = sel.querySelectorAll('option');
  if (options.isEmpty) return null;
  final chosen = options.firstWhere(
    (o) => o.attributes.containsKey('selected'),
    orElse: () => options.first,
  );
  return chosen.attributes['value'] ?? chosen.text.trim();
}

/// 送出前先確認每個值都是頁面上真的有的選項。
///
/// ASP.NET 的 event validation 會拒絕它沒渲染過的值，但錯誤長成
/// 「系統發生錯誤, 請通知系統管理人員」—— 看不出是哪個欄位、哪個值。
/// 在本機擋下來，錯誤訊息才有用。
void checkValues(dom.Document doc, Map<String, String> values) {
  values.forEach((name, value) {
    final sel = doc.querySelector('select[name="$name"]');
    if (sel == null) return; // 不是下拉就沒得驗，交給伺服器
    final allowed =
        sel.querySelectorAll('option').map((o) => o.attributes['value'] ?? '').toList();
    if (allowed.contains(value)) return;

    // 0 個 option 的下拉是「還沒連動出來」，不是「值填錯了」。
    // 印一句空的「可用的值：」對使用者完全沒有幫助 —— 而且他多半根本沒碰過這一格。
    if (allowed.isEmpty) {
      throw InvalidFieldValue(
        '「$name」這一格還沒有任何選項，要先選它上面的條件才會連動出來。'
        '（這通常是 App 的問題，不是你操作錯了）',
      );
    }

    final preview = allowed.take(12).map((a) => "'$a'").join(', ');
    final more = allowed.length > 12 ? ' …共 ${allowed.length} 個' : '';
    throw InvalidFieldValue(
      '$name=$value 不是這一頁提供的選項（送出去只會得到看不懂的 403）。\n'
      '可用的值：$preview$more',
    );
  });
}

/// WebForms 頁面上「標籤欄 → 值欄」的配對。
///
/// 學校的表單頁版面是 bootstrap 的 row/col：一個標籤欄配一個值欄，
///
/// ```html
/// <div class="col-…"><span ml="PL_歷年累計學分">歷年累計學分</span></div>
/// <div class="col-…"><span id="M_CRD" …>40</span></div>
/// ```
///
/// **靠中文標籤去對值，不要寫死 id。** `M_CRD`、`M_BBS_SUBJ` 這些 id 學校
/// 換掉是常事，而「歷年累計學分」那幾個字是印給人看的 —— 換掉會被使用者罵，
/// 所以它反而是這一頁上最穩的東西。
///
/// 公告內頁（`BBS3010_02`）和成績單（`GRD5010_02`）用的是同一種版面。
library;

import 'package:html/dom.dart' as dom;

import 'html_text.dart';

/// 標籤是 [label] 的那一欄，它的**值欄元素**；找不到回 null。
///
/// 回元素而不是字串，呼叫端才分得出要不要保留 `<br>` 的換行。
dom.Element? labelledValue(dom.Document doc, String label) {
  for (final lbl in doc.querySelectorAll('[ml]')) {
    if (clean(lbl.text) != label) continue;
    final val = _nextColSibling(_colAncestor(lbl));
    if (val != null) return val;
  }
  return null;
}

/// 標籤是 [label] 的那一欄的值，壓過空白；找不到或空的都回空字串。
String labelledText(dom.Document doc, String label) =>
    clean(labelledValue(doc, label)?.text ?? '');

/// 標籤所在的那個 `col-*` 欄。
dom.Element? _colAncestor(dom.Element el) {
  dom.Element? node = el;
  while (node != null) {
    final cls = node.className;
    if (cls.split(RegExp(r'\s+')).any((c) => c.startsWith('col-'))) return node;
    node = node.parent;
  }
  return null;
}

/// 同一列裡標籤欄後面的下一個 `col-*`（值欄）。
dom.Element? _nextColSibling(dom.Element? col) {
  if (col == null) return null;
  var sib = col.nextElementSibling;
  while (sib != null) {
    if (sib.className.contains('col-')) return sib;
    sib = sib.nextElementSibling;
  }
  return null;
}

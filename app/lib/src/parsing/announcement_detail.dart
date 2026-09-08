/// 一則公告的全文（`BBS3010_02`）。
///
/// 首頁的公告只有標題／日期／單位；點開之後這一頁才有內文、承辦人、
/// 登載期間、附件。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_text.dart';

class AnnouncementDetail {
  const AnnouncementDetail({
    required this.subject,
    required this.body,
    this.unit = '',
    this.postingPeriod = '',
    this.handler = '',
    this.contact = '',
    this.documentNo = '',
    this.priority = '',
    this.attachment = '',
  });

  /// 主旨。這是使用者從清單點進來就想確認的那一行。
  final String subject;

  /// 內文。**保留換行** —— 學校用 `<br>` 排段落，全部壓成一行會變成一坨。
  final String body;

  final String unit;

  /// 登載期間，例如「115/09/08~115/10/30」。原樣是民國年，不轉 ——
  /// 這是一段區間文字，不是拿來比大小的，轉了反而失真。
  final String postingPeriod;
  final String handler;
  final String contact;
  final String documentNo;
  final String priority;

  /// 附件說明。沒有附件時學校填「無」—— 那也照實顯示，比空白清楚。
  final String attachment;

  bool get hasBody => body.isNotEmpty;
}

/// 解析 BBS3010_02 的內容頁。
///
/// **靠「標籤 → 值」配對，不寫死 id。** 這一頁的版面是 bootstrap 的
/// row/col：每個欄位是一個標籤欄（`<span ml="PL_主旨">主旨</span>`）配一個
/// 值欄（同一列的下一個 `<div class="col-…">`）。用中文標籤去對值，比認
/// `M_BBS_SUBJ`、`L_BBS_CONTENT` 這些 id 耐改版一點 —— 學校換個 id 是常事，
/// 換掉「主旨」兩個字就會被使用者罵。
AnnouncementDetail parseAnnouncementDetail(String html) {
  final doc = html_parser.parse(html);

  // 值欄：跟標籤同一列、標籤欄後面那個 col。回原始元素，好分辨要不要保留換行。
  dom.Element? valueOf(String label) {
    for (final lbl in doc.querySelectorAll('[ml]')) {
      if (clean(lbl.text) != label) continue;
      final col = _colAncestor(lbl);
      final val = _nextColSibling(col);
      if (val != null) return val;
    }
    return null;
  }

  String textOf(String label) => clean(valueOf(label)?.text ?? '');

  // 內文要保留 <br> 換行。
  final bodyEl = valueOf('內容');

  // 單位不是 row/col 的欄位，是頁面上另外一塊（`#unit_type_title`），
  // 形如「學務處衛生保健組　學校公告」。取全形空白前那一段就是單位。
  final unitRaw = clean(doc.querySelector('#unit_type_title')?.text ?? '');
  final unit = unitRaw.split(' ').first;

  return AnnouncementDetail(
    subject: textOf('主旨'),
    body: bodyEl == null ? '' : _textWithBreaks(bodyEl),
    unit: unit,
    postingPeriod: textOf('登載期間'),
    handler: textOf('承辦人'),
    contact: textOf('聯絡方式'),
    documentNo: textOf('發文字號'),
    priority: textOf('速別'),
    attachment: textOf('附件'),
  );
}

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

/// 把 `<br>` 換成換行、其餘空白照 clean 壓掉，但保留段落之間的斷行。
String _textWithBreaks(dom.Element el) {
  final buf = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buf.write(node.text);
    } else if (node is dom.Element) {
      if (node.localName == 'br') {
        buf.write('\n');
      } else {
        for (final c in node.nodes) {
          walk(c);
        }
      }
    }
  }

  walk(el);
  // 每一行各自壓掉多餘空白，連續空行收成最多一個 —— 學校常常連打好幾個
  // <br>，照搬會在畫面上留一大片空白。
  final lines = buf
      .toString()
      .split('\n')
      .map((l) => l.replaceAll(' ', ' ').replaceAll(RegExp(r'[ \t　]+'), ' ').trim());
  final out = <String>[];
  for (final l in lines) {
    if (l.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(l);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_text.dart';

/// 電子公布欄的一則公告。
class Announcement {
  const Announcement({
    required this.title,
    this.unit = '',
    this.id = '',
    this.date,
  });

  final String title;

  /// 發布單位，例如「學務處住宿輔導組」。
  final String unit;

  /// 公告編號。點開內文要靠它 —— 頁面上是
  /// `onclick="return openBbsAnnouncement('9005901');"`。
  final String id;

  /// 發布日期。**頁面上是民國年**（`115/08/26`），這裡已經轉成西元。
  ///
  /// 可能是 null：解不出來的日期寧可不顯示，也不要猜一個出來 ——
  /// 公告最重要的資訊之一就是「這是什麼時候的事」。
  final DateTime? date;
}

/// 從登入後的入口頁（`Portal.aspx`）讀電子公布欄。
///
/// **不需要額外的請求。** 那一頁是登入握手時本來就會載的四個 frame 之一
/// （見 `AisSession.enterPortal`），公告是順便拿到的。
/// 選單裡雖然有「電子公布欄 > 公告訊息查詢」（`BBS3010`），但首頁只要
/// 最近幾則的話，開那一頁等於多打一次學校的伺服器。
///
/// 頁面結構（真實資料，見 `spike/fixtures/Portal.html`）：
/// ```html
/// <div id="BBS_BLOCK">
///   <div class="msg-list">
///     <a onclick="return openBbsAnnouncement('9005901');">
///       <span><i class="ri-calendar-event-fill"></i>115/08/26</span>
///       <span class="msg-subj">學生宿舍開放入住首二日…</span>
///       <span class="bbs-unit"><i></i><span>學務處住宿輔導組</span></span>
/// ```
List<Announcement> parseAnnouncements(String html) {
  final doc = html_parser.parse(html);
  final scope = doc.querySelector('#BBS_BLOCK') ?? doc.documentElement;
  if (scope == null) return const [];

  final out = <Announcement>[];
  for (final row in scope.querySelectorAll('.msg-list')) {
    final title = clean(row.querySelector('.msg-subj')?.text ?? '');
    if (title.isEmpty) continue;

    out.add(Announcement(
      title: title,
      unit: clean(row.querySelector('.bbs-unit')?.text ?? ''),
      id: _idRe.firstMatch(row.querySelector('a')?.attributes['onclick'] ?? '')
              ?.group(1) ??
          '',
      date: _dateOf(row.querySelectorAll('span')),
    ));
  }
  return out;
}

final RegExp _idRe = RegExp(r"""openBbsAnnouncement\(\s*['"]([^'"]+)['"]""");

/// `115/08/26`。**只認斜線那種寫法** —— 標題裡常常有「115年8月28日」，
/// 那是公告內容講的日期，不是發布日期，抓錯會讓排序整個亂掉。
final RegExp _rocDateRe = RegExp(r'(\d{3})/(\d{1,2})/(\d{1,2})');

/// 民國轉西元。
///
/// 只看**日期那一格**，不要對整列的文字下正則：標題裡的日期會先被撈到。
DateTime? _dateOf(List<dom.Element> spans) {
  for (final span in spans) {
    final cls = span.className;
    if (cls.contains('msg-subj') || cls.contains('bbs-unit')) continue;
    final m = _rocDateRe.firstMatch(clean(span.text));
    if (m == null) continue;
    final year = int.parse(m.group(1)!) + 1911;
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) continue;
    return DateTime(year, month, day);
  }
  return null;
}

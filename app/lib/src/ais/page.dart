import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 一次 HTTP 回應，HTML 已經解好碼。
///
/// **刻意沒有 save() / toString() 印出 html。** spike 的 `Page.save()` 是把頁面
/// 存成 fixture 用的，那在 CLI 上很好用；但登入回應裡有明文密碼（校方系統會回吐），
/// App 裡只要有一條路徑能把 html 寫出去，遲早會經過 log 或崩潰回報。
class AisPage {
  AisPage({required this.url, required this.status, required this.html});

  final String url;
  final int status;
  final String html;

  dom.Document? _doc;

  /// 解析結果有快取 —— 課表頁三萬多 bytes，重複 parse 會讓捲動卡頓。
  dom.Document get doc => _doc ??= html_parser.parse(html);

  /// 給 log 用的一行摘要。**只有長度，沒有內容。**
  String get summary => '[$status] $url (${html.length}B)';

  @override
  String toString() => 'AisPage($summary)';
}

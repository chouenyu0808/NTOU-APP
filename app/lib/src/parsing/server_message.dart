/// 學校用 JS 留給使用者的一句話。
///
/// 這個系統有話要說的時候不是寫在頁面上，是注入一段 JS 讓瀏覽器彈出來，
/// 然後把人踢回首頁。App 不跑 JS，所以那句話整個消失 —— 使用者看到的是
/// 一頁空白，完全不知道發生什麼事。
///
/// 實際長相（2026-09-08 抓的「人工加選申請」，非開放時段）：
///
/// ```html
/// <script>alert('人工加選尚未開放!');</script>
/// <script>location.href='/Portal.aspx';</script>
/// ...
/// <script type="text/javascript">
///   //<![CDATA[ var lang='ZH_TW';...
///   Message.showMessage('人工加選尚未開放!');;location.href='/Portal.aspx';;...
/// </script>
/// ```
///
/// 同一句話講兩次（一次 `alert`、一次 `Message.showMessage`），配一個導向。
library;

import 'inline_script.dart';

/// ASP.NET 從後端注入的訊息。
final RegExp _showMessageRe = RegExp(
  r'''Message\.showMessage\(\s*(['"])(.*?)\1\s*\)''',
  dotAll: true,
);

/// 整段就只有一句 alert 的 `<script>`。
///
/// 「頁面上有 alert」不能當條件 —— 每一頁的表單驗證函式裡都寫著
/// `alert("學年期不可為空白!")` 這種東西（`GRD5010` 那頁有兩句）。
/// 那些包在 `function doQuery() {...}` 裡，只有使用者按下查詢才會執行。
final RegExp _bareAlertRe = RegExp(
  r'''^\s*alert\(\s*(['"])(.*?)\1\s*\)\s*;?\s*$''',
  dotAll: true,
);

/// 抓出這一頁上伺服器要說的話，沒有就回 null。
///
/// **真訊息和假訊息分辨靠位置**（`{}` 淨深度 0）—— 那條規則和它的血淚
/// 在 `inline_script.dart` 的 [isTopLevelInScript] 上，那裡同時是
/// `startup_postback.dart` 的依據。
String? serverMessage(String html) {
  for (final body in inlineScripts(html)) {
    // 整段就是一句 alert —— 伺服器注入的長這樣，驗證用的包在函式裡。
    final bare = _bareAlertRe.firstMatch(body);
    final bareText = bare?.group(2)?.trim();
    if (bareText != null && bareText.isNotEmpty) return _tidy(bareText);

    for (final m in _showMessageRe.allMatches(body)) {
      if (!isTopLevelInScript(body, m.start)) continue;
      final text = m.group(2)?.trim();
      if (text != null && text.isNotEmpty) return _tidy(text);
    }
  }
  return null;
}

/// 學校的訊息用的是半形驚嘆號、而且常常連兩個（`尚未開放!`）。
/// 照搬到畫面上會比原本更兇 —— 那句話本身是中性的說明，不是警報。
String _tidy(String s) {
  var out = s.replaceAll(r'\n', ' ').replaceAll(r"\'", "'");
  out = out.replaceAll(RegExp(r'[!！]+$'), '');
  return out.trim();
}

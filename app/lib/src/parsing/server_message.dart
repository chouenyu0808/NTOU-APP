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
///   ...Message.showMessage('人工加選尚未開放!');;location.href='/Portal.aspx';;...
/// </script>
/// ```
///
/// 同一句話講兩次（一次 `alert`、一次 `Message.showMessage`），配一個導向。
library;

/// ASP.NET 從後端注入的訊息。表單驗證不會用這個函式 —— 那邊用的是
/// `alert` 和 `Form.errAppend`，所以這一條幾乎不會誤中。
final RegExp _showMessageRe = RegExp(
  r'''Message\.showMessage\(\s*(['"])(.*?)\1\s*\)''',
  dotAll: true,
);

/// **整段就只有一句 alert 的 `<script>`。**
///
/// 「頁面上有 alert」不能當條件 —— 每一頁的表單驗證函式裡都寫著
/// `alert("學年期不可為空白!")` 這種東西（`GRD5010` 那頁有兩句）。
/// 那些包在 `function doQuery() {...}` 裡，只有使用者按下查詢才會執行，
/// 撈出來顯示的話，使用者會在「人工加選」那一頁看到「學期成績-學年期
/// 不可為空白!」—— 一句完全不相干、但看起來很像真的的訊息。
///
/// 伺服器主動注入的那種是自己一個 `<script>`、裡面只有那一句，
/// 所以用「整段就是它」來認。
final RegExp _bareAlertRe = RegExp(
  r'''<script[^>]*>\s*alert\(\s*(['"])(.*?)\1\s*\)\s*;?\s*</script>''',
  dotAll: true,
  caseSensitive: false,
);

/// 抓出這一頁上伺服器要說的話，沒有就回 null。
///
/// 兩條規則抓到的通常是同一句（學校兩種都送），所以先找哪一條都一樣；
/// `showMessage` 排前面是因為它誤中的機會更低。
String? serverMessage(String html) {
  for (final re in [_showMessageRe, _bareAlertRe]) {
    final m = re.firstMatch(html);
    final text = m?.group(2)?.trim();
    if (text != null && text.isNotEmpty) return _tidy(text);
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

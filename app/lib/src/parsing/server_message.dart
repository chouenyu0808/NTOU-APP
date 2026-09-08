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

/// 每一段 inline `<script>` 的內容。
///
/// 要逐段看而不是對整份 HTML 掃 —— 判斷一句話算不算數，靠的是它在**自己
/// 那一段 script 裡**的位置（見 `_isTopLevel`）。
final RegExp _scriptRe = RegExp(
  r'<script[^>]*>(.*?)</script>',
  dotAll: true,
  caseSensitive: false,
);

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

/// 這個位置是不是在**頂層直接執行**（不在任何 `{}` 裡面）。
///
/// **這一條是這整支檔案的重點。** 一開始的規則是「頁面上有沒有
/// `Message.showMessage`」，理由是「表單驗證用的是 alert，不會用這個函式」——
/// 那個假設在 12 個 fixture 上零誤報，然後在第 13 個上破了：
/// `GRD5010_02`（成績明細）裡有
///
///     function doPrint(gridID, checkBoxName, printType) {
///       ...
///       if (checkCount == 0) {
///         Message.showMessage("必須選擇資料再進行處理!!");
///
/// 那是列印鈕的驗證訊息（「你沒勾選任何一列」），跟頁面現在的狀態完全無關。
/// 照著顯示的話，使用者一打開成績就看到一句莫名其妙的「必須選擇資料」。
///
/// 真訊息是 ASP.NET 用 `RegisterStartupScript` 注入的，一定在頂層 ——
/// 實測人工加選那句深度是 0、`doPrint` 那句是 3。
///
/// 括號是硬數的，字串和註解裡的 `{}` 也會被算進去。對這個系統的 JS 夠用
/// （它們是同一套樣板產生的），而且算錯的方向是**安全的**：深度變成非 0
/// 就是不顯示，回到「跟以前一樣什麼都沒有」，不會顯示錯的東西。
bool _isTopLevel(String js, int index) {
  var depth = 0;
  for (var i = 0; i < index; i++) {
    final c = js.codeUnitAt(i);
    if (c == 0x7B) {
      depth++; // {
    } else if (c == 0x7D) {
      depth--; // }
    }
  }
  return depth <= 0;
}

/// 抓出這一頁上伺服器要說的話，沒有就回 null。
String? serverMessage(String html) {
  for (final script in _scriptRe.allMatches(html)) {
    final body = script.group(1) ?? '';

    // 整段就是一句 alert —— 伺服器注入的長這樣，驗證用的包在函式裡。
    final bare = _bareAlertRe.firstMatch(body);
    final bareText = bare?.group(2)?.trim();
    if (bareText != null && bareText.isNotEmpty) return _tidy(bareText);

    for (final m in _showMessageRe.allMatches(body)) {
      if (!_isTopLevel(body, m.start)) continue;
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

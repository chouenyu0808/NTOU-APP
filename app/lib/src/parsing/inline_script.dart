/// 逐段看 inline `<script>`，並判斷「這個位置會不會在頁面載入時直接執行」。
///
/// 這一套判斷有兩個地方要用，而且它們踩的是**同一個坑** ——
/// 頁面上有一段 JS，不代表那段 JS 現在成立：
///
///   - `server_message.dart`：分辨伺服器注入的那句話，跟包在驗證函式裡
///     「按了查詢才會跳」的 alert
///   - `startup_postback.dart`：分辨頁面載入時自己補抓內容的那一發 postback，
///     跟「點了才跑」「被呼叫才跑」的那些
///
/// 所以規則只放這一份。兩邊各抄一份的話，哪天其中一邊踩到反例修對了，
/// 另一邊會**安靜地**繼續用舊規則 —— 而這兩件事錯了都不會報錯，
/// 只會在畫面上多一句不相干的話、或少一整頁的資料。
library;

/// 每一段 inline `<script>` 的內容，照文件順序。
///
/// 要逐段看而不是對整份 HTML 掃 —— 判斷一段 JS 算不算數，靠的是它在
/// **自己那一段 script 裡**的位置（見 [isTopLevelInScript]）。
final RegExp _scriptRe = RegExp(
  r'<script[^>]*>(.*?)</script>',
  dotAll: true,
  caseSensitive: false,
);

/// 這一頁上每一段 inline `<script>` 的內容。
Iterable<String> inlineScripts(String html) sync* {
  for (final m in _scriptRe.allMatches(html)) {
    yield m.group(1) ?? '';
  }
}

/// [js] 裡 [index] 這個位置是不是在**頂層直接執行**（不在任何 `{}` 裡面）。
///
/// **這一條是這兩個 parser 共同的重點。**
///
/// 訊息那邊一開始的規則是「頁面上有沒有 `Message.showMessage`」，理由是
/// 「表單驗證用的是 alert，不會用這個函式」—— 那個假設在 12 個 fixture 上
/// 零誤報，然後在第 13 個上破了：`GRD5010_02`（成績明細）裡有
///
///     function doPrint(gridID, checkBoxName, printType) {
///       ...
///       if (checkCount == 0) {
///         Message.showMessage("必須選擇資料再進行處理!!");
///
/// 那是列印鈕的驗證訊息（「你沒勾選任何一列」），跟頁面現在的狀態完全無關。
///
/// postback 那邊是同一件事的另一面：同一頁上還有
/// `function doDel(){ __doPostBack('DEL_BTN1','') }`，那顆是**刪除**。
///
/// 伺服器注入的（`RegisterStartupScript`）和頁面載入時自己發的那一發，
/// 一定在頂層 —— 實測人工加選那句深度是 0、`doPrint` 那句是 3。
///
/// 括號是硬數的，字串和註解裡的 `{}` 也會被算進去。對這個系統的 JS 夠用
/// （它們是同一套樣板產生的），而且算錯的方向是**安全的**：深度變成非 0
/// 就是不算數，回到「跟以前一樣」—— 不顯示、不補送，而不是做錯事。
bool isTopLevelInScript(String js, int index) {
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

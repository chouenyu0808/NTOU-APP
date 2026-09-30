/// 有些頁面的內容是它**自己補抓**的，不在我們拿到的那份 HTML 裡。
///
/// `GRD5010_02`（成績單）的 HTML 裡一張表都沒有 —— 成績是頁面載入之後
/// 自己發一發 `__doPostBack('ReQuery','')` 才回來的（ASP.NET 的 UpdatePanel）。
/// App 不跑 JS，所以拿到的是一份**空殼**。
///
/// **而空殼跟「這個帳號沒有資料」長得一模一樣**：學號姓名系所都對、統計欄
/// 全空、零筆結果、沒有任何錯誤，狀態碼 200。2026-09-07 就是這樣誤判的 ——
/// 結論寫成「這個帳號在本校還沒有任何成績」，寫進 README，卡了九天。
/// 真相是同一個帳號有 25 門課。
///
/// 所以這件事不能只寫在成績那條路上：13 個模組 131 個功能共用同一個驅動器，
/// 任何一頁跟 `GRD5010_02` 同型的，少了這一步都會顯示成「查無資料」。
library;

import 'inline_script.dart';

/// `__doPostBack('目標','參數')`。
///
/// **兩邊的引號都要是沒被跳脫的。** 連動下拉的 `onchange` 裡是
/// `__doPostBack(\'Q_X\',\'\')`（包在 `setTimeout` 的字串裡），前面那個
/// 反斜線讓它對不上這條規則 —— 那正是我們要的，那種是「使用者改了才跑」。
final RegExp _doPostBackCallRe = RegExp(
  r"""__doPostBack\(\s*(['"])([^'"]*)\1\s*,\s*(['"])([^'"]*)\3\s*\)""",
);

/// 這一頁載入時**自己發給自己**的那一發 postback，沒有就回 null。
///
/// 判準是：在某一段 `<script>` 的**頂層**（`{}` 淨深度 0）—— 只有那裡的
/// 程式碼會在頁面載入時直接跑掉。同一頁上還有兩種長得很像、但**不能跟**的：
///
/// ```html
/// <a id="ReQuery" href="javascript:__doPostBack('ReQuery','')">     ← 點了才跑
/// <script>function doDel(){ __doPostBack('DEL_BTN1','') }</script>  ← 呼叫了才跑
/// ```
///
/// 第一種根本不在 `<script>` 裡，第二種深度是 1。
/// **成績頁剛好兩個同名，所以抓錯了也看不出來** —— 但別的頁面上那顆
/// 可能是「刪除」，所以規則不能是「頁面上有 `__doPostBack`」。
///
/// 算錯的方向是安全的（見 [isTopLevelInScript]）：深度不是 0 就當作沒有，
/// 回到「跟以前一樣拿到空殼」，而不是憑空送一發 postback 出去。
///
/// 跟 `spike/login.py` 的 `startup_postback()` 是同一套規則，兩邊要一起改。
({String target, String argument})? startupPostback(String html) {
  for (final js in inlineScripts(html)) {
    for (final m in _doPostBackCallRe.allMatches(js)) {
      if (!isTopLevelInScript(js, m.start)) continue;
      final target = m.group(2) ?? '';
      // 空目標送出去只會讓伺服器困惑 —— 寧可當作沒看到。
      if (target.isEmpty) continue;
      return (target: target, argument: m.group(4) ?? '');
    }
  }
  return null;
}

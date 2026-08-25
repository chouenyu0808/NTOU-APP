/// 這個系統換頁幾乎全靠 JS，不是 HTTP 302。
///
/// 三種寫法都要認：
/// ```
/// location.href='DefaultQ.aspx'                    排隊關卡
/// top.location.href='MainFrame.aspx'               登入成功
/// top.mainFrame.location.href='TKE2240_01.aspx'    功能頁派發
/// ```
/// 第三種最容易漏 —— `Application/…/XXXX_.aspx?progcd=…` 這種選單連結其實只是
/// 派發器，直接 GET 只會拿到 1.4KB 空殼，看起來像「這頁沒東西」。
///
/// 右邊一定要是字面值字串，這樣驗證碼圖的
/// `onclick="self.location.href=self.location.href"` 才不會被誤判成導向。
library;

final RegExp _jsRedirectRe = RegExp(
  r'''(?<![\w$])(?:(?:top|self|parent|window)(?:\.\w+)*\.)?location'''
  r'''(?:\.href)?\s*=\s*['"]([^'"]+)['"]''',
);

/// 抓出頁面上第一個 JS 導向目標。沒有就回 null。
///
/// 回傳的可能是相對路徑，要用 `Uri.parse(page.url).resolve(target)` 解析，
/// **不能用 base_url** —— 功能頁埋在 `Application/TKE/TKE22/` 這種深層目錄，
/// 用 base_url 解析會跑到根目錄。
String? jsRedirectTarget(String html) {
  for (final m in _jsRedirectRe.allMatches(html)) {
    final target = m.group(1)!.trim();
    if (target.isEmpty) continue;
    final lower = target.toLowerCase();
    if (lower.startsWith('about:') || lower.startsWith('javascript:')) continue;
    return target;
  }
  return null;
}

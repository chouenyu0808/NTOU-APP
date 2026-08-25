import 'dart:io';

/// fixture 是從真實帳號抓下來的頁面，**沒進版控**（含個資，見 .gitignore）。
///
/// 所以測試不能假設它們存在：檔案在就跑，不在就整組 skip ——
/// 跟 spike 的 pytest 同一個做法。
///
/// 刻意直接讀 `spike/fixtures/`，不複製一份到 `app/test/fixtures/`：
/// 複製等於在版控範圍內多開一個個資出口，而 `.gitignore` 只擋得住它認得的路徑。
/// 少一份副本，就少一次「這份洗乾淨了嗎」的疑問。
final Directory fixturesDir = Directory('../spike/fixtures');

/// 有沒有真的 fixture 可以測。
///
/// **不能只看資料夾在不在。** `spike/fixtures/` 一定存在 ——
/// `menu_tree.json` 是刻意保留在版控裡的（那份沒有個資）。
/// 只檢查資料夾的話，任何 clone 這個 repo 的人都會拿到一整組紅燈，
/// 而錯誤訊息是「檔案不存在」，看起來像程式壞了而不是「你沒有 fixture」。
bool get fixturesAvailable => fixtureFiles().isNotEmpty;

String? get skipReason =>
    fixturesAvailable ? null : '沒有 fixture（跑 spike/login.py --save 產生）';

String fixture(String name) =>
    File('${fixturesDir.path}/$name').readAsStringSync();

List<File> fixtureFiles() {
  // 這裡才是問資料夾在不在的地方 —— fixturesAvailable 反過來靠這個函式，
  // 兩邊互相呼叫會變成無窮遞迴。
  if (!fixturesDir.existsSync()) return const [];
  return fixturesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.html'))
      .toList();
}

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

bool get fixturesAvailable => fixturesDir.existsSync();

String? get skipReason =>
    fixturesAvailable ? null : '沒有 fixture（跑 spike/login.py --save 產生）';

String fixture(String name) =>
    File('${fixturesDir.path}/$name').readAsStringSync();

List<File> fixtureFiles() {
  if (!fixturesAvailable) return const [];
  return fixturesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.html'))
      .toList();
}

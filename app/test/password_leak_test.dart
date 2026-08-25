import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/exceptions.dart';
import 'package:ntou_app/src/ais/page.dart';

import 'fixtures.dart';

/// 守門測試。
///
/// 學校系統會把登入密碼**明文回吐**到登入回應的 HTML 裡，兩處：
/// ```html
/// <script>var keyObj = {LoginPWD:'明文'};</script>
/// <script>_i(0, 'LoginPWD').value = '明文';</script>
/// ```
/// 這不是我們造成的，但後果是我們要處理的：任何一條讓頁面內容流進
/// log、例外訊息或崩潰回報的路徑，都會把使用者的密碼一起送出去。
///
/// 這裡鎖的是「那些路徑不存在」。這種測試紅了不要改測試，要改程式。
void main() {
  group('頁面內容不會經由 toString 外流', () {
    // 這一行故意長得跟真的外洩一模一樣 —— 那正是校方系統回吐密碼時的長相，
    // 照抄才看得出這個測試在防什麼。
    //
    // `hunter2` 在 spike/check.py 的 DUMMY_SECRETS 白名單裡，所以 commit 前的
    // 個資掃描認得它是假資料。**換掉這個值之前先去那份清單加一筆**，
    // 不然 check.py 會（正確地）把它當成外洩的明文密碼擋下來。
    // 密碼寫死不用變數：掃描器讀的是**原始碼**，`'$fakePassword'` 這種插值
    // 在它眼裡就是字面值 `$fakePassword`，不會對到白名單。
    final page = AisPage(
      url: 'https://ais.ntou.edu.tw/Default.aspx',
      status: 200,
      html: "<script>var keyObj = {LoginPWD:'hunter2'};</script>",
    );

    test('AisPage.toString 不含 html', () {
      // Flutter 的 FlutterError.onError、Zone 的 uncaught handler、
      // 任何崩潰回報 SDK 收走的都是 toString()。
      expect(page.toString(), isNot(contains('hunter2')));
      expect(page.toString(), isNot(contains('LoginPWD')));
    });

    test('AisPage.summary 只有 URL、狀態碼、長度', () {
      expect(page.summary, contains('200'));
      expect(page.summary, contains('Default.aspx'));
      expect(page.summary, isNot(contains('hunter2')));
    });
  });

  group('登入例外不帶頁面', () {
    test('LoginFailed 沒有 page 欄位可以外洩內容', () {
      // spike 的 LoginFailed(msg, page) 會把登入回應掛在例外上。
      // 在 CLI 上很方便，在 App 上是把明文密碼交給崩潰回報。
      const e = LoginFailed('登入失敗', diagnostics: 'status=200 len=22063');

      expect(e.toString(), '登入失敗');
      expect(e.diagnostics, isNot(contains('LoginPWD')));
      // diagnostics 只有「形狀」：狀態碼、長度、有沒有導向。
      expect(e.diagnostics, matches(RegExp(r'^[\x20-\x7e]*$')),
          reason: 'diagnostics 只該有 ASCII 的形狀資訊，不該有頁面文字');
    });

    test('SessionExpired 可以帶頁面 —— 走到那裡的都不是登入回應', () {
      const e = SessionExpired('登入逾時了，請重新登入。');
      expect(e.message, isNotEmpty);
      expect(e.page, isNull);
    });
  });

  group('fixture 裡不能有明文密碼', () {
    // 跟 spike/scrub.py 同一組樣式。fixture 在寫檔當下就洗過了，
    // 這是第二道 —— 洗過的東西沒人檢查過第二遍。
    final patterns = <RegExp>[
      RegExp(r"""keyObj\s*=\s*\{\s*LoginPWD\s*:\s*['"]([^'"]*)['"]"""),
      RegExp(
        r"""_i\(\s*\d+\s*,\s*['"]LoginPWD['"]\s*\)\.value\s*=\s*['"]([^'"]*)['"]""",
      ),
    ];

    /// 洗乾淨之後留下的佔位字串（scrub.py 寫的）：
    /// 回吐的密碼換成 `REDACTED`，`__VIEWSTATE` 換成 `SCRUBBED`。
    /// 看到這兩個就是洗過了；看到別的就是真的有東西沒洗掉。
    const placeholders = ['', 'REDACTED', 'SCRUBBED'];

    test('掃過每一份 fixture', () {
      for (final file in fixtureFiles()) {
        final html = file.readAsStringSync();
        for (final re in patterns) {
          for (final m in re.allMatches(html)) {
            expect(
              m.group(1) ?? '',
              isIn(placeholders),
              reason: '${file.path} 裡有沒洗掉的明文密碼。'
                  '**不要 commit**，先跑 spike/scrub.py。',
            );
          }
        }
      }
    }, skip: skipReason);
  });
}

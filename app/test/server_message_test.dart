import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/server_message.dart';

import 'fixtures.dart';

/// 學校用 JS 留給使用者的話。
///
/// App 不跑 JS，所以在做這件事之前，「人工加選尚未開放」這種訊息在畫面上
/// 是**完全消失**的 —— 使用者看到一頁空白，不知道是 App 壞了還是來錯時間。
void main() {
  group('抓得到伺服器的話', () {
    test('Message.showMessage 是 ASP.NET 注入的，最可靠', () {
      const html = '''
        <script type="text/javascript">
        var lang = 'ZH_TW';Message.showMessage('人工加選尚未開放!');;location.href='/Portal.aspx';;
        </script>
      ''';
      expect(serverMessage(html), '人工加選尚未開放');
    });

    test('整段就只有一句 alert 的 script 也算', () {
      const html = "<script>alert('人工加選尚未開放!');</script>";
      expect(serverMessage(html), '人工加選尚未開放');
    });

    test('驚嘆號拿掉 —— 那句話是說明，不是警報', () {
      // 學校的訊息一律用半形驚嘆號結尾，照搬會比原意兇。
      expect(serverMessage("<script>alert('尚未開放!!');</script>"), '尚未開放');
      expect(serverMessage("<script>alert('尚未開放！');</script>"), '尚未開放');
    });

    test('沒有話就是 null，不要回空字串', () {
      // 空字串在 UI 上會變成一張空白的卡片 —— 比什麼都不顯示更糟。
      expect(serverMessage('<html><body>一般頁面</body></html>'), isNull);
      expect(serverMessage("<script>alert('');</script>"), isNull);
    });
  });

  group('不能誤抓的東西', () {
    test('**表單驗證函式裡的 alert 不算**', () {
      // 這是整件事最容易做錯的地方。每一頁的驗證函式裡都寫著這種 alert，
      // 但它們只有在使用者按下查詢、而且欄位沒填的時候才會執行。
      //
      // 撈出來顯示的話，使用者會在「人工加選」那一頁看到
      // 「學期成績-學年期不可為空白!」—— 一句完全不相干、
      // 但看起來很像真的的訊息。
      const html = '''
        <script>
        function doQuery() {
          if (_i(0, "Q_AYEARSMS").value=="") {
            alert("學期成績-學年期不可為空白!");
            return false;
          }
        }
        </script>
      ''';
      expect(serverMessage(html), isNull);
    });

    test('一般頁面的 Message.showProcess 不是訊息', () {
      // 每一頁都有這兩句（載入動畫的開關），它們不帶任何要給人看的字。
      const html = '''
        <script>Message.showProcess();</script>
        <script>Message.hideProcess();</script>
      ''';
      expect(serverMessage(html), isNull);
    });

    test('**函式裡的 Message.showMessage 也不算**', () {
      // 這一條是拿真實反例補的。原本的規則是「頁面上有沒有 showMessage」，
      // 理由是「驗證用的是 alert，不會用這個函式」—— 那個假設在 12 個
      // fixture 上零誤報，然後在第 13 個（GRD5010_02 成績明細）破了：
      //
      // 那是列印鈕的驗證訊息（「你沒勾選任何一列」），跟頁面狀態無關。
      // 照著顯示的話，使用者一打開成績就看到一句莫名其妙的「必須選擇資料」。
      const html = '''
        <script>
        function doPrint(gridID, checkBoxName, printType) {
          var checkCount = 0;
          if (printType == "CHECK") {
            checkCount = getGridCheckCount(gridID, checkBoxName)
            if (checkCount == 0) {
              Message.showMessage("必須選擇資料再進行處理!!");
              return false;
            }
          }
        }
        </script>
      ''';
      expect(serverMessage(html), isNull);
    });

    test('頂層的算、同一段裡函式內的不算', () {
      // 真訊息跟假訊息可以出現在同一段 script 裡 —— 分辨靠的是位置。
      const html = '''
        <script>
        function doPrint() { Message.showMessage("必須選擇資料再進行處理!!"); }
        var lang='ZH_TW';Message.showMessage('人工加選尚未開放!');;
        </script>
      ''';
      expect(serverMessage(html), '人工加選尚未開放');
    });
  });

  group('真實頁面', () {
    const notOpen = 'Application_TKE_TKE20_TKE2040_01.html';

    test('人工加選在非開放時段：抓得到那句話', () {
      expect(serverMessage(fixture(notOpen)), '人工加選尚未開放');
    }, skip: skipUnless(notOpen));

    test('正常的功能頁一句話都不該抓到', () {
      // 這一組是誤報的防線。查詢頁裡有寫死的驗證 alert（GRD5010 有兩句），
      // 規則只要放寬一點就會在這裡冒出來。
      for (final f in [
        'Application_GRD_GRD50_GRD5010_01.html',
        'Application_GRD_GRD30_GRD3060_01.html',
        'Application_ENR_ENRG0_ENRG010_01.html',
        // 成績明細 —— 這一份就是打破「showMessage 一定是伺服器說的」
        // 那個假設的反例，它的 doPrint 裡有一句「必須選擇資料再進行處理」。
        'Application_GRD_GRD50_GRD5010_02.html',
        'Portal.html',
      ]) {
        if (skipUnless(f) != null) continue;
        expect(serverMessage(fixture(f)), isNull, reason: f);
      }
    }, skip: skipUnless('Application_GRD_GRD50_GRD5010_01.html'));
  });
}

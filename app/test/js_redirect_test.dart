import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/js_redirect.dart';

void main() {
  group('jsRedirectTarget', () {
    test('排隊關卡：裸的 location.href', () {
      expect(
        jsRedirectTarget("<script>location.href='DefaultQ.aspx';</script>"),
        'DefaultQ.aspx',
      );
    });

    test('登入成功：top.location.href', () {
      expect(
        jsRedirectTarget("<script>top.location.href = 'MainFrame.aspx';</script>"),
        'MainFrame.aspx',
      );
    });

    test('功能頁派發：top.<frame>.location.href', () {
      // 這一種最容易漏。漏掉的話功能頁只會拿到 1.4KB 空殼，
      // 看起來像「這頁沒東西」而不是「你少跟了一次導向」。
      expect(
        jsRedirectTarget(
          "<script>top.mainFrame.location.href='TKE2240_01.aspx';</script>",
        ),
        'TKE2240_01.aspx',
      );
    });

    test('驗證碼重新整理不算導向', () {
      // onclick="self.location.href=self.location.href" 右邊不是字面值字串。
      // 認成導向的話，每次點驗證碼圖都會被當成換頁。
      expect(
        jsRedirectTarget(
          '<img onclick="self.location.href=self.location.href" />',
        ),
        isNull,
      );
    });

    test('about: 和 javascript: 跳過', () {
      expect(jsRedirectTarget("location.href='about:blank'"), isNull);
      expect(jsRedirectTarget("location.href='javascript:void(0)'"), isNull);
    });

    test('沒有導向就是 null', () {
      expect(jsRedirectTarget('<html><body>沒有腳本</body></html>'), isNull);
    });

    test('不會誤中屬於別的識別字的 location', () {
      // myLocation.href='x' 不是導向。lookbehind 就是為了擋這個。
      expect(jsRedirectTarget("var myLocation = {}; myLocation.href='x';"), isNull);
    });

    test('保留查詢字串', () {
      expect(
        jsRedirectTarget("location.href='TKE2240_.aspx?progcd=STU1220'"),
        'TKE2240_.aspx?progcd=STU1220',
      );
    });
  });
}

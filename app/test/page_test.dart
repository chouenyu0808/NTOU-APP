import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/page.dart';

void main() {
  group('AisPage', () {
    test('保留 url / status / html', () {
      final page = AisPage(
        url: 'https://ais.ntou.edu.tw/x.aspx',
        status: 200,
        html: '<html></html>',
      );
      expect(page.url, 'https://ais.ntou.edu.tw/x.aspx');
      expect(page.status, 200);
      expect(page.html, '<html></html>');
    });

    test('doc 解析出 HTML', () {
      final page = AisPage(
        url: 'u',
        status: 200,
        html: '<html><body><p id="x">嗨</p></body></html>',
      );
      expect(page.doc.querySelector('#x')?.text, '嗨');
    });

    test('doc 有快取：多次讀取回同一個 Document 實例', () {
      // 課表頁三萬多 bytes，重複 parse 會讓捲動卡頓。
      final page = AisPage(url: 'u', status: 200, html: '<html><body></body></html>');
      expect(identical(page.doc, page.doc), isTrue);
    });

    test('summary 只有狀態碼、URL 和長度 —— 不含頁面內容', () {
      // 登入回應含明文密碼，summary 是給 log 用的，一個 byte 內容都不能帶。
      const secret = 'p@ssw0rd-must-never-appear';
      final page = AisPage(
        url: 'https://ais.ntou.edu.tw/Default.aspx',
        status: 200,
        html: "<html>keyObj={LoginPWD:'$secret'}</html>",
      );
      expect(page.summary, contains('200'));
      expect(page.summary, contains('https://ais.ntou.edu.tw/Default.aspx'));
      expect(page.summary, contains('B')); // 長度後綴
      expect(page.summary, isNot(contains(secret)));
    });

    test('toString 不外洩 html 內容', () {
      const secret = 'p@ssw0rd-must-never-appear';
      final page = AisPage(url: 'u', status: 200, html: 'LoginPWD=$secret');
      expect(page.toString(), isNot(contains(secret)));
      expect(page.toString(), contains(page.summary));
    });
  });
}

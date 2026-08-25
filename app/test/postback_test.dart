import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/ais_session.dart';
import 'package:ntou_app/src/ais/page.dart';

import 'fixtures.dart';

void main() {
  AisPage pageOf(String name) => AisPage(
        url: 'https://ais.ntou.edu.tw/x.aspx',
        status: 200,
        html: fixture(name),
      );

  group('autoPostBackFields', () {
    test('抓出課程查詢頁的三組連動下拉', () {
      // 選了上游還沒 postback 之前，下游的 select 是 0 個 option。
      // 那種欄位送出去會踩 event validation，錯誤只是一句通用的 403 ——
      // 所以「哪些欄位改了要重送」必須認得出來。
      final fields =
          AisSession.autoPostBackFields(pageOf('Application_TKE_TKE22_TKE2211_01.html'));

      // 這一頁恰好三組：學制→系所、教師系所→教師名單、大樓→教室
      expect(fields, contains('Q_DEGREE_CODE'));
      expect(fields, contains('Q_TCH_FACULTY_CODE'));
      expect(fields, contains('Q_CLSSRM_BUILD'));
    }, skip: skipReason);

    test('沒有連動的頁面回空的', () {
      final fields = AisSession.autoPostBackFields(
        AisPage(url: 'x', status: 200, html: '<html><body>沒有腳本</body></html>'),
      );
      expect(fields, isEmpty);
    });

    test('跳脫過的引號也認得', () {
      // onchange 裡的 __doPostBack 是包在字串裡的，引號被跳脫成 \'
      const html = r"""
        <select onchange="javascript:setTimeout('__doPostBack(\'Q_X\',\'\')', 0)">
        </select>
      """;
      final fields = AisSession.autoPostBackFields(
        AisPage(url: 'x', status: 200, html: html),
      );
      expect(fields, contains('Q_X'));
    });
  });
}

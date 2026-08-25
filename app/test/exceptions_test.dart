import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/exceptions.dart';
import 'package:ntou_app/src/ais/page.dart';

void main() {
  group('AisException', () {
    test('message 直接可顯示，toString 就是 message', () {
      const e = NetworkFailure('連不上學校系統');
      expect(e.message, '連不上學校系統');
      expect(e.toString(), '連不上學校系統');
    });

    test('每一種都是 AisException / Exception', () {
      expect(const LoginFailed('x'), isA<AisException>());
      expect(const SessionExpired('x'), isA<AisException>());
      expect(const NetworkFailure('x'), isA<AisException>());
      expect(const InvalidFieldValue('x'), isA<AisException>());
      expect(const NetworkFailure('x'), isA<Exception>());
    });
  });

  group('LoginFailed', () {
    test('toString 只吐 message —— diagnostics 不外洩', () {
      // 例外會往上飄到 FlutterError.onError / 崩潰回報，登入回應含明文密碼。
      // 就算把診斷字串塞進去，也只能透過 message 顯示、不能被 toString 收走。
      const e = LoginFailed('驗證碼錯誤', diagnostics: '[200] 21988B redirect=none');
      expect(e.toString(), '驗證碼錯誤');
      expect(e.toString(), isNot(contains('21988B')));
    });

    test('diagnostics 預設為空字串', () {
      const e = LoginFailed('密碼錯誤');
      expect(e.diagnostics, '');
    });

    test('diagnostics 帶得進去，內容是狀態碼／長度／導向，沒有頁面內文', () {
      const e = LoginFailed('登入失敗', diagnostics: '[200] len=21988 redirect=none');
      expect(e.diagnostics, '[200] len=21988 redirect=none');
    });
  });

  group('SessionExpired', () {
    test('可以帶 page（會走到這裡的是功能頁，不是登入回應）', () {
      final page = AisPage(url: 'u', status: 200, html: '<html></html>');
      final e = SessionExpired('請重新登入', page: page);
      expect(e.page, same(page));
      expect(e.toString(), '請重新登入');
    });

    test('page 預設為 null', () {
      const e = SessionExpired('逾時');
      expect(e.page, isNull);
    });
  });
}

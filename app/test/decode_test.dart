import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/decode.dart';

void main() {
  group('decodeHtml & sniffCharset', () {
    test('sniffCharset 成功嗅探各種 meta 標籤寫法', () {
      expect(
        sniffCharset(utf8.encode('<html><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></html>')),
        'utf-8',
      );
      expect(
        sniffCharset(utf8.encode('<meta charset="UTF-8">')),
        'utf-8',
      );
      expect(
        sniffCharset(utf8.encode("<meta charset='big5'>")),
        'big5',
      );
      expect(
        sniffCharset(utf8.encode('<meta charset=iso-8859-1>')),
        'iso-8859-1',
      );
      expect(
        sniffCharset(utf8.encode('<html><head><title>No charset</title></head></html>')),
        isNull,
      );
    });

    test('無宣告 charset 時預設以 UTF-8 解碼', () {
      final bytes = utf8.encode('<html><body>海大校務系統</body></html>');
      final text = decodeHtml(bytes);
      expect(text, '<html><body>海大校務系統</body></html>');
    });

    test('宣告 charset=utf-8 / UTF8 正常解碼 (包含不完整字元 allowMalformed)', () {
      final bytes = utf8.encode('<meta charset="utf-8"><body>國立臺灣海洋大學</body>');
      final text = decodeHtml(bytes);
      expect(text, contains('國立臺灣海洋大學'));

      // 中途截斷位元組 (allowMalformed: true 應輸出 U+FFFD 而不拋出例外)
      final truncatedBytes = bytes.sublist(0, bytes.length - 2);
      expect(() => decodeHtml(truncatedBytes), returnsNormally);
    });

    test('宣告 latin1 / iso-8859-1 / ascii 正常解碼', () {
      const html = '<meta charset="iso-8859-1"><body>Hello World!</body>';
      final bytes = latin1.encode(html);
      final text = decodeHtml(bytes);
      expect(text, contains('Hello World!'));
    });

    test('遭遇不支援的編碼（如 big5）拋出 UnsupportedCharset', () {
      final bytes = utf8.encode('<meta charset="big5"><body>內容</body>');
      expect(
        () => decodeHtml(bytes),
        throwsA(
          isA<UnsupportedCharset>().having(
            (e) => e.charset,
            'charset',
            'big5',
          ).having(
            (e) => e.toString(),
            'toString',
            contains('頁面編碼是 big5，這個版本只支援 UTF-8'),
          ),
        ),
      );
    });
  });
}

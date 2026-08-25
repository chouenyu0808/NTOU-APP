import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/origin.dart';

void main() {
  final base = Uri.parse('https://ais.ntou.edu.tw/');

  group('sameOrigin', () {
    test('同站的深層路徑是同源', () {
      expect(
        sameOrigin(
          Uri.parse('https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2240_01.aspx'),
          base,
        ),
        isTrue,
      );
    });

    test('預設埠正規化：https://x 和 https://x:443 同源', () {
      expect(sameOrigin(Uri.parse('https://ais.ntou.edu.tw:443/x'), base), isTrue);
    });

    test('主機大小寫不影響', () {
      expect(sameOrigin(Uri.parse('https://AIS.NTOU.EDU.TW/x'), base), isTrue);
    });

    test('協定不同不是同源', () {
      expect(sameOrigin(Uri.parse('http://ais.ntou.edu.tw/x'), base), isFalse);
    });

    test('校方少打一條斜線造成的站外導向會被擋下來', () {
      // MenuTree.aspx 裡有一行 top.mainFrame.location.href = "//portal.aspx"
      // 本意是 /portal.aspx，但 // 是協定相對 URL，解析出來是站外主機 ——
      // 而那個網域任何人都能註冊。跟下去就把帶著 session cookie 的請求送出去了。
      final resolved = Uri.parse('https://ais.ntou.edu.tw/MenuTree.aspx')
          .resolve('//portal.aspx');

      expect(resolved.host, 'portal.aspx', reason: '確認這真的解析成站外主機');
      expect(sameOrigin(resolved, base), isFalse);
    });

    test('子網域不是同源', () {
      expect(sameOrigin(Uri.parse('https://evil.ais.ntou.edu.tw/x'), base), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/html_text.dart';

void main() {
  group('clean', () {
    test('去掉頭尾空白', () {
      expect(clean('  王小明  '), '王小明');
    });

    test('把 &nbsp;（U+00A0）當成一般空白', () {
      // WebForms 的表格用 &nbsp; 補空，解出來是 U+00A0。
      expect(clean('王小明 '), '王小明');
      expect(clean('王 小明'), '王 小明');
    });

    test('壓掉全形空白 U+3000', () {
      expect(clean('王　小明'), '王 小明');
      expect(clean('　王小明　'), '王小明');
    });

    test('連續空白（含 tab / 換行）壓成一個', () {
      expect(clean('王    小明'), '王 小明');
      expect(clean('王\t\n 小明'), '王 小明');
    });

    test('「王小明」和「王小明 」清完之後相等 —— 否則會被當成兩個老師', () {
      // 差一個尾隨空白就變兩個 key，課表上會多出一堂一模一樣的課。
      expect(clean('王小明'), clean('王小明 '));
    });

    test('整串都是空白時清成空字串', () {
      expect(clean('    　\t '), '');
    });

    test('沒有多餘空白時原樣返回', () {
      expect(clean('資訊工程學系'), '資訊工程學系');
    });
  });
}

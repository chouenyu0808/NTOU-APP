import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/required_courses.dart';

import 'fixtures.dart';

void main() {
  const name =
      'Application_ENR_ENRA0_ENRA120_01__QUERY_BTN1_115_1_0_0507_01.html';

  group('必修科目表（真實資料：115 入學、資工系、一般生）', () {
    final missing =
        File('${fixturesDir.path}/$name').existsSync() ? null : '沒有 $name';

    late RequiredCourses r;
    setUp(() {
      if (missing == null) r = parseRequiredCourses(fixture(name));
    });

    test('讀得到畢業門檻 —— 這才是審核真正要比的數字', () {
      expect(r.requiredCredits, 78);
      expect(r.electiveMinimum, 57);
      expect(r.graduationMinimum, 135);
    }, skip: missing);

    test('類別靠 rowspan 帶下去，不能讓後面的科目變成沒有類別', () {
      // 表格只有該類別的第一列有「科目類別」那一格，
      // 共同教育課程跨 9 列、系訂專業必修跨 17 列。
      final categories = r.courses.map((c) => c.category).toSet();
      expect(categories, {'共同教育課程', '系訂專業必修'});
      expect(r.courses.every((c) => c.category.isNotEmpty), isTrue);
    }, skip: missing);

    test('課號跟課名黏在一起，要拆開', () {
      // 頁面上是「計算機概論B57011RQ」，中間沒有分隔。
      final intro = r.courses.firstWhere((c) => c.name == '計算機概論');
      expect(intro.codes, ['B57011RQ']);
      expect(intro.credits, 3);
      expect(intro.category, '系訂專業必修');

      // 上下學期各一個課號的
      final calculus = r.courses.firstWhere((c) => c.name == '微積分');
      expect(calculus.codes, ['B5711M97', 'B5721M97']);
      expect(calculus.credits, 6);
    }, skip: missing);

    test('「類別型」的要求沒有課號，不能跟指定科目混在一起', () {
      // 「12-國文領域」是「這個領域修滿 4 學分即可」，不是某一門課。
      final chinese = r.courses.firstWhere((c) => c.name.contains('國文領域'));
      expect(chinese.codes, isEmpty);
      expect(chinese.isSpecificCourse, isFalse);
      expect(chinese.credits, 4);

      expect(
        r.courses.firstWhere((c) => c.name == '計算機概論').isSpecificCourse,
        isTrue,
      );
    }, skip: missing);

    test('建議修課學期讀得出來（0 = 一上）', () {
      final intro = r.courses.firstWhere((c) => c.name == '計算機概論');
      expect(intro.byTerm.keys, [0]); // 一上
      expect(intro.byTerm[0], '3');

      final calculus = r.courses.firstWhere((c) => c.name == '微積分');
      expect(calculus.byTerm.keys, [0, 1]); // 一上、一下 各 3 學分
      expect(calculus.byTerm[1], '3');

      // 博雅課程那種一格寫「2,2」（兩門各兩學分），所以保留原文不轉數字
      final liberal = r.courses.firstWhere((c) => c.name.contains('博雅'));
      expect(liberal.byTerm.values, contains('2,2'));
    }, skip: missing);

    test('小計和總學分不會被當成科目', () {
      expect(r.courses.any((c) => c.name.contains('小計')), isFalse);
      expect(r.courses.any((c) => c.name.contains('總學分')), isFalse);
      expect(r.categoryTotals['共同教育課程學分小計'], 28);
      expect(r.categoryTotals['系訂專業必修學分小計'], 50);
    }, skip: missing);

    test('備註照原文保留 —— 那些是規則，改寫會失真', () {
      final ds = r.courses.firstWhere((c) => c.name == '資料結構');
      expect(ds.note, contains('程式設計'));
      expect(r.notes.any((n) => n.contains('軍訓')), isTrue);
    }, skip: missing);

    test('學分小計對得起來', () {
      // 28 + 50 = 78 = 必修總學分數
      final sum = r.categoryTotals['共同教育課程學分小計']! +
          r.categoryTotals['系訂專業必修學分小計']!;
      expect(sum, r.requiredCredits);
    }, skip: missing);
  });

  group('沒有結果的時候', () {
    test('不是必修科目表的頁面回空的，不要爆掉', () {
      expect(parseRequiredCourses('<html><body>x</body></html>').isEmpty,
          isTrue);
    });
  });

  group('學期標籤', () {
    test('0 = 一上，9 = 五下', () {
      expect(termLabel(0), '一上');
      expect(termLabel(1), '一下');
      expect(termLabel(2), '二上');
      expect(termLabel(9), '五下');
    });
  });
}

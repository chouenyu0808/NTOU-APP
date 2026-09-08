import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/graduation.dart';

import 'fixtures.dart';

/// 「查詢畢業資格」（`ENRG010`）。
///
/// 這一頁把**系上的必修課目表**和**你實際修過的課**擺在同一列上對照。
/// 所以還沒修的課，那一列左半邊是整排空白 —— 那不是解析失敗。
void main() {
  group('合成頁面', () {
    String page({required String rows, String credits = ''}) => '''
      <html><body>
        <table id="DataList"><tr><td>
          共同教育課程
          <table id="DataList_ctl00_DataGrid_FIELD">
            <tr>
              <th>修課學年期</th><th>原修課程名稱</th><th>選課別</th>
              <th>學年別</th><th>開課單位</th><th>成績</th><th>學分</th>
              <th>學期</th><th>必修課目</th><th>學分</th><th>審核結果</th>
            </tr>
            $rows
          </table>
        </td></tr></table>
        $credits
      </body></html>
    ''';

    test('還沒修的課：左半邊空白，右半邊是要求', () {
      final s = parseGraduation(page(rows: '''
        <tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
            <td>一上</td><td>12-國文領域</td><td>2</td><td></td></tr>
      '''));

      final c = s.groups.single.courses.single;
      expect(c.term, '一上');
      expect(c.name, '12-國文領域');
      expect(c.credits, 2);
      expect(c.taken, isFalse, reason: '沒有修課學年期就是還沒修');
      expect(c.grade, isNull);
    });

    test('修過的課：兩邊都有值', () {
      final s = parseGraduation(page(rows: '''
        <tr><td>1141</td><td>大一國文</td><td>必</td><td>1</td><td>共教中心</td>
            <td>85</td><td>2</td>
            <td>一上</td><td>12-國文領域</td><td>2</td><td>通過</td></tr>
      '''));

      final c = s.groups.single.courses.single;
      expect(c.taken, isTrue);
      expect(c.takenTerm, '1141');
      // 領域型的要求底下修的是某一門具體的課，兩個名字不一樣。
      expect(c.takenName, '大一國文');
      expect(c.name, '12-國文領域');
      expect(c.grade, '85');
      expect(c.review, '通過');
    });

    test('**要求學分抓的是「必修課目」後面那一欄**', () {
      // 表頭裡「學分」出現兩次：一次在「成績」後面（實得），一次在
      // 「必修課目」後面（要求）。用 indexOf 會永遠拿到第一個，於是
      // 「要求幾學分」整欄讀成實得學分 —— 沒修過的課就變成 0 學分，
      // 而畫面上看起來完全合理。
      final s = parseGraduation(page(rows: '''
        <tr><td>1141</td><td>大一國文</td><td>必</td><td>1</td><td>共教中心</td>
            <td>85</td><td>9</td>
            <td>一上</td><td>12-國文領域</td><td>2</td><td></td></tr>
      '''));
      expect(s.groups.single.courses.single.credits, 2, reason: '不是那個 9');
    });

    test('0 學分是有意義的值，不是缺值', () {
      // 游泳畢業門檻、體育課程都是 0 學分 —— 那種要求是「通過」不是「拿學分」。
      final s = parseGraduation(page(rows: '''
        <tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
            <td>三上</td><td>游泳畢業門檻</td><td>0</td><td></td></tr>
      '''));
      expect(s.groups.single.courses.single.credits, 0);
    });

    test('沒有課目名稱的列跳過（小計、裝飾）', () {
      final s = parseGraduation(page(rows: '''
        <tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
            <td>一上</td><td>12-國文領域</td><td>2</td><td></td></tr>
        <tr><td colspan="11">總計課程：0 學分</td></tr>
      '''));
      expect(s.groups.single.courses, hasLength(1));
    });

    test('學分統計貼回對應的類別', () {
      final s = parseGraduation(page(
        rows: '''
          <tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
              <td>一上</td><td>12-國文領域</td><td>2</td><td></td></tr>
        ''',
        credits: '''
          <table id="DataGrid_CRD">
            <tr><th>總計學分</th><th>應修學分</th><th>已得學分(1)</th>
                <th>修讀中學分(2)</th><th>(1) + (2)</th>
                <th>未通過學分</th><th>未通過科目</th></tr>
            <tr><td>共同教育課程</td><td>28</td><td>4</td><td>2</td><td>6</td>
                <td>22</td><td>16</td></tr>
            <tr><td>選修</td><td>-</td><td>0</td><td>0</td><td>0</td>
                <td>-</td><td>-</td></tr>
          </table>
        ''',
      ));

      final g = s.groups.single;
      expect(g.category, '共同教育課程');
      expect(g.summary!.required_, 28);
      expect(g.summary!.earned, 4);
      expect(g.summary!.failed, 22);
      expect(g.summary!.failedCourses, 16);

      // 沒有課目清單的類別（選修）不會憑空生一個空白區塊出來，
      // 但它的數字還是要看得到。
      expect(s.otherSummaries.map((e) => e.category), ['選修']);
      expect(s.otherSummaries.single.required_, isNull, reason: '學校給的是 -');
    });

    test('空頁面回空的，不要爆掉', () {
      final s = parseGraduation('<html><body>沒有表格</body></html>');
      expect(s.isEmpty, isTrue);
    });
  });

  group('真實頁面', () {
    const f = 'Application_ENR_ENRG0_ENRG010_01.html';

    test('兩個類別、學分統計、以及「一門都還沒修」', () {
      final s = parseGraduation(fixture(f));

      expect(s.groups.map((g) => g.category), ['共同教育課程', '系訂專業必修']);

      final common = s.groups[0];
      final major = s.groups[1];
      expect(common.summary!.required_, 28);
      expect(major.summary!.required_, 50);

      // 2026-09-08 抓的時候這個帳號在本校還沒有任何成績 ——
      // 所以「未通過科目」等於課目總數，一門都還沒修。
      expect(common.takenCount, 0);
      expect(major.takenCount, 0);
      expect(common.summary!.failedCourses, common.courses.length);
      expect(major.summary!.failedCourses, major.courses.length);
    }, skip: skipUnless(f));

    test('畢業門檻那種 0 學分的要求也在清單裡', () {
      // 游泳和英文畢業門檻最容易被忘記，而它們正是 0 學分的 ——
      // 用「學分 > 0」過濾清單的話會把它們濾掉。
      final s = parseGraduation(fixture(f));
      final names =
          s.groups.expand((g) => g.courses).map((c) => c.name).toList();
      expect(names, contains('游泳畢業門檻'));
      expect(names, contains('英文畢業門檻'));

      final swim = s.groups
          .expand((g) => g.courses)
          .firstWhere((c) => c.name == '游泳畢業門檻');
      expect(swim.credits, 0);
    }, skip: skipUnless(f));

    test('領域型的要求跟具體課名都認得', () {
      final s = parseGraduation(fixture(f));
      final names =
          s.groups.expand((g) => g.courses).map((c) => c.name).toSet();
      expect(names, contains('11-博雅課程')); // 領域
      expect(names, contains('計算機概論')); // 具體課名
    }, skip: skipUnless(f));
  });
}

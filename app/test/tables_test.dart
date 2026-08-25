import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:ntou_app/src/parsing/tables.dart';

void main() {
  group('expandGrid', () {
    test('rowspan 攤平之後，跨列的每一格都是同一個物件', () {
      // 連堂課就是這樣表示的。照位置逐格讀的話，兩小時的課只會出現在第一節 ——
      // 課表看起來完全正常，只是課提早一小時結束。錯得很安靜。
      final table = html_parser.parse('''
        <table>
          <tr><th>節次</th><th>一</th><th>二</th></tr>
          <tr><td>3</td><td rowspan="2">微積分</td><td>體育</td></tr>
          <tr><td>4</td><td>國文</td></tr>
        </table>
      ''').querySelector('table')!;

      final grid = expandGrid(table);
      expect(grid.length, 3);
      expect(grid.every((r) => r.length == 3), isTrue, reason: '每列補齊成一樣寬');

      // 第 3 節和第 4 節的「一」欄是同一堂課
      expect(identical(grid[1][1], grid[2][1]), isTrue);
      expect(gridText(grid)[2][1], '微積分');

      // 第二列原本只有兩個 td，rowspan 佔位之後「二」欄要落在正確的位置
      expect(gridText(grid)[2][2], '國文');
    });

    test('colspan 攤平', () {
      final table = html_parser.parse('''
        <table>
          <tr><td colspan="3">整週停課</td></tr>
          <tr><td>a</td><td>b</td><td>c</td></tr>
        </table>
      ''').querySelector('table')!;

      final grid = expandGrid(table);
      expect(grid[0].length, 3);
      expect(identical(grid[0][0], grid[0][2]), isTrue);
      expect(gridText(grid)[0], ['整週停課', '整週停課', '整週停課']);
    });

    test('rowspan 和 colspan 同時出現', () {
      final table = html_parser.parse('''
        <table>
          <tr><td rowspan="2" colspan="2">大格</td><td>x</td></tr>
          <tr><td>y</td></tr>
        </table>
      ''').querySelector('table')!;

      final grid = expandGrid(table);
      expect(gridText(grid)[0], ['大格', '大格', 'x']);
      expect(gridText(grid)[1], ['大格', '大格', 'y']);
    });

    test('rowspan 是 0 或非數字時當成 1', () {
      final table = html_parser.parse('''
        <table><tr><td rowspan="0">a</td><td rowspan="abc">b</td></tr></table>
      ''').querySelector('table')!;

      expect(expandGrid(table).length, 1);
    });
  });

  group('tableToRecords', () {
    test('第一列當表頭', () {
      final records = tableToRecords([
        ['課號', '課名'],
        ['B57011RQ', '計算機概論'],
      ]);
      expect(records, [
        {'課號': 'B57011RQ', '課名': '計算機概論'},
      ]);
    });

    test('欄數不符的列跳過', () {
      // GridView 的分頁列、合計列欄數都不一樣。硬塞只會產生垃圾資料。
      final records = tableToRecords([
        ['課號', '課名'],
        ['B57011RQ', '計算機概論'],
        ['共 1 筆'],
      ]);
      expect(records.length, 1);
    });
  });

  group('pickTable / firstOf', () {
    test('用表頭關鍵字挑表，不用位置', () {
      const html = '''
        <table><tr><th>公告</th></tr><tr><td>停課通知</td></tr></table>
        <table><tr><th>課號</th><th>課名</th></tr>
               <tr><td>B570</td><td>計概</td></tr></table>
      ''';
      expect(pickTable(html, ['課號'])?.first, ['課號', '課名']);
      expect(pickTable(html, ['不存在的欄位']), isNull);
    });

    test('firstOf 接受部分比對', () {
      const rec = {'科目名稱': '計算機概論', '學分數': '3'};
      expect(firstOf(rec, ['課名', '科目名稱']), '計算機概論');
      expect(firstOf(rec, ['學分']), '3', reason: '「學分」是「學分數」的一部分');
      expect(firstOf(rec, ['沒有這一欄']), '');
    });
  });

  group('isEmptyResult', () {
    test('認得「查無符合資料」', () {
      // 這一頁狀態碼是 200、結構完全正常，只有這一行字不一樣。
      // 不認得的話會以為 parser 壞了，然後跑去 debug 錯的東西。
      expect(isEmptyResult('<td>查無符合資料!!</td>'), isTrue);
      expect(isEmptyResult('<td>There is no matching data</td>'), isTrue);
    });

    test('有資料的頁面不是空結果', () {
      expect(isEmptyResult('<table id="DataGrid"><tr><td>計概</td></tr></table>'),
          isFalse);
    });
  });
}

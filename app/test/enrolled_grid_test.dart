import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/parsing/timetable.dart';

import 'fixtures.dart';

/// 對著真實的「選課課表」（`QUERY_BTN3`）頁面測。
///
/// 這一組的斷言是**寫死的已知答案** —— 2026-09-03 抓下來時使用者實際選的三門課。
/// 星期或節次算錯的話這裡會紅，而畫面上不會：每一格都有課、看起來很正常，
/// 只是整張表平移了一天或一節。
const String _fixture =
    'Application_TKE_TKE22_TKE2240_01__QUERY_BTN3_115_1.html';

void main() {
  group('parseEnrolledGrid（真實頁面）', () {
    late Map<String, GridCourse> grid;

    setUpAll(() {
      if (fixturesAvailable) grid = parseEnrolledGrid(fixture(_fixture));
    });

    test('三門課都認出來，而且以課號為 key', () {
      expect(grid.keys.toSet(), {'B57011RQ', 'B5701M33', 'B5701V75'});
    }, skip: skipReason);

    test('計算機概論：週一第 2、3、4 節，INS105', () {
      final c = grid['B57011RQ']!;
      expect(c.name, '計算機概論');
      expect(c.room, 'INS105');
      // weekday 0 = 週一
      expect(c.slots, const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
    }, skip: skipReason);

    test('程式設計：週三第 7、8、9 節，INS303', () {
      final c = grid['B5701M33']!;
      expect(c.name, '程式設計');
      expect(c.room, 'INS303');
      expect(c.slots, const [
        TimeSlot(2, 7),
        TimeSlot(2, 8),
        TimeSlot(2, 9),
      ]);
    }, skip: skipReason);

    test('離散數學：週四第 2、3、4 節，ECGB107', () {
      final c = grid['B5701V75']!;
      expect(c.name, '離散數學');
      expect(c.room, 'ECGB107');
      expect(c.slots, const [
        TimeSlot(3, 2),
        TimeSlot(3, 3),
        TimeSlot(3, 4),
      ]);
    }, skip: skipReason);

    test('開課單位和班別也讀得出來', () {
      expect(grid['B57011RQ']!.unit, '資訊工程學系');
      // 格子裡是短班別（1A），選課清單裡是「1年A班」—— 所以不能拿來比對
      expect(grid['B57011RQ']!.classLabel, '1A');
    }, skip: skipReason);
  });

  group('parseEnrolledGrid（合成頁面）', () {
    test('節次欄同時有時鐘時間，不能抓成 09', () {
      // 通用的 _periodOf 會抓文字裡第一個數字 —— 那會把「第二節」讀成 9。
      const html = '''
<table id="table2">
  <tr><td>&nbsp;</td><td>星期一</td><td>星期二</td></tr>
  <tr><td>第二節<br/>09:20<br/>~<br/>10:10<br/></td>
      <td><a href="javascript:fn_open('1');">微積分<br>B123<br>應數系<br>1A<br>SC101</a></td>
      <td>&nbsp;</td></tr>
</table>''';
      expect(parseEnrolledGrid(html)['B123']!.slots, const [TimeSlot(0, 2)]);
    });

    test('第 0 節是阿拉伯數字，其餘是國字，兩種都要認', () {
      const html = '''
<table id="table2">
  <tr><td>&nbsp;</td><td>星期一</td></tr>
  <tr><td>第0節<br/>06:20</td>
      <td><a href="#">早課<br>A1<br>單位<br>1A<br>R1</a></td></tr>
  <tr><td>第十四節<br/>21:15</td>
      <td><a href="#">晚課<br>A2<br>單位<br>1A<br>R2</a></td></tr>
</table>''';
      final g = parseEnrolledGrid(html);
      expect(g['A1']!.slots, const [TimeSlot(0, 0)]);
      expect(g['A2']!.slots, const [TimeSlot(0, 14)]);
    });

    test('表頭認不出星期就回空的，不要靠欄位索引硬猜', () {
      // 星期欄名變了（或整列不見）時，寧可什麼都不給，
      // 也不要給一張整體平移一天的課表 —— 那在畫面上看不出來。
      const html = '''
<table id="table2">
  <tr><td>&nbsp;</td><td>Mon</td><td>Tue</td></tr>
  <tr><td>第二節</td>
      <td><a href="#">微積分<br>B123<br>應數系<br>1A<br>SC101</a></td></tr>
</table>''';
      expect(parseEnrolledGrid(html), isEmpty);
    });

    test('沒有課號的格子跳過 —— 合併不了就等於用不上', () {
      const html = '''
<table id="table2">
  <tr><td>&nbsp;</td><td>星期一</td></tr>
  <tr><td>第一節</td><td><a href="#">只有課名</a></td></tr>
</table>''';
      expect(parseEnrolledGrid(html), isEmpty);
    });

    test('同一格兩門課都要收', () {
      const html = '''
<table id="table2">
  <tr><td>&nbsp;</td><td>星期一</td></tr>
  <tr><td>第三節</td><td>
      <a href="#">甲<br>C1<br>單位<br>1A<br>R1</a><br>
      <a href="#">乙<br>C2<br>單位<br>1B<br>R2</a></td></tr>
</table>''';
      expect(parseEnrolledGrid(html).keys.toSet(), {'C1', 'C2'});
    });

    test('沒有 table2 就回空的', () {
      expect(parseEnrolledGrid('<html><body>查無符合資料</body></html>'), isEmpty);
    });
  });
}

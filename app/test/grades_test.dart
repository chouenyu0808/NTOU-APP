import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/grades.dart';

import 'fixtures.dart';

/// 成績單（`GRD5010_02`）的解析。
///
/// 這一頁上每一件會出錯的事都是安靜的：欄位對錯了是「每一門課都沒成績」、
/// 記號認不得是畫面上一個裸 `+`、把記號當數字是「平均 0 分」。
/// 沒有一種會丟例外。
const _fixture = 'Application_GRD_GRD50_GRD5010_02__QUERY_BTN1_1151.html';

/// 表頭照真實頁面的順序（9 欄）。
String _page(String rows, {String totals = ''}) =>
    '''
<html><body>
<div class="row">
  <div class="col-md-3"><span ml="PL_歷年累計學分">歷年累計學分</span></div>
  <div class="col-md-9"><span id="M_CRD">$totals</span></div>
</div>
<table id="DataGrid">
  <tr><th>學年期</th><th>課號</th><th>開課班別</th><th>學分數</th><th>選別</th>
      <th>課程名稱</th><th>教師姓名</th><th>學期總成績</th><th>其他成績</th></tr>
  $rows
</table>
</body></html>''';

String _row({
  String term = '1151',
  String code = 'B5701M33',
  String classNo = 'A',
  String credits = '3',
  String kind = '必修',
  String name = '程式設計',
  String teacher = '林川傑',
  required String score,
}) =>
    '<tr><td>$term</td><td>$code</td><td>$classNo</td><td>$credits</td>'
    '<td>$kind</td><td>$name</td><td>$teacher</td><td>$score</td>'
    '<td>詳</td></tr>';

void main() {
  group('學期總成績那一欄不是數字', () {
    test('**半形的記號也要認得**', () {
      // 頁尾圖例印的是全形（＋ U+FF0B），但儲存格裡是半形（+ U+002B）——
      // 2026-09-16 實測 6 筆全是半形。只認圖例上那個字元的話永遠不會命中，
      // 而畫面上不會報錯，只會出現一個沒有說明的裸 `+`。
      expect(parseGradeMark('+').note, '成績未到');
      expect(parseGradeMark('＋').note, '成績未到');
      expect(parseGradeMark('*').note, '不及格');
      expect(parseGradeMark('＊').note, '不及格');
    });

    test('抵免和期中退選', () {
      expect(parseGradeMark('抵').note, '抵免');
      expect(parseGradeMark('抵').isTransferred, isTrue);
      expect(parseGradeMark('W').note, '期中退選');
    });

    test('**記號不能變成 0 分**', () {
      // 這是這一頁最貴的一個錯：把「成績未到」算成 0，
      // 使用者會以為自己被當了。
      final m = parseGradeMark('+');
      expect(m.score, isNull);
      expect(m.hasNoScore, isTrue);
    });

    test('真的是分數就留著分數', () {
      expect(parseGradeMark('85').score, '85');
      expect(parseGradeMark('85').note, isNull);
      expect(parseGradeMark('100').score, '100');
    });

    test('分數是 0 分跟「沒有分數」分得開', () {
      // 0 分是真的會發生的成績，不能跟「這一格我沒解出來」混在一起。
      expect(parseGradeMark('0').score, '0');
      expect(parseGradeMark('0').hasNoScore, isFalse);
      expect(parseGradeMark('').score, isNull);
      expect(parseGradeMark('').note, isNull);
    });

    test('記號黏著分數時兩個都留著', () {
      final m = parseGradeMark('*55');
      expect(m.score, '55');
      expect(m.note, '不及格');
    });

    test('**認不得的記號照原樣顯示，不要自己編一個說法**', () {
      // 學校哪天多一個記號，畫面上寧可出現一個看不懂的字，
      // 也不要把它講成「成績未到」——那是在說謊。
      final m = parseGradeMark('甲');
      expect(m.note, isNull);
      expect(m.raw, '甲');
      expect(m.isPassed, isFalse);
      expect(m.isUnconfirmed, isTrue);
    });

    test('未知文字、破折號與異常數字不能算及格', () {
      for (final raw in ['待審核', '不通過', '—', '', 'NaN', 'Infinity', '101']) {
        expect(parseGradeMark(raw).isPassed, isFalse, reason: raw);
      }
      for (final raw in ['85', '82.5', '抵', '通過', '及格']) {
        expect(parseGradeMark(raw).isPassed, isTrue, reason: raw);
      }
    });
  });

  group('整份成績單', () {
    test('一門課解出該有的欄位', () {
      final r = parseGrades(_page(_row(score: '+')));
      expect(r.courses, hasLength(1));
      final c = r.courses.single;
      expect(c.term, '1151');
      expect(c.name, '程式設計');
      expect(c.code, 'B5701M33');
      expect(c.kind, '必修');
      expect(c.teacher, '林川傑');
      expect(c.credits, 3);
      expect(c.mark.note, '成績未到');
    });

    test('0 學分跟「解不到學分」分得開', () {
      // 體育就是 0 學分（真實資料裡有 3 筆），那是有意義的值。
      expect(
        parseGrades(_page(_row(credits: '0', score: '抵')))
            .courses
            .single
            .credits,
        0,
      );
      expect(
        parseGrades(_page(_row(credits: '', score: '抵')))
            .courses
            .single
            .credits,
        isNull,
      );
    });

    test('跨學年期分得開，新的在前面', () {
      // 抵免會掛在未來的學期上 —— 真實資料裡 1152 有 4 筆。
      final r = parseGrades(
        _page(
          _row(term: '1151', name: '程式設計', score: '+') +
              _row(term: '1152', name: '體育', score: '抵'),
        ),
      );
      expect(r.terms, ['1152', '1151']);
      expect(r.inTerm('1151').single.name, '程式設計');
    });

    test('**空的統計欄不要收**', () {
      // 學校在還沒有成績時把平均、排名留空。收進來再顯示成 0，
      // 等於告訴使用者「你的平均是 0 分」。
      final r = parseGrades(_page(_row(score: '+')));
      expect(r.totals.containsKey('歷年累計學分'), isFalse);
      expect(r.totals.containsKey('目前平均成績'), isFalse);

      final r2 = parseGrades(_page(_row(score: '+'), totals: '40'));
      expect(r2.totals['歷年累計學分'], '40');
    });

    test('沒有表格時是空的，不是丟例外', () {
      expect(parseGrades('<html><body>什麼都沒有</body></html>').isEmpty, isTrue);
    });

    test('**欄序換掉也要對** —— 靠表頭，不是靠位置', () {
      // 學校在中間插一欄，照位置解的話從那一欄之後全部錯開，
      // 而畫面上每一格都還是有東西，看不出來。
      final html = '''
<html><body><table id="DataGrid">
  <tr><th>學年期</th><th>新的一欄</th><th>課程名稱</th><th>學期總成績</th></tr>
  <tr><td>1151</td><td>x</td><td>微積分</td><td>抵</td></tr>
</table></body></html>''';
      final c = parseGrades(html).courses.single;
      expect(c.name, '微積分');
      expect(c.mark.note, '抵免');
    });
  });

  group('真實頁面', () {
    test('解得出 25 門課，本學期 6 門成績未到、19 筆抵免', () {
      final r = parseGrades(fixture(_fixture));

      expect(r.courses, hasLength(25));
      expect(r.terms, ['1152', '1151']);

      final pending = r.courses.where((c) => c.mark.isPending).toList();
      final transferred = r.courses.where((c) => c.mark.isTransferred).toList();
      expect(pending, hasLength(6));
      expect(transferred, hasLength(19));

      // 每一門課都要有名字和學年期 —— 這兩個是分組和顯示的依據。
      expect(r.courses.every((c) => c.name.isNotEmpty), isTrue);
      expect(r.courses.every((c) => c.term.isNotEmpty), isTrue);

      // **沒有任何一格被誤判成分數。** 手上這份真實資料裡一個數字成績都沒有，
      // 所以只要有 score 就是解錯了。
      expect(r.courses.where((c) => c.mark.score != null), isEmpty);
    });

    test('真實頁面的統計只有歷年累計學分有值', () {
      final r = parseGrades(fixture(_fixture));
      expect(r.totals['歷年累計學分'], '40');
      // 其餘都是空的（還沒有成績）—— 不能自己補一個 0 上去。
      expect(r.totals.containsKey('目前平均成績'), isFalse);
      expect(r.totals.containsKey('班排名'), isFalse);
    });

    test('體育是 0 學分，而且解得到', () {
      final r = parseGrades(fixture(_fixture));
      final pe = r.courses.where((c) => c.name == '體育').toList();
      expect(pe, isNotEmpty);
      expect(pe.every((c) => c.credits == 0), isTrue);
    });
  }, skip: skipUnless(_fixture));
}

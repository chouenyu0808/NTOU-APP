import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/grades_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

/// 成績畫面。
///
/// 這一頁的導覽是三步的，而**少哪一步都不會報錯**：
/// 查詢回來的是一列學生清單、明細頁回來的是空殼、
/// 成績要等明細頁自己那一發 `ReQuery` 才長出來。
const _dispatcher = r"""<html><body>
<script>top.mainFrame.location.href='GRD5010_01.aspx';</script>
</body></html>""";

/// 查詢頁（學年期 + 查詢鈕）。
const _queryForm = '''
<html><head><title>GRD5010_</title></head><body><form>
<input type="hidden" name="__VIEWSTATE" value="vs">
<input name="Q_AYEARSMS" type="text" value="1151" CNAME="學期成績之學年期">
<input type="submit" name="QUERY_BTN1" value="查詢">
</form></body></html>''';

/// 按下查詢之後：**一列學生，不是成績**。「詳」的目標在頁尾的 JS 裡。
const _studentList = '''
<html><body><form>
<input type="hidden" name="__VIEWSTATE" value="vs2">
<table id="DataGrid">
  <tr><th>&nbsp;</th><th>部別</th><th>學號</th><th>姓名</th></tr>
  <tr><td>詳</td><td>大學部</td><td>B10900000</td><td>王小明</td></tr>
</table>
</form>
<script>
  var viewpage = "GRD5010_02.aspx";
  doEdit1_2('','STNO|B10900000','Mod');
</script>
</body></html>''';

/// 明細頁剛 POST 回來的樣子：**一張表都沒有**，只有那一發 postback。
const _emptyShell = '''
<html><body><form>
<input type="hidden" name="__VIEWSTATE" value="vs3">
<div class="row">
  <div class="col-md-3"><span ml="PL_歷年累計學分">歷年累計學分</span></div>
  <div class="col-md-9"><span id="M_CRD"></span></div>
</div>
</form>
<script>Message.showProcess();;__doPostBack('ReQuery','');;</script>
</body></html>''';

/// `ReQuery` 之後才有的成績表。
String _grades(String rows, {String total = '40'}) => '''
<html><body><form>
<input type="hidden" name="__VIEWSTATE" value="vs4">
<div class="row">
  <div class="col-md-3"><span ml="PL_歷年累計學分">歷年累計學分</span></div>
  <div class="col-md-9"><span id="M_CRD">$total</span></div>
</div>
<table id="DataGrid">
  <tr><th>學年期</th><th>課號</th><th>開課班別</th><th>學分數</th><th>選別</th>
      <th>課程名稱</th><th>教師姓名</th><th>學期總成績</th><th>其他成績</th></tr>
  $rows
</table>
</form></body></html>''';

const _realRows = '''
<tr><td>1151</td><td>B5701M33</td><td>A</td><td>3</td><td>必修</td>
    <td>程式設計</td><td>林川傑</td><td>+</td><td>詳</td></tr>
<tr><td>1151</td><td>B9600G00</td><td></td><td>0</td><td>必修</td>
    <td>體育</td><td></td><td>抵</td><td>詳</td></tr>
<tr><td>1152</td><td>B9620H61</td><td></td><td>2</td><td>必修</td>
    <td>國文</td><td></td><td>抵</td><td>詳</td></tr>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedAis ais;
  late AppController controller;

  setUp(() async {
    ais = ScriptedAis();
    controller = await loggedInController(ais);
  });

  /// 把完整的三步接起來。[rows] 是 ReQuery 之後那張表的內容。
  void scriptFullFlow({String rows = _realRows}) {
    ais.reply = (r) {
      if (r.page.startsWith('GRD5010_.aspx')) return _dispatcher;
      if (r.page == 'GRD5010_02.aspx') {
        // 第三步：帶著 __EVENTTARGET=ReQuery 回來的才給成績。
        return r['__EVENTTARGET'] == 'ReQuery' ? _grades(rows) : _emptyShell;
      }
      if (r.pressed('QUERY_BTN1')) return _studentList;
      return _queryForm;
    };
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: GradesPage(controller: controller),
    ));
    await tester.pumpAndSettle();
  }

  group('三步導覽', () {
    testWidgets('**成績是第三步才拿到的 —— 那一發一定要送出去**', (tester) async {
      // 這是整條路上最容易漏的一步。漏了的話畫面上是「沒有任何成績紀錄」，
      // 跟「這個帳號真的沒有成績」一模一樣 —— 這個 repo 為此誤判了九天。
      scriptFullFlow();
      await open(tester);

      final reQuery = ais.posts.where((r) => r['__EVENTTARGET'] == 'ReQuery');
      expect(reQuery, hasLength(1), reason: 'ReQuery 沒送出去，成績永遠是空的');
      expect(find.text('程式設計'), findsOneWidget);
    });

    testWidgets('跟著「詳」POST 過去，帶 Mode 和學號', (tester) async {
      // 這是 POST 不是 GET，而且沒有 __VIEWSTATE（表單是 JS 現做的）。
      scriptFullFlow();
      await open(tester);

      final detail = ais.posts.firstWhere((r) => r.page == 'GRD5010_02.aspx');
      expect(detail['Mode'], 'MOD');
      expect(detail['STNO'], 'B10900000');
    });

    testWidgets('明細頁的網址是相對於功能頁解的', (tester) async {
      // viewpage 只寫 `GRD5010_02.aspx`。用網站根目錄去解會 POST 到
      // 不存在的地方，而回來的是一頁空表單，不報錯。
      scriptFullFlow();
      await open(tester);

      final detail = ais.posts.firstWhere((r) => r.page == 'GRD5010_02.aspx');
      expect(detail.url.path, contains('/Application/GRD/GRD50/'));
    });

    testWidgets('**查無修課紀錄 ≠ 沒有成績**', (tester) async {
      // 查詢用的是學校預填的學年期。那一期沒有修課紀錄的話回來是
      // 「查無符合資料」，那一頁沒有可以點的「詳」—— 我們只是進不去，
      // 不是他沒有成績（成績單本身是歷年整份的）。
      ais.reply = (r) {
        if (r.page.startsWith('GRD5010_.aspx')) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) {
          return '<html><body><form>'
              '<input type="hidden" name="__VIEWSTATE" value="v">'
              '查無符合資料!!</form></body></html>';
        }
        return _queryForm;
      };
      await open(tester);

      expect(find.textContaining('查不到你的修課紀錄'), findsOneWidget);
      expect(find.textContaining('這不代表你沒有成績'), findsOneWidget);
      expect(find.textContaining('1151'), findsOneWidget, reason: '要說是哪一期');
    });
  });

  group('畫面上不要出現看不懂的符號', () {
    testWidgets('**`+` 要寫成「還沒登記」，不是印一個加號**', (tester) async {
      // 學校那一欄寫的是 `+`，照搬的話畫面上是一個沒有說明的符號 ——
      // 使用者分不出那是「還沒登記」還是「零分」。
      scriptFullFlow();
      await open(tester);

      expect(find.text('成績未到'), findsOneWidget);
      expect(find.text('+'), findsNothing);
    });

    testWidgets('抵免照講，而且跟「沒有成績」分得開', (tester) async {
      scriptFullFlow();
      await open(tester);
      expect(find.text('抵免'), findsNWidgets(2));
    });

    testWidgets('最上面一句話講清楚現在有沒有分數可看', (tester) async {
      // 一整排沒有數字的課，沒有這一句就像 App 壞了。
      scriptFullFlow();
      await open(tester);
      expect(find.textContaining('1 門還沒登記'), findsOneWidget);
      expect(find.textContaining('2 門抵免'), findsOneWidget);
    });
  });

  group('數字要說實話', () {
    testWidgets('有分數就以分數為主角', (tester) async {
      scriptFullFlow(rows: '''
<tr><td>1151</td><td>C1</td><td>A</td><td>3</td><td>必修</td>
    <td>微積分</td><td>許玉平</td><td>85</td><td>詳</td></tr>''');
      await open(tester);

      expect(find.text('85'), findsOneWidget);
      expect(find.textContaining('1 門有成績'), findsOneWidget);
    });

    testWidgets('**0 學分的課不寫「0 學分」**', (tester) async {
      // 體育就是 0 學分 —— 那種課是「要通過」不是「拿學分」。
      scriptFullFlow();
      await open(tester);

      expect(find.text('體育'), findsOneWidget);
      expect(find.textContaining('0 學分'), findsNothing);
    });

    testWidgets('空的統計欄不顯示（不要變成 0）', (tester) async {
      scriptFullFlow();
      await open(tester);

      expect(find.text('歷年累計學分'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      // 學校沒填的那幾欄根本不該出現
      expect(find.text('目前平均成績'), findsNothing);
      expect(find.text('班排名'), findsNothing);
    });
  });

  group('學年期', () {
    testWidgets('照學期分組，新的在上面', (tester) async {
      scriptFullFlow();
      await open(tester);

      expect(find.text('115 學年 下學期'), findsOneWidget);
      expect(find.text('115 學年 上學期'), findsOneWidget);
    });

    test('**認不得的學期碼照原樣顯示，不要猜**', () {
      expect(termLabel('1151'), '115 學年 上學期');
      expect(termLabel('1152'), '115 學年 下學期');
      expect(termLabel('1153'), '115 學年 暑修');
      // 編一個說法出來，畫面上看起來完全正常，但那是假的
      expect(termLabel('1159'), '1159');
      expect(termLabel('abc'), 'abc');
    });
  });

  testWidgets('學校說不開放的時候，照著講而不是說沒資料', (tester) async {
    ais.reply = (r) => r.page.startsWith('GRD5010_.aspx')
        ? _dispatcher
        : "<html><body>"
            "<script>alert('成績查詢尚未開放!');</script>"
            "<script>location.href='/Portal.aspx';</script>"
            "</body></html>";
    await open(tester);

    expect(find.text('成績查詢尚未開放'), findsOneWidget);
    // 那不是錯誤，不該配一顆「重試」讓人一直按
    expect(find.widgetWithText(FilledButton, '重試'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/graduation_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

/// 畢業資格畫面。
///
/// 這一頁最容易做錯的是「一門都還沒修」的情況 —— 剛轉進來、或大一上剛開學
/// 的人整頁都是未修。那不是壞掉，但畫面要說得出來。
const _dispatcher = r"""<html><body>
<script>top.mainFrame.location.href='ENRG010_01.aspx';</script>
</body></html>""";

/// [rows] 是「共同教育課程」底下的課目列。
String _page({required String rows, String credits = ''}) => '''
<html><head><title>ENRG010_</title></head><body><form>
<input type="hidden" name="__VIEWSTATE" value="vs">
<table id="DataList"><tr><td>
  共同教育課程
  <div class="col-md-12"><div class="table-responsive"><div id="grid-scroll">
  <table id="DataList_ctl00_DataGrid_FIELD">
    <tr>
      <th>修課學年期</th><th>原修課程名稱</th><th>選課別</th><th>學年別</th>
      <th>開課單位</th><th>成績</th><th>學分</th>
      <th>學期</th><th>必修課目</th><th>學分</th><th>審核結果</th>
    </tr>
    $rows
  </table>
  </div></div></div>
</td></tr></table>
$credits
</form></body></html>''';

const _credits = '''
<table id="DataGrid_CRD">
  <tr><th>總計學分</th><th>應修學分</th><th>已得學分(1)</th>
      <th>修讀中學分(2)</th><th>(1) + (2)</th>
      <th>未通過學分</th><th>未通過科目</th></tr>
  <tr><td>共同教育課程</td><td>28</td><td>0</td><td>0</td><td>0</td>
      <td>28</td><td>20</td></tr>
</table>''';

/// 還沒修：左半邊整排空白。
const _notTaken = '''
<tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
    <td>一上</td><td>12-國文領域</td><td>2</td><td></td></tr>
<tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>
    <td>三上</td><td>游泳畢業門檻</td><td>0</td><td></td></tr>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedAis ais;
  late AppController controller;

  setUp(() async {
    ais = ScriptedAis();
    controller = await loggedInController(ais);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: GraduationPage(controller: controller),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('一門都還沒修：學分顯示 0 / 28，而且說得出還差多少', (tester) async {
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : _page(rows: _notTaken, credits: _credits);
    await open(tester);

    expect(find.text('共同教育課程'), findsWidgets);
    expect(find.text('0 / 28'), findsOneWidget);
    expect(find.text('還差 28'), findsOneWidget);
    // 「0 / 2 門」—— 課目層級也要看得出進度
    expect(find.text('0 / 2 門'), findsOneWidget);
  });

  testWidgets('**0 學分的畢業門檻不寫「0 學分」**', (tester) async {
    // 游泳和英文畢業門檻就是 0 學分 —— 那種要求是「通過」不是「拿學分」，
    // 照著寫成「0 學分」會像是不重要的東西，而它們正是最容易被忘記的。
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : _page(rows: _notTaken, credits: _credits);
    await open(tester);

    expect(find.text('游泳畢業門檻'), findsOneWidget);
    expect(find.text('門檻'), findsOneWidget);
    expect(find.text('0 學分'), findsNothing);
    expect(find.text('2 學分'), findsOneWidget); // 一般課目照常寫學分
  });

  testWidgets('修過的課打勾，而且看得到實際修的是哪一門', (tester) async {
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : _page(
            rows: '''
              <tr><td>1141</td><td>大一國文</td><td>必</td><td>1</td>
                  <td>共教中心</td><td>85</td><td>2</td>
                  <td>一上</td><td>12-國文領域</td><td>2</td><td></td></tr>
            ''',
            credits: _credits,
          );
    await open(tester);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // 領域型的要求底下修的是某一門具體的課，兩個名字都要看得到 ——
    // 只顯示「12-國文領域」的話，使用者不知道自己修的是哪一門。
    expect(find.text('12-國文領域'), findsOneWidget);
    expect(find.text('1141 大一國文'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
  });

  testWidgets('未修的是空心圓，不是打勾', (tester) async {
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : _page(rows: _notTaken, credits: _credits);
    await open(tester);

    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('學校說這一頁不開放時，照著講而不是說沒資料', (tester) async {
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : "<html><body>"
            "<script>alert('畢業資格查詢尚未開放!');</script>"
            "<script>location.href='/Portal.aspx';</script>"
            "</body></html>";
    await open(tester);

    expect(find.text('畢業資格查詢尚未開放'), findsOneWidget);
    // 「沒有解出資料」是另一回事（那是學校改版），不能混為一談。
    expect(find.textContaining('學校可能改版'), findsNothing);
  });

  testWidgets('右上角留著必修科目表的入口', (tester) async {
    // 必修科目表（ENRA120）跟這一頁講同一件事，但要自己選入學年度／系所，
    // 選錯就查到別系的規劃。所以它從首頁快捷降級成這裡的次要入口 ——
    // **降級不是刪掉**：想轉系或雙主修的人還是需要查別系。
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : _page(rows: _notTaken, credits: _credits);
    await open(tester);

    expect(find.byTooltip('查其他系的規劃'), findsOneWidget);
  });

  testWidgets('真的解不出東西時說「可能改版了」，並且給重試', (tester) async {
    ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
        ? _dispatcher
        : '<html><body><form>'
            r'<input type="hidden" name="__VIEWSTATE" value="vs">'
            '一頁沒有表格的東西</form></body></html>';
    await open(tester);

    expect(find.textContaining('學校可能改版'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重試'), findsOneWidget);
  });


  group('「不知道」不能講成一個確定的答案', () {
    /// 學分表少了某幾欄（學校改版的樣子）。
    String creditsMissing({required bool failedCol, required bool earnedCol}) => '''
      <table id="DataGrid_CRD">
        <tr><th>總計學分</th><th>應修學分</th>
            ${earnedCol ? '<th>已得學分(1)</th>' : '<th>某個新欄名</th>'}
            <th>修讀中學分(2)</th><th>(1) + (2)</th>
            ${failedCol ? '<th>未通過學分</th>' : '<th>另一個新欄名</th>'}
            <th>未通過科目</th></tr>
        <tr><td>共同教育課程</td><td>28</td><td>0</td><td>0</td><td>0</td>
            <td>28</td><td>20</td></tr>
      </table>''';

    testWidgets('**解不到「未通過學分」時絕對不能說「已達成」**', (tester) async {
      // 這是這一頁最不能出錯的一句話。原本寫 `(failed ?? 0) > 0 ? 還差 : 已達成`
      // —— 學校把那一欄改個名字，畫面上每一類都會變成「已達成」，
      // 使用者會以為自己修完了。
      ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
          ? _dispatcher
          : _page(
              rows: _notTaken,
              credits: creditsMissing(failedCol: false, earnedCol: true),
            );
      await open(tester);

      expect(find.text('已達成'), findsNothing);
      // 「還差 N」那一行也不該出現。注意卡片底部固定有一句說明寫著
      // 「『還差』是學校算的未通過學分…」—— 比對要帶空格才不會撞到它。
      expect(find.textContaining('還差 '), findsNothing);
    });

    testWidgets('解不到「已得學分」時寫「—」，不是 0', (tester) async {
      // 寫 0 等於說「你一分都沒拿到」，那跟「這一欄我沒解出來」是兩回事。
      ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
          ? _dispatcher
          : _page(
              rows: _notTaken,
              credits: creditsMissing(failedCol: true, earnedCol: false),
            );
      await open(tester);

      expect(find.text('— / 28'), findsOneWidget);
    });

    testWidgets('真的是 0 就照實寫 0（跟「不知道」分得開）', (tester) async {
      ais.reply = (r) => r.page.startsWith('ENRG010_.aspx')
          ? _dispatcher
          : _page(rows: _notTaken, credits: _credits);
      await open(tester);

      expect(find.text('0 / 28'), findsOneWidget);
      expect(find.text('還差 28'), findsOneWidget);
    });
  });
}

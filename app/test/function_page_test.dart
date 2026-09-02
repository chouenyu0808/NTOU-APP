import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/function_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

/// 連動下拉的 `onchange`。
///
/// 真的頁面上引號是 HTML 實體再加一層反斜線跳脫的，這裡照抄那個形狀 ——
/// `autoPostBackFields` 刻意走 DOM 而不是對原始 HTML 下正則，就是為了認得它。
const _cascadeOnChange =
    r"""onchange="javascript:setTimeout('__doPostBack(\'Q_DEGREE_CODE\',\'\')', 0)" """;

/// 選單上的路徑是派發器，GET 完只有這個空殼，真正的表單在它導向的那一頁。
const _dispatcher = r"""<html><body>
<script>top.mainFrame.location.href='TKE2211_01.aspx';</script>
</body></html>""";

/// 真正的查詢表單。
///
/// 每個欄位都帶著自己的中文名（`cname`）、按鈕帶著 `ml` —— 這一頁沒有為
/// 「課程課表查詢」寫過任何一行專屬程式碼，畫面全是讀頁面自己的宣告畫出來的。
String _queryPage({String deptOptions = '', String result = ''}) =>
    '<html><head><title>TKE2211_課程課表查詢</title></head><body><form>'
    r'<input type="hidden" name="__VIEWSTATE" value="vs">'
    r'<input type="hidden" name="PC$PageSize" value="10">'
    r'<input type="hidden" name="PC$PageNo" value="1">'
    '<select name="Q_DEGREE_CODE" cname="學制" $_cascadeOnChange>'
    '<option value="">請選擇</option>'
    '<option value="B">學士班</option>'
    '</select>'
    // 初始 0 個選項：要先選學制、連動 postback 之後伺服器才會填。
    '<select name="Q_DEPT_CODE" cname="系所">$deptOptions</select>'
    r'<input type="text" name="Q_CRS_NAME" cname="課程名稱" maxlength="30" value="">'
    r'<input type="submit" name="QUERY_BTN" ml="CB_查詢" value="查詢">'
    r'<input type="submit" name="PRINT_BTN" ml="CB_列印" value="列印">'
    '</form>$result</body></html>';

const _deptOptions =
    '<option value="">請選擇</option><option value="CS">資訊工程學系</option>';

const _resultTable = '<table id="DataGrid">'
    '<tr><td>科目名稱</td><td>教師</td><td>學分</td></tr>'
    '<tr><td>演算法</td><td>王小明</td><td>3</td></tr>'
    '<tr><td>作業系統</td><td>李小華</td><td>3</td></tr>'
    '</table>';

/// 分頁列。「>>」那顆帶著真正的末頁頁碼，所以總頁數是讀出來的，不是猜的。
const _pagerRow =
    r"""<a onclick="gotoPage('PC_PageNo', 3, 'doQuery', '5')">&gt;&gt;</a>""";

/// 分頁式的頁面：同一頁擺了兩套互不相干的查詢條件，各自一顆送出鈕。
const _tabbedPage = '<html><head><title>TKE2211_課程課表查詢</title></head>'
    '<body><form>'
    r'<input type="hidden" name="__VIEWSTATE" value="vs">'
    r'<input type="hidden" name="hdnSelectedTab" value="0">'
    '<ul><li><a href="#tabs-1">單位查詢</a></li>'
    '<li><a href="#tabs-2">教師查詢</a></li></ul>'
    '<div id="tabs-1">'
    '<select name="Q_DEPT" cname="開課單位">'
    '<option value="">全部</option><option value="CS">資訊工程學系</option>'
    '</select>'
    r'<input type="submit" name="QUERY_BTN1" ml="CB_查詢" value="查詢">'
    '</div>'
    '<div id="tabs-2">'
    r'<input type="text" name="Q_TCH_NAME" cname="教師姓名" value="">'
    r'<input type="submit" name="QUERY_BTN2" ml="CB_查詢" value="查詢">'
    '</div>'
    '</form></body></html>';

/// 只有列印鈕的功能頁。
///
/// 學生請假底下有三個這種功能（列印註冊/考試請假單、列印假單證明聯、
/// 列印學期請假紀錄）。列印鈕會被 `queryButtons` 濾掉（掛在 Crystal Reports 上，
/// 輸出不是網頁），濾完就一顆都不剩。
const _printOnlyPage =
    '<html><head><title>SEC5010_列印請假單</title></head><body><form>'
    r'<input type="hidden" name="__VIEWSTATE" value="vs">'
    '<select name="Q_AYEAR" cname="學年度">'
    '<option value="115">115</option></select>'
    r'<input type="submit" name="PRINT_BTN1" ml="CB_列印" value="列印">'
    '</form></body></html>';

/// 被踢回登入頁 —— **狀態碼一樣是 200**，只能靠指紋認出來。
const _kickedToLogin =
    '<html><body><input name="M_PORTAL_LOGIN_ACNT"><input name="LoginPWD">'
    '</body></html>';

const _fn = AisFunction(
  title: '課程課表查詢',
  path: 'Application/TKE/TKE22/TKE2211_.aspx?progcd=x',
  trail: ['教務系統', '選課系統', '課程課表查詢'],
);

const _printFn = AisFunction(
  title: '列印註冊/考試請假單',
  path: 'Application/SEC/SEC50/SEC5010_.aspx?progcd=x',
  trail: ['學生請假', '列印註冊/考試請假單'],
);

const _mutatingFn = AisFunction(
  title: '線上加退選',
  path: 'Application/TKE/TKE20/TKE2011_.aspx?progcd=x',
  trail: ['教務系統', '選課系統', '線上加退選'],
);

/// 派發器那一步（兩個功能頁共用同一個判斷）。
bool _isDispatcher(FakeRequest r) =>
    r.page.startsWith('TKE2211_.aspx') ||
    r.page.startsWith('TKE2011_.aspx') ||
    r.page.startsWith('SEC5010_.aspx');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedAis ais;
  late AppController controller;

  // session 要在 setUp 裡建好：`testWidgets` 的 body 跑在 fake async 裡，
  // 在那裡面 await 一次真正的請求會停住不動。
  setUp(() async {
    ais = ScriptedAis();
    controller = await loggedInController(ais);
  });

  /// 最常見的腳本：派發器 -> 表單；查詢鈕回 [onQuery]；連動回填好的系所。
  void script({String? onQuery, String deptOptions = ''}) {
    ais.reply = (r) {
      if (_isDispatcher(r)) return _dispatcher;
      if (r.cascaded('Q_DEGREE_CODE')) {
        return _queryPage(deptOptions: deptOptions);
      }
      if (onQuery != null && r.pressed('QUERY_BTN')) return onQuery;
      return _queryPage();
    };
  }

  /// 開好功能頁，停在「表單畫出來、還沒查」的狀態。
  Future<void> open(WidgetTester tester, {AisFunction fn = _fn}) async {
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: FunctionPage(controller: controller, function: fn),
    ));
    await tester.pumpAndSettle();
  }

  Finder queryButton() => find.widgetWithText(FilledButton, '查詢');

  group('開啟功能頁', () {
    testWidgets('跟完派發器的 JS 導向才拿得到表單', (tester) async {
      script();
      await open(tester);

      // 直接 GET 派發器只會拿到 1.4KB 空殼，要跟著 JS 導向再抓一次。
      expect(
        ais.seen.map((r) => r.page).toList(),
        ['TKE2211_.aspx', 'TKE2211_01.aspx'],
      );
      await unmount(tester);
    });

    testWidgets('中文標籤和按鈕都是讀頁面自己的宣告畫出來的', (tester) async {
      script();
      await open(tester);

      // cname="學制" / cname="課程名稱" / ml="CB_查詢"
      expect(find.text('學制'), findsOneWidget);
      expect(find.text('課程名稱'), findsOneWidget);
      expect(queryButton(), findsOneWidget);

      // 列印掛在 Crystal Reports 上，輸出不一定是 HTML，不能混進查詢鈕裡
      expect(find.widgetWithText(FilledButton, '列印'), findsNothing);

      // 「還沒查」跟「查了沒資料」是兩件事，要分開講
      expect(find.text('按上面的按鈕開始查詢。'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('0 個選項的下拉不讓人填，並說清楚要先動哪一格', (tester) async {
      script();
      await open(tester);

      expect(find.text('要先選上面的條件，這一格才會有選項'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('被踢回登入頁時說的是「重新登入」，不是解析失敗', (tester) async {
      var kicked = true;
      ais.reply = (r) {
        if (_isDispatcher(r)) return kicked ? _kickedToLogin : _dispatcher;
        return _queryPage();
      };
      await open(tester);

      expect(find.text('登入逾時了，請重新登入。'), findsOneWidget);
      expect(find.text('按上面的按鈕開始查詢。'), findsNothing);

      // 重試要真的重走一次開頁流程
      kicked = false;
      await tester.tap(find.widgetWithText(TextButton, '重試'));
      await tester.pumpAndSettle();

      expect(find.text('登入逾時了，請重新登入。'), findsNothing);
      expect(find.text('學制'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('會改資料的功能頁最上面先講清楚', (tester) async {
      script();
      await open(tester, fn: _mutatingFn);

      expect(find.text('這一頁會真的送出資料，不只是查詢。'), findsOneWidget);

      // 這種頁面下面不會出現結果表格，別叫人「開始查詢」——
      // 只會讓人以為自己少按了什麼。
      expect(find.text('按上面的按鈕開始查詢。'), findsNothing);
      expect(find.text('這一頁是填寫表單，填好上面的欄位再送出。'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('只有列印鈕的頁面不會叫人去按一顆不存在的鈕', (tester) async {
      // 學生請假底下有三個這種功能。列印鈕被 queryButtons 濾掉之後，
      // 上面一顆按鈕都沒有 —— 這時不能再說「按上面的按鈕開始查詢」。
      ais.reply = (r) => _isDispatcher(r) ? _dispatcher : _printOnlyPage;
      await open(tester, fn: _printFn);

      expect(find.text('按上面的按鈕開始查詢。'), findsNothing,
          reason: '上面沒有按鈕可以按');
      await unmount(tester);
    });
  });

  group('連動下拉', () {
    testWidgets('改上游會重送整張表單，而且不送 0 個選項的下游', (tester) async {
      script(deptOptions: _deptOptions);
      await open(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('學士班').last);
      await tester.pumpAndSettle();

      final sent = ais.posts.single;
      // __doPostBack 靠 __EVENTTARGET 說是誰觸發的，**不送任何按鈕的 name** ——
      // 反過來做會變成「按了某顆按鈕」，執行的是別的邏輯。
      expect(sent['__EVENTTARGET'], 'Q_DEGREE_CODE');
      expect(sent.pressed('QUERY_BTN'), isFalse);
      expect(sent['Q_DEGREE_CODE'], 'B');

      // 0 個選項的下拉送出去會踩 event validation，而錯誤只是一句看不懂的 403
      expect(sent.form.containsKey('Q_DEPT_CODE'), isFalse);
      await unmount(tester);
    });

    testWidgets('連動回來之後下游才變成選得動的下拉', (tester) async {
      script(deptOptions: _deptOptions);
      await open(tester);

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('學士班').last);
      await tester.pumpAndSettle();

      // 系所從「不能填的提示」變成第二個下拉
      expect(find.text('要先選上面的條件，這一格才會有選項'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
      await unmount(tester);
    });
  });

  group('查詢', () {
    testWidgets('送出時把每頁筆數調大，並照學校給的欄名欄序畫表格', (tester) async {
      script(onQuery: _queryPage(result: _resultTable));
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      // 手機上一頁 10 筆幾乎沒用
      expect(ais.posts.single[r'PC$PageSize'], '100');

      expect(find.text('2 筆'), findsOneWidget);
      expect(find.text('科目名稱'), findsOneWidget);
      expect(find.text('演算法'), findsOneWidget);
      expect(find.text('王小明'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('「查無符合資料」不會被當成錯誤', (tester) async {
      script(onQuery: _queryPage(result: '<span>查無符合資料</span>'));
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      // 空結果就是空結果 —— 不出現錯誤，也不畫出一張空表格
      expect(find.textContaining('錯誤'), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      await unmount(tester);
    });

    testWidgets('解不出表格時不當機、也不假裝有結果', (tester) async {
      // Crystal Reports 之類的輸出：有回應，但不是我們認得的表格
      script(
        onQuery: _queryPage(result: '<iframe src="CrystalReportViewer.aspx">'),
      );
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('錯誤'), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      await unmount(tester);
    });

    testWidgets('查詢失敗的紅框，下一次查成功之後要消失', (tester) async {
      var broken = true;
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN')) {
          return broken ? _kickedToLogin : _queryPage(result: _resultTable);
        }
        return _queryPage();
      };
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();
      expect(find.text('登入逾時了，請重新登入。'), findsOneWidget);

      broken = false;
      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      expect(find.text('登入逾時了，請重新登入。'), findsNothing);
      expect(find.text('演算法'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('翻頁', () {
    void paged() =>
        script(onQuery: _queryPage(result: '$_resultTable$_pagerRow'));

    testWidgets('總頁數讀自「跳到最後」那顆，不是從顯示的頁碼猜的', (tester) async {
      paged();
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      expect(find.text('2 筆（第 1 / 3 頁）'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('下一頁重按的是當初那一顆查詢鈕，並帶著頁碼', (tester) async {
      paged();
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      final sent = ais.posts.last;
      expect(sent[r'PC$PageNo'], '2');
      expect(sent.pressed('QUERY_BTN'), isTrue);
      await unmount(tester);
    });

    testWidgets('第一頁不能再往前', (tester) async {
      paged();
      await open(tester);

      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      final back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(back.onPressed, isNull);
      await unmount(tester);
    });
  });

  group('分頁式的功能頁', () {
    void tabbed() {
      ais.reply = (r) => _isDispatcher(r) ? _dispatcher : _tabbedPage;
    }

    testWidgets('一次只顯示一組條件，不把好幾顆「查詢」攤在同一畫面', (tester) async {
      tabbed();
      await open(tester);

      expect(find.widgetWithText(ChoiceChip, '單位查詢'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '教師查詢'), findsOneWidget);

      // 第一組的欄位看得到，第二組的看不到
      expect(find.text('開課單位'), findsOneWidget);
      expect(find.text('教師姓名'), findsNothing);
      expect(queryButton(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('切到第二組送出的是那一組的 0-based 索引', (tester) async {
      tabbed();
      await open(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '教師查詢'));
      await tester.pumpAndSettle();

      expect(find.text('教師姓名'), findsOneWidget);
      await tester.tap(queryButton());
      await tester.pumpAndSettle();

      final sent = ais.posts.single;
      // 頁面上的容器是 tabs-2（1-based），送出去要減一 ——
      // 差一個就會拿別組的空欄位去查，而回應是「查無符合資料」，
      // 看起來像沒資料，其實是問錯了問題。
      expect(sent['hdnSelectedTab'], '1');
      expect(sent.pressed('QUERY_BTN2'), isTrue);
      expect(sent.pressed('QUERY_BTN1'), isFalse);
      await unmount(tester);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/data/function_view.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/parsing/data_grid.dart';
import 'package:ntou_app/src/parsing/startup_postback.dart';

import 'fake_ais.dart';
import 'fixtures.dart';

/// 有些功能頁的 HTML 是**空殼** —— 內容是頁面載入之後自己發一發
/// `__doPostBack('ReQuery','')`（UpdatePanel）才補回來的。App 不跑 JS，
/// 所以拿到的永遠是那份空殼。
///
/// **而空殼跟「這個帳號沒有資料」長得一模一樣**：欄位齊全、統計全空、零筆、
/// 狀態碼 200、沒有任何錯誤。這個 repo 2026-09-07 就是這樣誤判成績單的，
/// 結論還寫進了 README，卡了九天。
///
/// 這一組測試釘的是兩件事：認得出該補的那一發、以及**不要認錯**。
/// 認錯的代價很具體 —— 成績頁剛好兩個同名所以看不出來，
/// 但別的頁面上那顆可能是「刪除」。

/// 真實長相（`GRD5010_02`，2026-09-16 抓的那一份殼）。
///
/// 那一發夾在頁尾一長串設定中間，前後都是 `try{...}catch(ex){}` ——
/// 括號硬數的話這些都會被算進去，所以照抄那個形狀。
const _startupScript = '<script type="text/javascript">'
    '//<![CDATA[\n'
    "var lang='ZH_TW';"
    'try{if(getTop().columnFilterRecord==null)getTop().columnFilterRecord={};}'
    'catch(ex){};'
    "var recordName1='GRD5010_02';"
    "Message.showProcess();;__doPostBack('ReQuery','');;"
    'try{setButtonEvent();reSize();}catch(ex){};'
    '\n//]]></script>';

/// 點了才跑的那一顆。**在 HTML 裡，不在 `<script>` 裡。**
const _reQueryAnchor =
    '<a id="ReQuery" href="javascript:__doPostBack(\'ReQuery\',\'\')">重新查詢</a>';

/// 呼叫了才跑的那些。深度 > 0，而且**其中一顆是刪除**。
const _validationScripts = '<script>\n'
    'function doQuery() {\n'
    '  if (_i(0, "Q_AYEARSMS").value=="") {\n'
    '    alert("學期成績-學年期不可為空白!");\n'
    '    return false;\n'
    '  }\n'
    "  __doPostBack('QUERY_BTN1','');\n"
    '}\n'
    "function doDel() { __doPostBack('DEL_BTN1',''); }\n"
    '</script>';

/// 派發器：選單上的路徑 GET 完只有這個空殼。
const _dispatcher = r"""<html><body>
<script>top.mainFrame.location.href='GRD5010_01.aspx';</script>
</body></html>""";

/// 查詢表單。[viewState] 要看得出是哪一頁送出去的 ——
/// 補送那一發如果拿錯頁面的 `__VIEWSTATE`，學校回的是一頁空的，而且不報錯。
String _page({String viewState = 'vs_form', String extra = ''}) =>
    '<html><head><title>GRD5010_查詢各式成績</title></head><body><form>'
    '<input type="hidden" name="__VIEWSTATE" value="$viewState">'
    '<input type="text" name="Q_AYEARSMS" cname="學年期" value="1151">'
    '<input type="submit" name="QUERY_BTN1" ml="CB_查詢" value="查詢">'
    '</form>$extra</body></html>';

/// `ReQuery` 之後才長出來的那張表。
const _resultTable = '<table id="DataGrid">'
    '<tr><th>學年期</th><th>課程名稱</th><th>學期總成績</th></tr>'
    '<tr><td>1151</td><td>程式設計</td><td>85</td></tr>'
    '<tr><td>1151</td><td>微積分</td><td>78</td></tr>'
    '</table>';

const _fn = AisFunction(
  title: '查詢各式成績',
  path: 'Application/GRD/GRD50/GRD5010_.aspx?progcd=x',
  trail: ['教務系統', '成績系統', '查詢各式成績'],
);

bool _isDispatcher(FakeRequest r) => r.page.startsWith('GRD5010_.aspx');
bool _isReQuery(FakeRequest r) => r['__EVENTTARGET'] == 'ReQuery';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('認得出頁面自己發的那一發', () {
    test('`<script>` 頂層的算 —— 那是載入時就會跑掉的', () {
      final got = startupPostback('<html><body>${_page(extra: _startupScript)}');
      expect(got?.target, 'ReQuery');
      expect(got?.argument, '');
    });

    test('**`<a href="javascript:__doPostBack(...)">` 不算**', () {
      // 那一顆要使用者點才跑。成績頁上它剛好也叫 ReQuery，所以抓錯了
      // 看不出來 —— 但規則錯了就是錯了。
      expect(startupPostback(_page(extra: _reQueryAnchor)), isNull);
    });

    test('**包在函式裡的不算 —— 其中一顆是刪除**', () {
      expect(startupPostback(_page(extra: _validationScripts)), isNull);
    });

    test('連動下拉那種跳脫過的引號也不算', () {
      // onchange 裡是 `setTimeout('__doPostBack(\'Q_X\',\'\')', 0)`，
      // 使用者改了那一格才跑。就算它被寫進 <script> 裡也一樣。
      const html = '<script>'
          r"""setTimeout('__doPostBack(\'Q_DEGREE_CODE\',\'\')', 0);"""
          '</script>';
      expect(startupPostback(html), isNull);
    });

    test('同一段裡：頂層的算，函式裡的不算', () {
      const html = '<script>'
          "function doDel(){ __doPostBack('DEL_BTN1',''); }"
          "Message.showProcess();;__doPostBack('ReQuery','');;"
          '</script>';
      expect(startupPostback(html)?.target, 'ReQuery');
    });

    test('沒有就回 null —— 不要憑空送一發出去', () {
      expect(startupPostback(_page()), isNull);
      expect(startupPostback('<html><body>一般頁面</body></html>'), isNull);
      // ASP.NET 自己那個函式定義沒有引號，不是一發呼叫
      expect(
        startupPostback(
          '<script>function __doPostBack(eventTarget, eventArgument) { }</script>',
        ),
        isNull,
      );
    });
  });

  group('真實頁面', () {
    const shell = 'Application_GRD_GRD50_GRD5010_02__QUERY_BTN1_1141.html';
    const filled = 'Application_GRD_GRD50_GRD5010_02__QUERY_BTN1_1151.html';

    test('成績單空殼：認得出它還缺那一發', () {
      final html = fixture(shell);
      // 一張表都沒有 —— 而畫面上這跟「你沒有成績」一模一樣
      expect(parseDataGrid(html).rows, isEmpty, reason: '這一份本來就該是空的');
      expect(startupPostback(html)?.target, 'ReQuery');
    }, skip: skipUnless(shell));

    test('補完的那一份不該再認出一發 —— 不然會一直繞', () {
      final html = fixture(filled);
      expect(startupPostback(html), isNull);

      // 同一個帳號、同一個網址，補送之後是有資料的 ——
      // 「空殼」跟「沒有資料」是兩件事，這一組 fixture 就是證據。
      final grid = parseDataGrid(html);
      expect(grid.rows, isNotEmpty);
      expect(grid.columns, contains('學期總成績'));
    }, skip: skipUnless(filled));

    test('一般的功能頁一發都不該認出來', () {
      // 誤報的防線。這些頁面上全是「點了才跑」和「呼叫了才跑」的
      // `__doPostBack`（翻頁、刪除、連動下拉），規則放寬一點就會在這裡冒出來
      // —— 而多送出去的那一發是真的會執行的。
      for (final f in [
        'Application_GRD_GRD50_GRD5010_01.html',
        'Application_GRD_GRD50_GRD5010_01__QUERY_BTN1_1151.html',
        'Application_GRD_GRD70_GRD7050_01__QUERY_BTN1.html',
        'Application_TKE_TKE20_TKE2040_01.html',
        'Application_ENR_ENRG0_ENRG010_01.html',
        'Portal.html',
      ]) {
        if (skipUnless(f) != null) continue;
        expect(startupPostback(fixture(f)), isNull, reason: f);
      }
    }, skip: skipUnless('Application_GRD_GRD50_GRD5010_01.html'));
  });

  group('查詢回來是空殼時會自己補一發', () {
    late ScriptedAis ais;
    late AisRepository repo;

    // session 要在這裡建好：`beginLogin()` 是真的走一次請求。
    setUp(() async {
      ais = ScriptedAis();
      repo = await loggedInRepository(ais);
    });

    Future<FunctionView> query() async =>
        repo.runQuery(await repo.openFunction(_fn), 'QUERY_BTN1');

    test('**頂層那一發要補送，而且解得到補回來的表格**', () async {
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (_isReQuery(r)) return _page(extra: _resultTable);
        // 按下查詢回來的是空殼：欄位齊全、零筆、沒有任何錯誤
        if (r.pressed('QUERY_BTN1')) {
          return _page(viewState: 'vs_shell', extra: _startupScript);
        }
        return _page();
      };

      final view = await query();

      final reQuery = ais.posts.where(_isReQuery).toList();
      expect(reQuery, hasLength(1), reason: '沒補送的話，畫面上就是「查無資料」');
      // 要用**空殼那一頁**的 __VIEWSTATE 送。拿錯頁面的話學校回一頁空的，
      // 而且不報錯 —— 症狀跟沒補送一模一樣。
      expect(reQuery.single['__VIEWSTATE'], 'vs_shell');

      expect(view.result?.rows, hasLength(2));
      expect(view.result?.columns, contains('學期總成績'));
      expect(view.result?.rows.first, contains('程式設計'));
    });

    test('補回來還是空殼的話就停手，不要一直繞', () async {
      // 每一圈都是一次打在學校機器上的請求，而且繞不出結果。
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1') || _isReQuery(r)) {
          return _page(extra: _startupScript);
        }
        return _page();
      };

      await query();

      expect(ais.posts.where(_isReQuery), hasLength(1));
    });

    test('**已經有結果的頁面不補送** —— 那是白白多打一次', () async {
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) {
          // 有表格，同時頁尾照樣掛著那一發（翻頁用的）
          return _page(extra: '$_resultTable$_startupScript');
        }
        return _page();
      };

      final view = await query();

      expect(ais.posts, hasLength(1), reason: '查詢那一發之外不該再有請求');
      expect(ais.posts.where(_isReQuery), isEmpty);
      expect(view.result?.rows, hasLength(2));
    });

    test('包在函式裡的不補送', () async {
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) return _page(extra: _validationScripts);
        return _page();
      };

      await query();

      expect(ais.posts, hasLength(1));
      // 這一頁的 doDel 送出去是會**刪掉東西**的
      expect(
        ais.posts.where((r) => r['__EVENTTARGET'] == 'DEL_BTN1'),
        isEmpty,
      );
    });

    test('`<a href="javascript:…">` 那一顆不補送', () async {
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) return _page(extra: _reQueryAnchor);
        return _page();
      };

      await query();

      expect(ais.posts, hasLength(1));
      expect(ais.posts.where(_isReQuery), isEmpty);
    });

    test('查無符合資料還是查無符合資料 —— 沒有那一發就不要多送', () async {
      // 學校明確說了沒有資料的頁面上沒有那一發，所以這條路不受影響。
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) {
          return _page(extra: '<span>查無符合資料!!</span>');
        }
        return _page();
      };

      final view = await query();

      expect(ais.posts, hasLength(1));
      expect(view.result?.isEmpty, isTrue);
    });
  });
}

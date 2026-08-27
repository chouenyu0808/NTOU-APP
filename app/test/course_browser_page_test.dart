import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/parsing/timetable.dart';
import 'package:ntou_app/src/planner/plan_models.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/course_browser_page.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';
import 'fixtures.dart';

/// 連動下拉的 `onchange`。
///
/// 照抄真頁面的形狀：引號是 HTML 實體 `&#39;`，外面再包一層反斜線跳脫。
/// `autoPostBackFields` 刻意走 DOM 而不是對原始 HTML 下正則，就是為了認得它。
const _cascadeOnChange = r"""onchange="javascript:setTimeout('__doPostBack(\&#39;Q_DEGREE_CODE\&#39;,\&#39;\&#39;)', 0)" """;

/// 這一頁最前面那段表單驗證的 JS。
///
/// **「上課時間」四個字就寫在裡面**（`case "5"` 是「上課時間查詢」那個標籤頁）。
/// 抓上課時間如果直接對原始 HTML `indexOf('上課時間')`，撞到的永遠是這裡。
const _validationScript = '<script>switch (t) { case "5": //上課時間\n'
    'if (_i(0, "Q_WEEK").value == "") { errAppend("上課時間-星期"); }\n'
    'if (_i(0, "Q_CLASS").value == "") { errAppend("上課時間-節次"); } }</script>';

/// 選單上的路徑是派發器，GET 完只有這個空殼，真正的表單在它導向的那一頁。
const _dispatcher = r"""<html><body>
<script>top.mainFrame.location.href='TKE2211_01.aspx';</script>
</body></html>""";

/// `DataGrid$ctl02$COSID` —— ASP.NET 依列數編的 id，不是可以自己組的。
String _target(String row) => 'DataGrid\$$row\$COSID';

/// 查詢結果裡「課號」那一格。
///
/// **引號是 `&#39;` 不是 `'`** —— 真頁面就長這樣（見
/// `spike/fixtures/…TKE2211_01__QUERY_BTN1_0_0507.html`）。
/// 這正是「拿正則去比原始 HTML」一列都對不到的原因。
String _codeLink(String row, String code) =>
    '<a id="DataGrid_${row}_COSID" class="pathLink" '
    'href="javascript:__doPostBack(&#39;${_target(row)}&#39;,&#39;&#39;)">'
    '$code</a>';

/// 課程課表查詢頁（只留這個 App 用得到的兩個標籤頁）。
String _searchPage({String facultyOptions = '', String result = ''}) =>
    '<html><head><title>TKE2211_課程課表查詢</title></head><body>'
    '$_validationScript'
    '<form>'
    r'<input type="hidden" name="__VIEWSTATE" value="vs">'
    r'<input type="hidden" name="PC$PageSize" value="10">'
    r'<input type="hidden" name="PC$PageNo" value="1">'
    r'<input type="hidden" name="hdnSelectedTab" value="0">'
    '<ul><li><a href="#tabs-1">單位查詢</a></li>'
    '<li><a href="#tabs-2">關鍵字查詢</a></li></ul>'
    '<div id="tabs-1">'
    '<select name="Q_DEGREE_CODE" cname="部別" $_cascadeOnChange>'
    '<option value="">請選擇</option><option value="B">學士班</option>'
    '</select>'
    // 一開始 0 個選項：要先選部別、連動 postback 之後伺服器才會填。
    '<select name="Q_FACULTY_CODE" cname="系所">$facultyOptions</select>'
    '<select name="Q_GRADE" cname="年級">'
    '<option value="">全部</option><option value="1">一年級</option>'
    '</select>'
    '<select name="Q_CLASSID" cname="班別">'
    '<option value="">全部</option><option value="A">A班</option>'
    '</select>'
    r"""<input type="submit" name="QUERY_BTN1" value="查詢" ml="CB_查詢" onclick="return doQuery(&#39;1&#39;);">"""
    '</div>'
    '<div id="tabs-2">'
    r'<input type="text" name="Q_CH_LESSON" cname="課程名稱" value="">'
    r"""<input type="submit" name="QUERY_BTN7" value="查詢" ml="CB_查詢" onclick="return doQuery(&#39;2&#39;);">"""
    '</div>'
    '</form>$result</body></html>';

const _facultyOptions =
    '<option value="">請選擇</option><option value="CS">資訊工程學系</option>';

/// 查詢結果。**17 欄裡沒有上課時間那一欄** —— 這就是為什麼要再點進詳細頁。
String _resultTable() => '<table id="DataGrid">'
    '<tr><th>序號</th><th>課號</th><th>課名</th><th>開課單位</th>'
    '<th>年級班別</th><th>授課老師</th><th>學分</th><th>選別</th></tr>'
    '<tr><td>0001</td><td>${_codeLink('ctl02', 'B57011RQ')}</td>'
    '<td>計算機概論</td><td>資訊工程學系</td><td>1年A班</td><td>許小明</td>'
    '<td>3</td><td>A</td></tr>'
    '<tr><td>0002</td><td>${_codeLink('ctl03', 'B57012RQ')}</td>'
    '<td>離散數學</td><td>資訊工程學系</td><td>1年A班</td><td>李小華</td>'
    '<td>3</td><td>A</td></tr>'
    '</table>';

/// 課程內容頁（`TKE2240_03.aspx`），照真實頁面的形狀。
///
/// 上課時間在一個有 id 的 span 裡，而**隔壁的上課地點是 `INS105,INS105,INS105`**
/// —— `INS105` 裡的 105 是合法的時間代碼（週一第 5 節）。掃文字會多排一節課出來。
String _detailPage(String codes) =>
    '<html><head><title>TKE2240_03 課程內容</title></head><body>'
    '$_validationScript'
    '<div><span ml="PL_課號">課號</span></div>'
    '<div><span id="M_COSID" cname="課號">B57011RQ</span></div>'
    '<div><span ml="PL_上課時間">上課時間</span></div>'
    '<div><span id="M_SEG" class="form-label" cname="時間">$codes</span></div>'
    '<div><span ml="PL_上課地點">上課地點</span></div>'
    '<div><span id="M_CLSSRM_ID" cname="教室代號">INS105,INS105,INS105</span>'
    '</div></body></html>';

/// 點課號的 postback 回應。
///
/// **跟查詢結果頁幾乎一模一樣，只多注入這一行。** 真實資料裡整份 HTML 只差
/// 3 個 byte（`Message.hideProcess()` 換成 `fn_open(...)`）。
const _fnOpenResponse = '<html><body>'
    "<script>fn_open('137171415','1');</script>"
    '</body></html>';

/// 被踢回登入頁 —— 狀態碼一樣是 200，只能靠指紋認出來。
const _kickedToLogin =
    '<html><body><input name="M_PORTAL_LOGIN_ACNT"><input name="LoginPWD">'
    '</body></html>';

bool _isDispatcher(FakeRequest r) => r.page.startsWith('TKE2211_.aspx');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedAis ais;
  late AppController controller;
  late PlanStore store;

  // session 要在 setUp 裡建好：`testWidgets` 的 body 跑在 fake async 裡，
  // 在那裡面 await 一次真正的請求會停住不動。
  setUp(() async {
    ais = ScriptedAis();
    controller = await loggedInController(ais);
    // 加入預排要有學年學期才知道要寫哪一份計畫。
    controller.year = '114';
    controller.semester = '1';
    store = PlanStore(prefs: await SharedPreferences.getInstance());
  });

  /// 派發器 -> 表單；關鍵字查詢回 [onKeyword]；系所查詢回 [onFaculty]；
  /// 連動回填好系所選項的表單。
  void script({
    String? onKeyword,
    String? onFaculty,
    String? onDetail,
    String facultyOptions = '',
  }) {
    ais.reply = (r) {
      if (_isDispatcher(r)) return _dispatcher;
      if (r.cascaded('Q_DEGREE_CODE')) {
        return _searchPage(facultyOptions: facultyOptions);
      }
      // 點課號不換頁，只回一行 fn_open；內容在它指的那一頁。
      if (onDetail != null && r['__EVENTTARGET'] == _target('ctl02')) {
        return _fnOpenResponse;
      }
      if (onDetail != null && r.page.startsWith('TKE2240_03.aspx')) {
        return onDetail;
      }
      if (onKeyword != null && r.pressed('QUERY_BTN7')) return onKeyword;
      if (onFaculty != null && r.pressed('QUERY_BTN1')) return onFaculty;
      // 第一次打開時系所是空的 —— 選項要連動 postback 之後伺服器才會填。
      return _searchPage();
    };
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: CourseBrowserPage(controller: controller, planStore: store),
    ));
    await tester.pumpAndSettle();
  }

  /// 切到「系所瀏覽」那一頁。`TabBarView` 只建目前這一頁，不切過去就沒有下拉。
  Future<void> openFacultyTab(WidgetTester tester) async {
    await tester.tap(find.text('系所瀏覽'));
    await tester.pumpAndSettle();
  }

  Future<void> searchByKeyword(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField), keyword);
    await tester.tap(find.widgetWithText(FilledButton, '搜尋'));
    await tester.pumpAndSettle();
  }

  Finder dropdown(int index) =>
      find.byType(DropdownButtonFormField<String>).at(index);

  /// 下拉「真正選中」的值。
  ///
  /// 不能用 `find.text` 判斷：關起來的 `DropdownButton` 是把每一個選項都放進
  /// `IndexedStack`，只顯示其中一個 —— 沒選中的那些文字也都還在 widget 樹裡。
  String? selectedValue(WidgetTester tester, int index) =>
      tester.state<FormFieldState<String>>(dropdown(index)).value;

  Future<CoursePlan?> readPlan() => store.read('114', '1');

  group('開啟課程查詢頁', () {
    testWidgets('跟完派發器的 JS 導向才拿得到查詢表單', (tester) async {
      script();
      await open(tester);

      // 直接 GET 派發器只會拿到空殼，要跟著 JS 導向再抓一次。
      expect(
        ais.seen.map((r) => r.page).toList(),
        ['TKE2211_.aspx', 'TKE2211_01.aspx'],
      );
      expect(find.text('課名搜尋'), findsOneWidget);
      expect(find.text('系所瀏覽'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('標題說清楚這些課要加到哪一個學期', (tester) async {
      script();
      await open(tester);

      expect(find.text('加入至：114 學年第 1 學期'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('還沒查之前不顯示「查無資料」，那是兩件事', (tester) async {
      script();
      await open(tester);

      expect(find.textContaining('請設定條件並按下查詢'), findsOneWidget);
      expect(find.text('查無符合資料'), findsNothing);
      await unmount(tester);
    });

    testWidgets('被踢回登入頁時說的是「重新登入」，而且重試會重開整頁', (tester) async {
      var kicked = true;
      ais.reply = (r) {
        if (_isDispatcher(r)) return kicked ? _kickedToLogin : _dispatcher;
        return _searchPage();
      };
      await open(tester);

      expect(find.text('登入逾時了，請重新登入。'), findsOneWidget);
      expect(find.text('課名搜尋'), findsOneWidget); // TabBar 還在，只是內容換成錯誤

      kicked = false;
      await tester.tap(find.widgetWithText(OutlinedButton, '重試'));
      await tester.pumpAndSettle();

      expect(find.text('登入逾時了，請重新登入。'), findsNothing);
      expect(find.textContaining('請設定條件並按下查詢'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('課名搜尋', () {
    testWidgets('送出的是關鍵字那一組的按鈕、欄位和標籤索引', (tester) async {
      script(onKeyword: _searchPage(result: _resultTable()));
      await open(tester);
      await searchByKeyword(tester, '計算機');

      final sent = ais.posts.single;
      expect(sent.pressed('QUERY_BTN7'), isTrue);

      // 頁面預設是「類別=課號(0)、查詢模式=精準(0)」——
      // 照預設送等於拿課名去比對課號、而且要完全相同。
      // 「微積分」永遠比不到「微積分(一)」，畫面上看起來就像這門課不存在。
      expect(sent['radioButtonClass'], '1', reason: '要用課名查，不是課號');
      expect(sent['radioButtonQuery'], '1', reason: '要模糊比對，不是精準');
      expect(sent.pressed('QUERY_BTN1'), isFalse);
      expect(sent['Q_CH_LESSON'], '計算機');
      // 關鍵字查詢是頁面上的第二個標籤頁（tabs-2），送出去要減一。
      expect(sent['hdnSelectedTab'], '1');
      // 手機上一頁 10 筆幾乎沒用
      expect(sent[r'PC$PageSize'], '100');
      await unmount(tester);
    });

    testWidgets('結果照學校表格的課名、老師、學分畫成清單', (tester) async {
      script(onKeyword: _searchPage(result: _resultTable()));
      await open(tester);
      await searchByKeyword(tester, '計算機');

      expect(find.text('計算機概論'), findsOneWidget);
      expect(find.text('離散數學'), findsOneWidget);
      expect(find.text('許小明 • 3.0學分 • 1年A班'), findsOneWidget);
      expect(find.text('李小華 • 3.0學分 • 1年A班'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('關鍵字空白時不送出任何請求', (tester) async {
      script(onKeyword: _searchPage(result: _resultTable()));
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, '搜尋'));
      await tester.pumpAndSettle();

      expect(ais.posts, isEmpty);
      await unmount(tester);
    });

    testWidgets('「查無符合資料」是查詢結果，不是錯誤', (tester) async {
      script(onKeyword: _searchPage(result: '<span>查無符合資料</span>'));
      await open(tester);
      await searchByKeyword(tester, '不存在的課');

      expect(find.text('查無符合資料'), findsOneWidget);
      expect(find.textContaining('請設定條件並按下查詢'), findsNothing);
      await unmount(tester);
    });

    testWidgets('查詢途中 session 掉了，顯示的是重新登入而不是空清單', (tester) async {
      script(onKeyword: _kickedToLogin);
      await open(tester);
      await searchByKeyword(tester, '計算機');

      expect(find.text('登入逾時了，請重新登入。'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('系所連動選單', () {
    testWidgets('四個條件都畫得出來，系所一開始是不能選的', (tester) async {
      script();
      await open(tester);
      await openFacultyTab(tester);

      expect(find.text('部別'), findsOneWidget);
      expect(find.text('系所'), findsOneWidget);
      expect(find.text('年級'), findsOneWidget);
      expect(find.text('班別'), findsOneWidget);

      // 0 個選項的下拉送出去會踩 event validation，所以直接不讓人碰。
      final faculty = tester.widget<DropdownButtonFormField<String>>(dropdown(1));
      expect(faculty.onChanged, isNull);
      await unmount(tester);
    });

    testWidgets('改部別會發連動 postback，而且不送 0 個選項的系所', (tester) async {
      script(facultyOptions: _facultyOptions);
      await open(tester);
      await openFacultyTab(tester);

      await tester.tap(dropdown(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('學士班').last);
      await tester.pumpAndSettle();

      final sent = ais.posts.single;
      // __doPostBack 靠 __EVENTTARGET 說是誰觸發的，**不送任何按鈕的 name**。
      expect(sent.cascaded('Q_DEGREE_CODE'), isTrue);
      expect(sent.pressed('QUERY_BTN1'), isFalse);
      expect(sent['Q_DEGREE_CODE'], 'B');
      expect(sent.form.containsKey('Q_FACULTY_CODE'), isFalse);
      await unmount(tester);
    });

    testWidgets('連動回來之後，部別停在剛剛選的、系所變成選得動的', (tester) async {
      script(facultyOptions: _facultyOptions);
      await open(tester);
      await openFacultyTab(tester);

      await tester.tap(dropdown(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('學士班').last);
      await tester.pumpAndSettle();

      // `DropdownButtonFormField` 的值是 **initialValue**（`value` 已經棄用）。
      // 名字聽起來像「只在第一次有效」，但 didUpdateWidget 會比對新舊值再套用 ——
      // 這個斷言就是在盯這件事：連動回來之後畫面不能停在舊選項。
      expect(selectedValue(tester, 0), 'B');

      final faculty = tester.widget<DropdownButtonFormField<String>>(dropdown(1));
      expect(faculty.onChanged, isNotNull);
      await unmount(tester);
    });

    testWidgets('選了系所之後查詢，送的是單位查詢那一組', (tester) async {
      script(
        facultyOptions: _facultyOptions,
        onFaculty: _searchPage(
          facultyOptions: _facultyOptions,
          result: _resultTable(),
        ),
      );
      await open(tester);
      await openFacultyTab(tester);

      await tester.tap(dropdown(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('學士班').last);
      await tester.pumpAndSettle();

      await tester.tap(dropdown(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('資訊工程學系').last);
      await tester.pumpAndSettle();

      // 系所不是連動欄位，選了不該多送一次 postback。
      expect(ais.posts.length, 1);
      expect(selectedValue(tester, 1), 'CS');

      await tester.tap(find.widgetWithText(FilledButton, '查詢此系所課程'));
      await tester.pumpAndSettle();

      final sent = ais.posts.last;
      expect(sent.pressed('QUERY_BTN1'), isTrue);
      expect(sent['Q_DEGREE_CODE'], 'B');
      expect(sent['Q_FACULTY_CODE'], 'CS');
      // 單位查詢是第一個標籤頁（tabs-1），0-based 是 0。
      expect(sent['hdnSelectedTab'], '0');

      expect(find.text('計算機概論'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('加入預排時自動抓上課時間', () {
    Future<void> addFirstCourse(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
    }

    testWidgets('點的是那一列課號自己的 __doPostBack 目標', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('102 103 104'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      // 頁面上的引號是 `&#39;`，所以這個目標只有走 DOM 才讀得出來。
      final sent = ais.posts.last;
      expect(sent['__EVENTTARGET'], _target('ctl02'));
      // 是 postback 不是按鈕：按鈕的 name 一個都不能送。
      expect(sent.pressed('QUERY_BTN7'), isFalse);
      await unmount(tester);
    });

    testWidgets('「102 103 104」是週一第 2、3、4 節，而且寫進預排的時段', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('102 103 104'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      final planned = (await readPlan())!.courses.single;
      expect(planned.course.name, '計算機概論');
      // 代碼的第一碼 1 是週一，TimeSlot.weekday 是 0 起算的 ——
      // 少減這一格，整張課表會整個往後挪一天，而且畫面上看不出來。
      expect(planned.slots, const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
      await unmount(tester);
    });

    testWidgets('抓到的時段要放在預排頁看得到的地方', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('102 103 104'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      final plan = (await readPlan())!;
      // 預排頁的格子、衝堂檢查、「未填時段」的統計看的都是 PlannedCourse.slots。
      // 只寫進 Course.slots 的話：抓到了，但畫面上跟沒抓到一模一樣。
      expect(plan.missingSlotCount, 0);
      expect(plan.asCourses().single.slots, hasLength(3));
      await unmount(tester);
    });

    testWidgets('跨天的代碼各自對到自己的星期', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('203 204 511'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      expect((await readPlan())!.courses.single.slots, const [
        TimeSlot(1, 3),
        TimeSlot(1, 4),
        TimeSlot(4, 11),
      ]);
      await unmount(tester);
    });

    testWidgets('點課號不換頁 —— 要跟著 fn_open 再抓一次才拿得到時間', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('102,103,104'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      // postback 之後一定要再 GET 一次課程內容頁，而且要帶著 fn_open 給的 PKNO
      final detail = ais.seen.where(
        (r) => r.page.startsWith('TKE2240_03.aspx'),
      );
      expect(detail, hasLength(1),
          reason: '停在 postback 的回應上是抓不到上課時間的');
      expect(detail.single.url.queryParameters['PKNO'], '137171415');
      expect(detail.single.url.queryParameters['LESSON_TYPE'], '1');
      expect(detail.single.method, 'GET');

      expect((await readPlan())!.courses.single.slots, hasLength(3));
      await unmount(tester);
    });

    testWidgets('上課地點裡的數字不能被當成上課時間', (tester) async {
      // 真實資料：上課時間 102,103,104；上課地點 INS105,INS105,INS105。
      // 掃文字的話 INS105 的 105 會變成「週一第 5 節」，憑空多一節課。
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('102,103,104'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      expect((await readPlan())!.courses.single.slots, const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
      await unmount(tester);
    });

    testWidgets('抓不到上課時間也要加得進去，並提醒回去手動填', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: '<html><body><p>這一頁沒有時間</p></body></html>',
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      final planned = (await readPlan())!.courses.single;
      expect(planned.course.name, '計算機概論');
      expect(planned.slots, isEmpty);
      expect(find.textContaining('請記得回預排頁面填入上課時段'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('抓時間失敗不該讓「加入預排」跟著失敗', (tester) async {
      // 詳細頁那一步被踢回登入頁 —— 課還是要加得進去。
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _kickedToLogin,
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      expect((await readPlan())!.courses, hasLength(1));
      // 查詢結果也不能被錯誤畫面蓋掉
      expect(find.text('計算機概論'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('同一門課不會重複加入，也不會白跑一次詳細頁', (tester) async {
      script(
        onKeyword: _searchPage(result: _resultTable()),
        onDetail: _detailPage('102 103 104'),
      );
      await open(tester);
      await searchByKeyword(tester, '計算機');
      await addFirstCourse(tester);

      // 上一則 SnackBar 還在的話，第二則會被排隊排到後面而看不到。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final before = ais.posts.length;
      await addFirstCourse(tester);

      expect(find.text('這門課已經在預排清單中了'), findsOneWidget);
      expect((await readPlan())!.courses, hasLength(1));
      expect(ais.posts.length, before);
      await unmount(tester);
    });
  });

  group('上課時間代碼', () {
    test('第一碼是星期（1 = 週一），TimeSlot.weekday 從 0 起算', () {
      expect(parseTimeCodes('102 103 104'), const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
      expect(parseTimeCodes('700'), const [TimeSlot(6, 0)]);
      expect(parseTimeCodes('516'), const [TimeSlot(4, 16)]);
    });

    test('分隔符號和重複都吃得下，輸出是排好序的', () {
      expect(parseTimeCodes('104,102、103 102'), const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
    });

    test('不是代碼的數字一律不算', () {
      // 星期只到 7、節次只到 16；前後接著數字的也不是（1102 不是 110）
      expect(parseTimeCodes('802 017 117 1102'), isEmpty);
    });

    test('「上課時間」寫在 JS 註解裡不算數', () {
      // 這是原本的寫法會踩到的坑：整份 HTML 最前面就有 case "5": //上課時間
      expect(parseCourseTimeSlots('<html><body>$_validationScript'
          '<p>這門課沒有排時間</p></body></html>'), isEmpty);
    });

    test('只讀標籤隔壁那一格，不會把教室代碼當成上課時間', () {
      // 綜一301 就排在上課時間隔壁，301 長得跟代碼一模一樣
      expect(parseCourseTimeSlots(_detailPage('102 103 104')), const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
    });

    test('標籤和值擠在同一格也讀得出來', () {
      expect(
        parseCourseTimeSlots(
          '<html><body><td>上課時間：102 103 上課教室 綜一301</td></body></html>',
        ),
        const [TimeSlot(0, 2), TimeSlot(0, 3)],
      );
    });

    test('沒有標籤時只認連在一起的一串，單獨一個三位數不算', () {
      expect(
        parseCourseTimeSlots('<html><body><p>週一 102 103</p></body></html>'),
        const [TimeSlot(0, 2), TimeSlot(0, 3)],
      );
      expect(
        parseCourseTimeSlots('<html><body><p>教室 綜一301</p></body></html>'),
        isEmpty,
      );
    });

    test('相鄰兩格的數字不會黏成一串而漏掉代碼', () {
      // <td>65</td><td>102 103</td> 直接取 text 會變成「65102 103」
      expect(
        parseCourseTimeSlots(
          '<html><body><table><tr><td>65</td><td>102 103</td></tr>'
          '</table></body></html>',
        ),
        const [TimeSlot(0, 2), TimeSlot(0, 3)],
      );
    });
  });

  group('必修 / 選修', () {
    testWidgets('結果清單上標出選別', (tester) async {
      // 查詢結果的「選別」欄只有代碼（A / B），頁面上沒有對照表 ——
      // 對照放在 selectors.json，A = 必修、B = 選修。
      script(onKeyword: _searchPage(result: _resultTable()));
      await open(tester);
      await searchByKeyword(tester, '計算機');

      expect(find.text('必修'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('認不得的代碼原樣顯示，不要猜', (tester) async {
      // 猜錯比不翻譯更糟：使用者看到「選修」會照著排課，
      // 看到「Z」至少知道要自己去查。
      const table = '<table id="DataGrid">'
          '<tr><th>課號</th><th>課名</th><th>年級班別</th>'
          '<th>授課老師</th><th>學分</th><th>選別</th></tr>'
          '<tr><td>X1</td><td>某課</td><td>1年A班</td>'
          '<td>某師</td><td>3</td><td>Z</td></tr>'
          '</table>';
      script(onKeyword: _searchPage(result: table));
      await open(tester);
      await searchByKeyword(tester, '某');

      expect(find.text('Z'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('課號連結的 postback 目標', () {
    test('引號是 HTML 實體也讀得出來', () {
      expect(courseDetailTarget(_resultTable(), 'B57011RQ'), _target('ctl02'));
      expect(courseDetailTarget(_resultTable(), 'B57012RQ'), _target('ctl03'));
    });

    test('找不到課號就回 null，不要亂猜一個 id', () {
      expect(courseDetailTarget(_resultTable(), 'X99999'), isNull);
      expect(courseDetailTarget(_resultTable(), ''), isNull);
    });

    test('同課號多班別：靠班別和老師認出使用者按的那一列', () {
      // 真實資料就長這樣：B57011RQ 計算機概論同時有 1年A班和 1年B班，
      // 上課時間不一樣。只比課號的話會固定拿第一列 —— 使用者加的是 B 班，
      // 填進去的卻是 A 班的時間，而且畫面上完全看不出來（有時間、看起來正常）。
      final html = '<table id="DataGrid">'
          '<tr><th>課號</th><th>課名</th><th>年級班別</th><th>授課老師</th></tr>'
          '<tr><td>${_codeLink('ctl02', 'B57011RQ')}</td>'
          '<td>計算機概論</td><td>1年A班</td><td>許為元</td></tr>'
          '<tr><td>${_codeLink('ctl03', 'B57011RQ')}</td>'
          '<td>計算機概論</td><td>1年B班</td><td>林韓禹</td></tr>'
          '</table>';

      expect(
        courseDetailTarget(html, 'B57011RQ',
            classLabel: '1年B班', teacher: '林韓禹'),
        _target('ctl03'),
      );
      expect(
        courseDetailTarget(html, 'B57011RQ',
            classLabel: '1年A班', teacher: '許為元'),
        _target('ctl02'),
      );

      // 只認得出一個線索，也比「隨便拿第一列」好
      expect(
        courseDetailTarget(html, 'B57011RQ', classLabel: '1年B班'),
        _target('ctl03'),
      );

      // 完全沒有線索時維持舊行為：回第一列
      expect(courseDetailTarget(html, 'B57011RQ'), _target('ctl02'));
    });
  });

  group('真實的課程內容頁', () {
    // 這一份是從學校真的抓下來的（login.py --goto 之後自動跟 fn_open）。
    // 沒有 fixture 的人跑 flutter test 不該拿到紅燈。
    final missing = File('${fixturesDir.path}/course_detail.html').existsSync()
        ? null
        : '沒有 course_detail.html';

    test('M_SEG 是空的時候回「沒有時間」，不要退回掃文字亂猜', () {
      // PKNO 不對時，課程內容頁會回一份 Mode=ADD 的空殼：版面和標籤都在，
      // 每一格都是空的。那時候掃文字等於拿頁面上任何三位數當上課時間。
      const shell = '<html><body>'
          '<div><span ml="PL_上課時間">上課時間</span></div>'
          '<div><span id="M_SEG" cname="時間"></span></div>'
          '<div><span id="M_CLSSRM_ID" cname="教室代號">INS105</span></div>'
          '<div>人數限制 105 / 102</div>'
          '</body></html>';

      expect(parseCourseTimeSlots(shell), isEmpty);
    });

    test('直接對著學校回來的那一頁解析上課時間', () {
      final html = fixture('course_detail.html');

      // 真實內容：<span id="M_SEG" CNAME="時間">102,103,104</span>
      // 隔壁是   <span id="M_CLSSRM_ID">INS105,INS105,INS105</span>
      // —— INS105 的 105 是合法代碼，掃文字會多解析出「週一第 5 節」。
      expect(parseCourseTimeSlots(html), const [
        TimeSlot(0, 2),
        TimeSlot(0, 3),
        TimeSlot(0, 4),
      ]);
    }, skip: missing);
  });
}

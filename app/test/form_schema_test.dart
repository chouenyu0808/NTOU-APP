import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:ntou_app/src/ais/form_schema.dart';
import 'package:ntou_app/src/parsing/data_grid.dart';

import 'fixtures.dart';

/// 「全部原生」的做法是：不為 50 個功能頁各寫一個 parser，而是讀頁面自己的宣告。
/// 這組測試鎖住那個假設 —— 學校哪天不再標 `CNAME` / `ml`，這裡會先紅。
void main() {
  group('FunctionSchema（真實頁面）', () {
    test('個人課表查詢：讀出中文欄位與按鈕', () {
      final schema = FunctionSchema.fromDocument(
        html_parser.parse(fixture('Application_TKE_TKE22_TKE2240_01.html')),
      );

      // 這一頁的 <title> 是 `TKE2240_` —— 底線後面是空的。
      // 所以功能名稱要靠選單（menu_tree.json），不能只靠頁面。
      expect(schema.title, isEmpty);

      final labels = {for (final f in schema.visibleFields) f.name: f.label};
      expect(labels['Q_AYEAR'], '學年度');
      expect(labels['Q_SMS'], '學期');

      // 分頁控制項沒有 CNAME，不該被當成使用者要填的欄位
      expect(labels.containsKey('PC\$PageNo'), isFalse);
      expect(labels.containsKey('PC\$PageSize'), isFalse);

      final buttons = {for (final b in schema.buttons) b.name: b.label};
      expect(buttons['QUERY_BTN1'], '選課清單');
      expect(buttons['QUERY_BTN3'], '選課課表');
      // 「還原」只是清空表單的前端動作，不是查詢
      expect(buttons.containsKey('QCLEAR_BTN1'), isFalse);
    }, skip: skipReason);

    test('學年下拉帶回真實選項，不是寫死的', () {
      final schema = FunctionSchema.fromDocument(
        html_parser.parse(fixture('Application_TKE_TKE22_TKE2240_01.html')),
      );
      final year = schema.visibleFields.firstWhere((f) => f.name == 'Q_AYEAR');

      expect(year.kind, FieldKind.select);
      expect(year.options.length, greaterThan(5));
      expect(year.value, isNotEmpty);
      // 每年都會變的東西不該寫在 App 裡
      expect(year.options.map((o) => o.value), contains('115'));
    }, skip: skipReason);

    test('課程查詢：五組查詢條件的欄位都讀得出來', () {
      final schema = FunctionSchema.fromDocument(
        html_parser.parse(fixture('Application_TKE_TKE22_TKE2211_01.html')),
      );

      expect(schema.title, '課程課表查詢');

      final labels = {for (final f in schema.visibleFields) f.name: f.label};
      expect(labels['Q_FACULTY_CODE'], '系所代碼');
      expect(labels['Q_CH_LESSON'], '中文課名');
      expect(labels['Q_WEEK'], '星期');
      expect(labels['Q_CLSSRM_BUILD'], isNotNull);
    }, skip: skipReason);

    test('沒有選項的下拉標成 needsCascade —— 那種欄位不能送', () {
      // Q_LECTR_TCH_CH 初始 0 個 option，要先選系所觸發連動 postback。
      // 直接送空字串會踩 event validation，而錯誤只是一句通用的 403。
      final schema = FunctionSchema.fromDocument(
        html_parser.parse(fixture('Application_TKE_TKE22_TKE2211_01.html')),
      );
      final teacher =
          schema.visibleFields.firstWhere((f) => f.name == 'Q_LECTR_TCH_CH');

      expect(teacher.options, isEmpty);
      expect(teacher.needsCascade, isTrue);
    }, skip: skipReason);

    test('type=button 的列印鈕不收進來', () {
      // PRINT_ALL_BTN1 是 `type="button" onclick="doPrint()"`，不是 submit。
      // doPrint() 會先動 QUERY_COND 和 Q_AYEARSMS 再送，不是單純的 postback ——
      // 收進來而不重現那些副作用的話，按下去只會得到看不懂的 403。
      final schema = FunctionSchema.fromDocument(
        html_parser.parse(fixture('Application_TKE_TKE22_TKE2211_01.html')),
      );

      expect(schema.buttons.any((b) => b.name.contains('PRINT')), isFalse);
      // 能驅動的那幾顆都在
      expect(schema.queryButtons.map((b) => b.name), contains('QUERY_BTN1'));
      expect(schema.queryButtons.map((b) => b.name), contains('QUERY_BTN5'));
    }, skip: skipReason);
  });

  group('parseDataGrid（真實頁面）', () {
    test('全校課程查詢的結果', () {
      final r = parseDataGrid(
        fixture('Application_TKE_TKE22_TKE2211_01__QUERY_BTN1_0_0507.html'),
      );

      expect(r.isEmpty, isFalse);
      expect(r.columns, contains('課號'));
      expect(r.columns, contains('課名'));
      expect(r.rowCount, greaterThan(0));
      // 每一列的欄數都跟表頭對得上（分頁列已經濾掉）
      expect(r.rows.every((row) => row.length == r.columns.length), isTrue);
      expect(r.records.first['課號'], isNotEmpty);
    }, skip: skipReason);

    test('查無資料：isEmpty 為真，而不是解析失敗', () {
      final r = parseDataGrid(
        fixture('Application_TKE_TKE22_TKE2240_01__QUERY_BTN1_115_1.html'),
      );

      expect(r.isEmpty, isTrue);
      expect(r.rowCount, 0);
    }, skip: skipReason);

    test('讀得到分頁狀態', () {
      final r = parseDataGrid(
        fixture('Application_TKE_TKE22_TKE2211_01__QUERY_BTN5_1_03.html'),
      );

      expect(r.paging.pageSize, 10);
      expect(r.paging.pageNo, 1);
      // 這個時段全校超過一頁。末頁頁碼是從「>>」那顆的
      // gotoPage('PC_PageNo', 11, ...) 讀出來的，不是從顯示的頁碼猜的。
      expect(r.paging.lastPage, greaterThan(1));
      expect(r.paging.hasMore, isTrue);
    }, skip: skipReason);
  });

  group('分頁式的功能頁', () {
    FunctionSchema courseSearch() => FunctionSchema.fromDocument(
          html_parser.parse(fixture('Application_TKE_TKE22_TKE2211_01.html')),
        );

    test('六組查詢各自分開，不是攛平成一張表單', () {
      // 攛平的話畫面上會出現六顆都叫「查詢」的按鈕，
      // 十幾個欄位混在一起 —— 使用者不知道哪個配哪個。
      final schema = courseSearch();
      expect(schema.isTabbed, isTrue);
      expect(schema.groups.map((g) => g.label), [
        '單位查詢',
        '關鍵字查詢',
        '開課老師查詢',
        '上課時間查詢',
        '教室排課查詢',
        '全英語課查詢',
      ]);
    }, skip: skipReason);

    test('欄位跟按鈕分到正確的組', () {
      final g = {for (final g in courseSearch().groups) g.label: g};

      expect(g['單位查詢']!.fields.map((f) => f.name),
          containsAll(['Q_DEGREE_CODE', 'Q_FACULTY_CODE']));
      expect(g['單位查詢']!.buttons.map((b) => b.name), ['QUERY_BTN1']);

      expect(g['上課時間查詢']!.fields.map((f) => f.name),
          containsAll(['Q_WEEK', 'Q_CLASS']));
      expect(g['上課時間查詢']!.buttons.map((b) => b.name), ['QUERY_BTN5']);

      // 開課老師查詢有兩顆：課表跟清單
      expect(g['開課老師查詢']!.buttons.map((b) => b.name),
          containsAll(['QUERY_BTN3', 'QUERY_BTN4']));
    }, skip: skipReason);

    test('index 是 0-based，送出時要放進 hdnSelectedTab', () {
      // tabs_init() 寫進去的是 jQuery UI 的 active 索引，
      // 容器 id 却是 tabs-1 起跳 —— 差一個就會用錯一組條件。
      final groups = courseSearch().groups;
      expect(groups.first.index, 0);
      expect(groups.map((g) => g.index), [0, 1, 2, 3, 4, 5]);
    }, skip: skipReason);

    test('沒有分頁的頁面只有一組', () {
      final schema = FunctionSchema.fromDocument(
        html_parser.parse(fixture('Application_TKE_TKE22_TKE2240_01.html')),
      );
      expect(schema.isTabbed, isFalse);
      expect(schema.groups.single.label, isEmpty);
      expect(schema.groups.single.buttons.map((b) => b.name),
          containsAll(['QUERY_BTN1', 'QUERY_BTN3']));
    }, skip: skipReason);
  });
}

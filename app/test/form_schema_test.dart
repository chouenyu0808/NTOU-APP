import 'dart:io';

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

  group('按鈕標籤', () {
    FunctionSchema parse(String html) =>
        FunctionSchema.fromDocument(html_parser.parse(html));

    test('剝掉的不只是 CB_ —— 任何大寫前綴都不該漏到畫面上', () {
      // 維護新生資料那一頁上就有一顆 ml="PL_填寫範例說明"，
      // 只剝 CB_ 的話使用者會看到「PL_填寫範例說明」。
      final schema = parse(
        '<html><body><form>'
        '<input type="submit" name="B1" ml="CB_查詢">'
        '<input type="submit" name="B2" ml="PL_填寫範例說明">'
        '</form></body></html>',
      );

      final labels = schema.groups.single.buttons.map((b) => b.label).toList();
      expect(labels, ['查詢', '填寫範例說明']);
      expect(labels.any((l) => l.contains('_')), isFalse);
    });

    test('長表單上下各一顆的「存檔」只留一顆', () {

      // 維護新生資料每一組都有兩顆「存檔」：一顆在表單最上面、一顆在最下面，

      // onclick 都是 `return doSave();` —— 同一個動作，只是排版方便。

      // 我們的畫面按鈕集中在一起，兩顆長得一樣的只是雜訊。

      final schema = parse(

        '<html><body><form>'

        '<input type="submit" name="SAVE_BTN1" ml="CB_存檔" '

        'onclick="return doSave();">'

        '<input type="text" name="F1" cname="姓名">'

        '<input type="submit" name="SAVE_BTN2" ml="CB_存檔" '

        'onclick="return doSave();">'

        '</form></body></html>',

      );



      final buttons = schema.groups.single.buttons;

      expect(buttons.map((b) => b.label), ['存檔']);

      // 留的是第一顆，不是硬造一個「存檔 2」出來

      expect(buttons.single.name, 'SAVE_BTN1');

    });



    test('標籤一樣但動作不同的，一顆都不能少', () {

      // 課程課表查詢六顆都叫「查詢」，但 doQuery('1')…('6') 是六個不同的查詢。

      // 只看標籤去重會把五個功能吃掉。

      final schema = parse(

        '<html><body><form>'

        '<input type="submit" name="QUERY_BTN1" ml="CB_查詢" '

        'onclick="return doQuery(&#39;1&#39;);">'

        '<input type="submit" name="QUERY_BTN7" ml="CB_查詢" '

        'onclick="return doQuery(&#39;2&#39;);">'

        '</form></body></html>',

      );



      expect(schema.groups.single.buttons.map((b) => b.name),

          ['QUERY_BTN1', 'QUERY_BTN7']);

    });



    test('只有一顆的時候原樣保留', () {
      final schema = parse(
        '<html><body><form>'
        '<input type="submit" name="SAVE1" ml="CB_存檔">'
        '</form></body></html>',
      );

      expect(schema.groups.single.buttons.single.label, '存檔');
    });

    test('第二種分頁：TabBtn 當標籤、TabCnt 裝內容', () {
      // 維護新生資料那一頁沒有 `#tabs-N` 錨點，靠一排 TabBtn 按鈕切換，
      // 內容在 TabCnt 裡（非作用中的 display:none）。
      final schema = parse(
        '<html><body><form>'
        '<input type="button" id="TabBtn1" ml="CB_基本資料">'
        '<input type="button" id="TabBtn2" ml="CB_戶籍與聯絡資料">'
        '<div id="TabCnt1" style="display: ">'
        '<input type="text" name="M_NAME" cname="姓名">'
        '<input type="submit" name="SAVE_BTN1" ml="CB_存檔"></div>'
        '<div id="TabCnt2" style="display: none">'
        '<input type="text" name="M_ADDR" cname="戶籍地址">'
        '<input type="submit" name="SAVE_BTN3" ml="CB_存檔"></div>'
        '</form></body></html>',
      );

      expect(schema.isTabbed, isTrue);
      expect(schema.groups.map((g) => g.label), ['基本資料', '戶籍與聯絡資料']);

      // 每組各自一顆存檔，不是兩顆疊在同一畫面
      for (final g in schema.groups) {
        expect(g.buttons.single.label, '存檔');
      }
      expect(schema.groups[0].buttons.single.name, 'SAVE_BTN1');
      expect(schema.groups[1].buttons.single.name, 'SAVE_BTN3');

      // 欄位也要跟著分開
      expect(schema.groups[0].visibleFields.single.label, '姓名');
      expect(schema.groups[1].visibleFields.single.label, '戶籍地址');
    });

    test('分頁式的頁面每組只有一顆，不能被誤加編號', () {
      // 課程課表查詢整頁有 6 顆都叫「查詢」，但每個標籤頁只看得到一顆 ——
      // 那是正常的，不該變成「查詢 1」。
      final schema = parse(
        '<html><body><form>'
        '<ul><li><a href="#tabs-1">單位查詢</a></li>'
        '<li><a href="#tabs-2">教師查詢</a></li></ul>'
        '<div id="tabs-1">'
        '<input type="submit" name="QUERY_BTN1" ml="CB_查詢"></div>'
        '<div id="tabs-2">'
        '<input type="submit" name="QUERY_BTN2" ml="CB_查詢"></div>'
        '</form></body></html>',
      );

      expect(schema.isTabbed, isTrue);
      for (final g in schema.groups) {
        expect(g.buttons.single.label, '查詢');
      }
    });
  });

  group('維護新生資料（真實頁面）', () {
    final missing =
        File('${fixturesDir.path}/Application_ENR_ENR30_ENR3030_01.html')
                .existsSync()
            ? null
            : '沒有 ENR3030 的 fixture';

    test('8 組條件要分開，不是 14 顆一模一樣的「存檔」攤在同一畫面', () {
      final schema = FunctionSchema.fromDocument(html_parser.parse(
          fixture('Application_ENR_ENR30_ENR3030_01.html')));

      expect(schema.isTabbed, isTrue);
      expect(schema.groups.map((g) => g.label),
          containsAll(['基本資料', '戶籍與聯絡資料', '入學前資料', '綜合記錄']));

      // 攤平的話整頁有 14 顆「存檔」。分好組之後每一組都只有個位數。
      for (final g in schema.groups) {
        final saves = g.queryButtons.where((b) => b.label.startsWith('存檔'));
        expect(saves.length, lessThan(4),
            reason: '「${g.label}」有 ${saves.length} 顆存檔，分組沒生效');
      }

      // 學校內部的欄位命名不該漏到畫面上
      for (final g in schema.groups) {
        for (final b in g.buttons) {
          expect(b.label, isNot(startsWith('PL_')));
          expect(b.label, isNot(startsWith('CB_')));
        }
      }
    }, skip: missing);

    group('維護新生資料：不是只有下拉和文字框', () {
      // 這一頁是全 App 表單最複雜的一頁，而且會**真的寫學籍資料**。
      // 以前 schema 只認得 `<select>` 和 `<input type=text>`，那一頁 151 個
      // 可見欄位裡沒有一個是勾選型，還有兩格整個不存在。
      FunctionSchema schema() => FunctionSchema.fromDocument(html_parser.parse(
          fixture('Application_ENR_ENR30_ENR3030_01.html')));

      SchemaField? field(FunctionSchema s, String name) =>
          s.fields.where((f) => f.name == name).firstOrNull;

      test('textarea 讀得到 —— 以前「自傳」那 2000 字整格不存在', () {
        final autobiography = field(schema(), 'M_AUTOBI');

        expect(autobiography, isNotNull,
            reason: '<textarea> 以前完全沒被掃進來，畫面上找不到這一格');
        expect(autobiography!.label, '自傳');
        expect(autobiography.kind, FieldKind.textarea);
        // 值在元素內容裡，不在 value 屬性 —— 拿 value 會永遠是空的。
        expect(autobiography.value, isNotEmpty);
        expect(autobiography.maxLength, 2000);
      });

      test('同名的 radio 收成一組，不是三個一模一樣的文字框', () {
        final s = schema();
        final identity = s.fields.where((f) => f.name == 'M_GENDER_IDENTITY');

        expect(identity, hasLength(1),
            reason: '以前一個 radio 一個欄位，畫面上是三個都叫「自我認同性別」的文字框');
        expect(identity.single.kind, FieldKind.radio);
        expect(identity.single.label, '自我認同性別');
        expect(identity.single.value, '1', reason: 'checked 的那一顆');
        expect(
          identity.single.options.map((o) => o.label),
          ['Male(男)', 'Female(女)', 'Other(其他)'],
          reason: '選項的字要來自 <label for=...>，不是 value',
        );
      });

      test('CheckBoxList 收成一個複選欄位，不是 37 個文字框', () {
        final present = field(schema(), 'M_PRESENT_TYPE');

        expect(present, isNotNull);
        expect(present!.kind, FieldKind.checkboxes);
        // CNAME 在包住整組的 <span id="M_PRESENT_TYPE"> 上，不在 input 上。
        expect(present.label, '目前身份');
        expect(present.options.length, greaterThan(30));
        expect(present.options.first.label, '01-一般生');
        // 選中的存的是各自的欄位名，送出時才展開成 `名字=on`。
        expect(SchemaField.splitChecked(present.value),
            [r'M_PRESENT_TYPE$0']);
      });

      test('學校鎖住的欄位標成唯讀 —— 瀏覽器根本不送 disabled 的東西', () {
        final s = schema();

        // disabled 放在包住整組的 <span> 上，個別 input 不一定有，要往上找。
        expect(field(s, 'M_SEX')!.readOnly, isTrue, reason: '性別整組 disabled');
        expect(field(s, 'M_PRESENT_TYPE')!.readOnly, isTrue);
        // <select disabled> 也一樣 —— 以前這一格是可以拉的，
        // 拉完送出去等於改一個使用者不該改的欄位。
        expect(field(s, 'M_ST_TYPE')!.readOnly, isTrue, reason: '學生類別');

        expect(field(s, 'M_GENDER_IDENTITY')!.readOnly, isFalse,
            reason: '這一組沒有 disabled，不要連坐');
      });

      test('沒有兩個欄位共用同一個名字', () {
        final s = schema();
        final counts = <String, int>{};
        for (final f in s.visibleFields) {
          counts[f.name] = (counts[f.name] ?? 0) + 1;
        }
        final dupes = counts.entries.where((e) => e.value > 1).toList();

        // 重複的欄位在送出時後面會蓋掉前面 —— 使用者填的是哪一格
        // 完全不可預測。
        expect(dupes, isEmpty,
            reason: '重複：${dupes.map((e) => '${e.key} x${e.value}').join(', ')}');
      });
    }, skip: missing);

    test('課程課表查詢的關鍵字分頁：「類別」和「查詢模式」是選項，不是文字框', () {
      // 這兩組 radio 決定「用課號還是課名查」「精準還是模糊」。頁面預設是
      // 課號＋精準 —— 拿「微積分」去做課號的精準比對，永遠是「查無符合資料」，
      // 而畫面上看起來就像這門課不存在。
      //
      // 以前它們被畫成 5 個文字框（類別 3 個、查詢模式 2 個），同名欄位
      // 後蓋前，送出去的是一個沒人選過的值。
      final schema = FunctionSchema.fromDocument(html_parser.parse(
          fixture('Application_TKE_TKE22_TKE2211_01.html')));

      final keyword =
          schema.groups.firstWhere((g) => g.label == '關鍵字查詢');
      final byName = {for (final f in keyword.visibleFields) f.name: f};

      expect(keyword.visibleFields.map((f) => f.name).toSet(),
          {'radioButtonClass', 'Q_CH_LESSON', 'radioButtonQuery'});

      final kind = byName['radioButtonClass']!;
      expect(kind.kind, FieldKind.radio);
      expect(kind.options.map((o) => o.label), ['課號', '課名', '老師']);

      expect(byName['radioButtonQuery']!.kind, FieldKind.radio);
    }, skip: missing);
  });
}

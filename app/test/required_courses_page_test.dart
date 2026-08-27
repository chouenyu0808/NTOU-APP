import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/required_courses_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';
import 'fixtures.dart';

/// 派發器 -> 查詢表單。
const _dispatcher = r"""<html><body>
<script>top.mainFrame.location.href='ENRA120_01.aspx';</script>
</body></html>""";

/// 查詢表單。條件全部由 `FunctionSchema` 從頁面自己的宣告讀出來，
/// 所以這裡照真實頁面的形狀寫（`CNAME` 是欄位的中文名）。
const _form = '<html><head><title>ENRA120_查詢必修科目表</title></head>'
    '<body><form>'
    r'<input type="hidden" name="__VIEWSTATE" value="vs">'
    '<select name="Q_ENROLL_AYEAR" cname="入學年度">'
    '<option value="114">114</option>'
    '<option value="115" selected>115</option>'
    '</select>'
    '<select name="Q_RQ_CRS_TYPE" cname="必修科目類別">'
    '<option value="1">本系必修科目</option>'
    '<option value="2">輔系必修科目</option>'
    '</select>'
    '<select name="Q_FACULTY_CODE" cname="系所">'
    '<option value="0507">0507-資訊工程學系</option>'
    '</select>'
    r'<input type="submit" name="QUERY_BTN1" ml="CB_查詢" value="查詢">'
    '</form></body></html>';

bool _isDispatcher(FakeRequest r) => r.page.startsWith('ENRA120_.aspx');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedAis ais;
  late AppController controller;

  setUp(() async {
    ais = ScriptedAis();
    controller = await loggedInController(ais);
  });

  Widget wrap() => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: RequiredCoursesPage(controller: controller),
      );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
  }

  group('查詢條件', () {
    testWidgets('欄位是讀頁面自己的宣告畫出來的，沒有寫死', (tester) async {
      ais.reply = (r) => _isDispatcher(r) ? _dispatcher : _form;
      await open(tester);

      // CNAME="入學年度" / "必修科目類別" / "系所"
      expect(find.text('入學年度'), findsOneWidget);
      expect(find.text('必修科目類別'), findsOneWidget);
      expect(find.text('系所'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '查詢'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('還沒查之前提醒條件要跟自己一致', (tester) async {
      ais.reply = (r) => _isDispatcher(r) ? _dispatcher : _form;
      await open(tester);

      // 查到別人的必修表而不自知，是這一頁最糟的失敗方式
      expect(find.textContaining('不然看到的會是別人的必修表'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('查詢結果（真實資料）', () {
    const name =
        'Application_ENR_ENRA0_ENRA120_01__QUERY_BTN1_115_1_0_0507_01.html';
    final missing =
        File('${fixturesDir.path}/$name').existsSync() ? null : '沒有 $name';

    testWidgets('門檻、學期分組、課號都畫得出來', (tester) async {
      final real = fixture(name);
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) return real;
        return _form;
      };
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, '查詢'));
      await tester.pumpAndSettle();

      // 三個門檻
      expect(find.text('135'), findsOneWidget);
      expect(find.text('78'), findsOneWidget);
      expect(find.text('57'), findsOneWidget);
      expect(find.text('畢業最低'), findsOneWidget);

      // 三個大數字並排長得像進度條的兩端，很容易被讀成「我修到 135 了」。
      // 成績查詢不在這套系統的學生選單裡，App 拿不到已修學分 ——
      // 沒講清楚的話，這一頁會被當成他根本沒有的那份進度表。
      expect(find.textContaining('這是門檻，不是進度'), findsOneWidget);

      // 一上那一組，以及它底下的課。
      // ListView 是延遲建構的，畫面外的列還沒進樹裡 —— 要捲過去才找得到。
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('計算機概論'), findsWidgets);
      expect(find.textContaining('一上'), findsWidgets);
      await unmount(tester);
    }, skip: missing != null);

    testWidgets('沒有課號的要說「修滿學分即可」，不要讓人去找那門課', (tester) async {
      final real = fixture(name);
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) return real;
        return _form;
      };
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, '查詢'));
      await tester.pumpAndSettle();

      // 「11-博雅課程」不是一門課，是一個領域
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.textContaining('修滿學分即可，不限課號'), findsWidgets);
      await unmount(tester);
    }, skip: missing != null);
  });

  group('查不到的時候', () {
    testWidgets('說條件可能不對，而不是一片空白', (tester) async {
      ais.reply = (r) {
        if (_isDispatcher(r)) return _dispatcher;
        if (r.pressed('QUERY_BTN1')) {
          return '<html><body>查無符合資料</body></html>';
        }
        return _form;
      };
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, '查詢'));
      await tester.pumpAndSettle();

      expect(find.textContaining('確認一下入學年度、系所和入學身分'), findsOneWidget);
      await unmount(tester);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/function_list_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

void main() {
  late AppController controller;

  // 保留學校選單原本的層次：模組 > 中間層（group）> 功能。
  final catalog = MenuCatalog.fromJson([
    {
      'text': '課程課表查詢',
      'href': 'Application/TKE/TKE22/TKE2211_.aspx?progcd=x',
      'trail': '教務系統>選課系統>課程課表查詢',
    },
    {
      'text': '線上加退選',
      'href': 'Application/TKE/TKE20/TKE2011_.aspx?progcd=x',
      'trail': '教務系統>選課系統>線上加退選',
    },
  ]);

  setUp(() async {
    controller = await newController();
  });

  Widget wrap() => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: FunctionListPage(
          controller: controller,
          catalog: catalog,
          module: '教務系統',
          color: Colors.blue,
        ),
      );

  testWidgets('標題是模組名，並保留中間層的分組標頭', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '教務系統'), findsOneWidget);
    expect(find.text('選課系統'), findsOneWidget); // group 標頭
    expect(find.text('課程課表查詢'), findsOneWidget);
    expect(find.text('線上加退選'), findsOneWidget);
  });

  testWidgets('會改資料的功能靠圖示區分，警告只在頂端說一次', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // **舊版每一列各掛一行「會送出資料」。** 教務系統底下 53 個功能有 21 個
    // 會送出，那一頁就是滿螢幕紅字 —— 而警告的作用是讓人停下來，到處都是
    // 就沒人會停。
    expect(find.text('會送出資料'), findsNothing);
    expect(find.textContaining('紅色的會送出申請或修改資料'), findsOneWidget);

    // 區分靠圖示：紅色 edit_note（圖例 1 個 + 線上加退選 1 個）
    // vs 藍色 description_outlined（課程課表查詢）。
    // 顏色和形狀同時不同，所以不是只靠顏色在傳達。
    expect(find.byIcon(Icons.edit_note), findsNWidgets(2));
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });

  testWidgets('整個模組都是查詢時，不要放那行圖例', (tester) async {
    // 圖例是在解釋紅色代表什麼。一個紅色項目都沒有還印那行字，
    // 使用者會回頭找那個不存在的紅色。
    final readOnly = MenuCatalog.fromJson([
      {
        'text': '課程課表查詢',
        'href': 'Application/TKE/TKE22/TKE2211_.aspx?progcd=x',
        'trail': '教務系統>選課系統>課程課表查詢',
      },
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: FunctionListPage(
        controller: controller,
        catalog: readOnly,
        module: '教務系統',
        color: Colors.blue,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('紅色的'), findsNothing);
  });

  group('系辦報表', () {
    final withStaff = MenuCatalog.fromJson([
      {
        'text': '課程課表查詢',
        'href': 'Application/TKE/TKE22/TKE2211_.aspx?progcd=x',
        'trail': '教務系統>選課系統>課程課表查詢',
      },
      {
        'text': '上課時間衝堂學生名單查詢',
        'href': 'Application/TKE/TKE20/TKE2070_01.aspx?PAGETYPE=TKE2070',
        'trail': '教務系統>選課系統>上課時間衝堂學生名單查詢',
      },
      {
        'text': '選課學分超過上限學生名單查詢',
        'href': 'Application/TKE/TKE20/TKE2070_01.aspx?PAGETYPE=TKE2080',
        'trail': '教務系統>選課系統>選課學分超過上限學生名單查詢',
      },
    ]);

    Widget wrapStaff() => MaterialApp(
          theme: NtouTheme.of(Brightness.light),
          home: FunctionListPage(
            controller: controller,
            catalog: withStaff,
            module: '教務系統',
            color: Colors.blue,
          ),
        );

    testWidgets('從原本的分組裡抽出來，收進摺疊區', (tester) async {
      await tester.pumpWidget(wrapStaff());
      await tester.pumpAndSettle();

      // 真實資料裡這 12 個全部落在「選課系統」，佔掉那組 26 個裡的 12 個 ——
      // 混在裡面時那一組看起來像是「選課有一半的功能我看不懂」。
      expect(find.text('系辦報表'), findsOneWidget);
      expect(find.textContaining('2 項'), findsOneWidget);

      // 摺疊起來，所以名字看不到；一般功能照常在外面。
      expect(find.text('上課時間衝堂學生名單查詢'), findsNothing);
      expect(find.text('課程課表查詢'), findsOneWidget);
    });

    testWidgets('展開就看得到 —— 是降級不是封鎖', (tester) async {
      await tester.pumpWidget(wrapStaff());
      await tester.pumpAndSettle();

      await tester.tap(find.text('系辦報表'));
      await tester.pumpAndSettle();

      expect(find.text('上課時間衝堂學生名單查詢'), findsOneWidget);
      expect(find.text('選課學分超過上限學生名單查詢'), findsOneWidget);
    });

    testWidgets('沒有系辦報表的模組不會冒出空的摺疊區', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.text('系辦報表'), findsNothing);
    });
  });

  testWidgets('未登入時點功能會提示先登入，不會直接進去', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('課程課表查詢'));
    await tester.pumpAndSettle();

    expect(find.text('請先登入'), findsOneWidget);
    // 沒有離開這一頁。
    expect(find.widgetWithText(AppBar, '教務系統'), findsOneWidget);
  });
}

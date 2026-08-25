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

  testWidgets('會改資料的功能標成「會送出資料」', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 線上加退選（TKE2011）是 mutating，要先警告，不能跟查詢混在一起。
    expect(find.text('會送出資料'), findsOneWidget);
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

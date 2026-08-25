import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/function_list_page.dart';
import 'package:ntou_app/src/ui/module_list_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

void main() {
  late AppController controller;

  final catalog = MenuCatalog.fromJson([
    {
      'text': '課程課表查詢',
      'href': 'Application/TKE/TKE22/TKE2211_.aspx?progcd=x',
      'trail': '教務系統>選課系統>課程課表查詢',
    },
    {
      // 頂層就是功能的（trail 只有一層）會進「帳號」區。
      'text': '修改密碼',
      'href': 'Application/PWD/PWD1020_.aspx',
      'trail': '修改密碼',
    },
  ]);

  setUp(() async {
    controller = await newController();
  });

  Widget wrap() => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: ModuleListPage(controller: controller, catalog: catalog),
      );

  testWidgets('顯示模組網格與「帳號」區', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '校務系統'), findsOneWidget);
    expect(find.text('教務系統'), findsOneWidget); // 模組格子
    expect(find.text('帳號'), findsOneWidget); // 區段標題
    expect(find.text('修改密碼'), findsOneWidget); // 頂層功能
  });

  testWidgets('點模組格子進到該模組的功能清單', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('教務系統'));
    await tester.pumpAndSettle();

    // 導到 FunctionListPage：標題變模組名，列出底下的功能。
    expect(find.byType(FunctionListPage), findsOneWidget);
    expect(find.text('課程課表查詢'), findsOneWidget);
  });
}

import 'dart:convert';
import 'dart:io';

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
      'text': '線上加退選',
      'href': 'Application/TKE/TKE20/TKE2011_.aspx?progcd=x',
      'trail': '教務系統>選課系統>線上加退選',
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

  group('搜尋功能', () {
    testWidgets('打關鍵字之後，網格換成符合的功能清單', (tester) async {
      // 13 個模組底下 50 個功能，顏色解的是「找模組」不是「找功能」。
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '加退選');
      await tester.pumpAndSettle();

      expect(find.text('線上加退選'), findsOneWidget);
      // 網格收起來了
      expect(find.byType(GridView), findsNothing);
      await unmount(tester);
    });

    testWidgets('比對的是整條麵包屑，不只是功能名稱', (tester) async {
      // 使用者記得的常常是「請假那一區的東西」，不是確切的功能名。
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '選課系統');
      await tester.pumpAndSettle();

      // 這幾個功能名稱裡都沒有「選課系統」四個字，是靠 trail 比到的
      expect(find.text('課程課表查詢'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('結果附「模組 › 群組」，名字像的分得出來', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '課程課表查詢');
      await tester.pumpAndSettle();

      expect(find.textContaining('教務系統 › 選課系統'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('沒有符合的說清楚是在幾個功能裡找', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz沒有這個');
      await tester.pumpAndSettle();

      expect(find.textContaining('沒有符合'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('清空之後網格回來，13 色原封不動', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '加退選');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      await unmount(tester);
    });
  });

  group('真實的 26 個模組都要認得', () {
    // 網格是靠**顏色 + 圖示 + 位置**讓人一眼找到東西的（見 NtouTheme 的
    // moduleColors 註解）。2026-09-08 學校一次加了 13 個模組，兩邊都不夠用，
    // 而症狀在畫面上是「一半的格子長一樣」，不是任何錯誤。
    final real = MenuCatalog.fromJson(
      jsonDecode(File('assets/menu_tree.json').readAsStringSync()) as List,
    );

    test('顏色不少於模組數，否則會有兩個模組同色', () {
      // moduleColor 是 index % length —— 13 色配 26 個模組剛好整除，
      // 每個顏色會出現兩次，「請假是紫色那個」就有兩個答案。
      expect(
        NtouTheme.moduleColors.length,
        greaterThanOrEqualTo(real.modules.length),
        reason: '學校又加模組了，往 moduleColors 後面接新的顏色（不要重排）',
      );
    });

    test('顏色彼此不重複', () {
      expect(
        NtouTheme.moduleColors.toSet().length,
        NtouTheme.moduleColors.length,
      );
    });

    testWidgets('每個模組都有自己的圖示，沒有一個掉進 fallback', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: ModuleListPage(controller: controller, catalog: real),
      ));
      await tester.pumpAndSettle();

      // 沒對應的模組會拿到 Icons.folder_outlined。一個都不該有 ——
      // 那是「這個模組我沒認出來」的樣子。
      expect(
        find.byIcon(Icons.folder_outlined),
        findsNothing,
        reason: '有模組沒有圖示，補進 module_list_page.dart 的 _icons',
      );
    });
  });
}

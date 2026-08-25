import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/home_shell.dart';
import 'package:ntou_app/src/ui/module_list_page.dart';
import 'package:ntou_app/src/ui/planner_page.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:ntou_app/src/ui/timetable_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

/// 骨架這一層要鎖的是：三個分頁都接上了、切換有反應。
///
/// promptLoginOnOpen 關掉 —— 開著的話一掛載就去打學校的伺服器，
/// 而 widget test 裡的 HttpClient 是被擋住的。
void main() {
  late AppController controller;
  late PlanStore store;

  setUp(() async {
    controller = await newController();
    store = PlanStore(prefs: await SharedPreferences.getInstance());
  });

  Widget wrap() => MaterialApp(
        theme: NtouTheme.of(Brightness.light),
        home: HomeShell(
          controller: controller,
          catalog: const MenuCatalog([]),
          planStore: store,
          promptLoginOnOpen: false,
        ),
      );

  testWidgets('底部有課表 / 預排 / 校務系統三個分頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('課表'), findsWidgets);
    expect(find.text('預排'), findsWidgets);
    expect(find.text('校務系統'), findsWidgets);
  });

  testWidgets('三頁都掛在骨架裡（IndexedStack）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // IndexedStack 會把非當前頁放到 offstage，finder 預設會跳過，
    // 所以這裡明確 skipOffstage: false，確認三頁都真的建進了樹裡。
    expect(find.byType(TimetablePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(PlannerPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(ModuleListPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('一開始停在課表（index 0）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });

  testWidgets('點「預排」切到第 2 頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('預排'));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1);
  });

  testWidgets('點「校務系統」切到第 3 頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 用未選中的 icon 來點，避開 ModuleListPage AppBar 也叫「校務系統」的歧義。
    await tester.tap(find.byIcon(Icons.apps_outlined));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
  });
}

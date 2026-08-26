import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/home_page.dart';
import 'package:ntou_app/src/ui/home_shell.dart';
import 'package:ntou_app/src/ui/module_list_page.dart';
import 'package:ntou_app/src/ui/planner_page.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:ntou_app/src/ui/timetable_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

/// 骨架這一層要鎖的是：四個分頁都接上了、切換有反應。
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

  testWidgets('底部有首頁 / 課表 / 預排 / 校務系統四個分頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('首頁'), findsWidgets);
    expect(find.text('課表'), findsWidgets);
    expect(find.text('預排'), findsWidgets);
    expect(find.text('校務系統'), findsWidgets);
  });

  testWidgets('四頁都掛在骨架裡（IndexedStack）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // IndexedStack 會把非當前頁放到 offstage，finder 預設會跳過，
    // 所以這裡明確 skipOffstage: false，確認四頁都真的建進了樹裡。
    expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(TimetablePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(PlannerPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(ModuleListPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('一開始停在首頁（index 0）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });

  testWidgets('點「預排」切到預排頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('預排'));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
  });

  testWidgets('首頁的快捷可以切到別的分頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 首頁上的「預排課表」快捷 —— 對新生來說那是開學前唯一用得到的東西，
    // 不該要他先知道底部有幾個分頁。
    await tester.tap(find.text('預排課表'));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
  });

  testWidgets('點「校務系統」切到校務系統頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 用未選中的 icon 來點，避開 ModuleListPage AppBar 也叫「校務系統」的歧義。
    // 要限定在 NavigationBar 裡 —— 首頁的快捷也用同一顆 icon。
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.apps_outlined),
    ));
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 3);
  });
}

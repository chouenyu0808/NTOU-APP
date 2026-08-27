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

/// 骨架這一層要鎖的是：三個分頁都接上了、切換有反應，
/// 而且課表分頁上的「本學期 / 預排」切得動。
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

  testWidgets('底部是首頁 / 課表 / 校務三個分頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(3));
    expect(find.text('首頁'), findsWidgets);
    expect(find.text('課表'), findsWidgets);
    expect(find.text('校務'), findsWidgets);
  });

  testWidgets('三頁都掛在骨架裡（IndexedStack）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // IndexedStack 會把非當前頁放到 offstage，finder 預設會跳過，
    // 所以這裡明確 skipOffstage: false。
    expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(ModuleListPage, skipOffstage: false), findsOneWidget);
    // 課表分頁一次只建其中一份 —— 預設是「本學期」。
    expect(find.byType(TimetablePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(PlannerPage, skipOffstage: false), findsNothing);
  });

  testWidgets('一開始停在首頁（index 0）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });

  testWidgets('課表分頁上用切換鈕換成預排，底部分頁不變', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('課表'));
    await tester.pumpAndSettle();
    expect(find.byType(TimetablePage), findsOneWidget);

    // 兩份課表畫的是同一種東西，用同一頁上的切換鈕換，
    // 而不是底部再多一個分頁。
    await tester.tap(find.text('預排'));
    await tester.pumpAndSettle();

    expect(find.byType(PlannerPage), findsOneWidget);
    expect(find.byType(TimetablePage), findsNothing);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1, reason: '還在課表分頁上');
  });

  // 首頁上原本有「完整課表」和「預排課表」兩張快捷，兩張都導到同一個地方
  // （見 35eae1e）。後來整批砍掉了 —— 它們只是把底部分頁列再列一次。
  // 那個 bug 現在結構上不可能再發生，所以驗它的兩條測試也跟著走。

  testWidgets('點「校務」切到校務系統頁', (tester) async {
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
    expect(bar.selectedIndex, 2);
  });
}

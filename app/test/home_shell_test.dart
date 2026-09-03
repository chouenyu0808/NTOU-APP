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
import 'package:ntou_app/src/ui/transit_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

/// 骨架這一層要鎖的是：四個分頁都接上了、切換有反應，
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

  testWidgets('底部是首頁 / 課表 / 校務 / 交通四個分頁', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(find.text('首頁'), findsWidgets);
    expect(find.text('課表'), findsWidgets);
    expect(find.text('校務'), findsWidgets);
    expect(find.text('交通'), findsWidgets);
  });

  testWidgets('四頁都掛在骨架裡（IndexedStack）', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // IndexedStack 會把非當前頁放到 offstage，finder 預設會跳過，
    // 所以這裡明確 skipOffstage: false。
    expect(find.byType(HomePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(ModuleListPage, skipOffstage: false), findsOneWidget);
    // 課表分頁底下**兩份都掛著**，也是 IndexedStack。
    //
    // 以前這裡是 `_schedule == 0 ? TimetablePage : PlannerPage`，切換時
    // 同一個位置換成不同型別，Flutter 把舊的 Element 整個丟掉重建 ——
    // 預排頁選好的學年學期就跟著沒了。排下學期排到一半點一下「本學期」
    // 再點回來，就被丟回當學期，畫面上沒有任何提示。
    expect(find.byType(TimetablePage, skipOffstage: false), findsOneWidget);
    expect(find.byType(PlannerPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(TransitPage, skipOffstage: false), findsOneWidget);
  });

  /// 交通頁掛著，但**開 App 的時候不該開始做事**。
  ///
  /// 它裡面有一個每 30 秒重抓的計時器和一顆載入中的轉圈圈。停在首頁的時候
  /// 兩個都不該啟動：計時器會整天打交通部的伺服器，而那顆轉圈圈是無限動畫，
  /// 只要它在畫面上，整個 App 的 pumpAndSettle 就永遠等不到穩定。
  testWidgets('停在首頁時，交通頁沒有在背景轉圈圈', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final page = tester.widget<TransitPage>(
      find.byType(TransitPage, skipOffstage: false),
    );
    expect(page.isActive, isFalse);
    expect(
      find.descendant(
        of: find.byType(TransitPage, skipOffstage: false),
        matching: find.byType(CircularProgressIndicator),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('切去「本學期」再切回來，預排選的學期還在', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('課表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('預排'));
    await tester.pumpAndSettle();

    // PlannerPage 的 State 就是那個記憶體。切走再切回來如果是同一個
    // State 物件，右上角選好的學期才不會被重置。
    final before = tester.state(find.byType(PlannerPage));

    await tester.tap(find.text('本學期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('預排'));
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(PlannerPage)), same(before));
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

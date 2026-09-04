import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'src/config/selectors.dart';
import 'src/data/ais_repository.dart';
import 'src/menu/menu_catalog.dart';
import 'src/storage/credential_store.dart';
import 'src/storage/plan_store.dart';
import 'src/storage/timetable_cache.dart';
import 'src/ui/app_controller.dart';
import 'src/ui/auth_gate.dart';
import 'src/ui/theme.dart';
import 'src/widget/widget_background.dart';
import 'src/widget/widget_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await SelectorConfig.loadFromAsset();
  final catalog = await MenuCatalog.load();

  final repository = AisRepository(
    config: config,
    cache: TimetableCache(),
    // log 只收得到 URL / 狀態碼 / 長度（見 AisSession._absorb），
    // 而且只在 debug build 印出來。release 版一行都不留。
    log: kDebugMode ? (line) => debugPrint(line) : null,
  );

  // 桌面小組件。**註冊背景進入點要在這裡做，不是第一次用到的時候** ——
  // 它記的是一個 callback handle，原生下次要在背景叫 Dart 的時候就靠它，
  // 而那個時候 App 通常根本沒在跑。沒註冊過的話小組件永遠不會自己更新，
  // 而且不會有任何錯誤訊息。
  //
  // 註冊失敗（例如平台不支援）不該讓 App 開不起來，所以吞掉。
  unawaited(
    HomeWidget.registerInteractivityCallback(ntouWidgetBackground)
        .catchError((_) => null),
  );

  final widgets = WidgetUpdater();
  final controller = AppController(
    repository: repository,
    credentials: CredentialStore(),
    widgets: widgets,
  );
  await controller.init();

  // 開 App 就把桌面小組件補一次。
  //
  // **這是唯一保證修得好的路徑** —— 背景那條有太多會靜靜失敗的環節，
  // 而使用者發現小組件不動之後會做的第一件事正好就是開 App。
  //
  // 不 await：它會讀本機快取、可能打一次網路，那不該擋著第一幀。
  unawaited(widgets.refreshAll());

  runApp(NtouApp(controller: controller, catalog: catalog, planStore: PlanStore()));
}

class NtouApp extends StatefulWidget {
  const NtouApp({
    super.key,
    required this.controller,
    required this.catalog,
    required this.planStore,
  });

  final AppController controller;
  final MenuCatalog catalog;
  final PlanStore planStore;

  @override
  State<NtouApp> createState() => _NtouAppState();
}

class _NtouAppState extends State<NtouApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 學校系統一個帳號同時只允許一個 session，App 掛著的那個會擋住使用者
    // 自己在瀏覽器登入 —— 症狀是「系統同時一次僅許可一個帳號登入」，
    // 完全看不出兇手是自己的手機。所以離開夠久就要放掉。
    //
    // 但「一切出去就登出」太煩：看一眼訊息再回來就要重打驗證碼。
    // 所以給兩分鐘緩衝，細節見 AppController.handlePaused。
    //
    // 這裡不能 await（lifecycle callback 是同步的），但 logout 內部
    // 就算請求失敗也會把本機 cookie 清掉，不會留下半個狀態。
    switch (state) {
      case AppLifecycleState.paused:
        widget.controller.handlePaused();
      case AppLifecycleState.resumed:
        unawaited(widget.controller.handleResumed());
      case AppLifecycleState.detached:
        // 要被關掉了，最後一次機會，不等緩衝
        unawaited(widget.controller.handleDetached());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NTOU',
      debugShowCheckedModeBanner: false,
      theme: NtouTheme.of(Brightness.light),
      darkTheme: NtouTheme.of(Brightness.dark),
      home: AuthGate(
        controller: widget.controller,
        catalog: widget.catalog,
        planStore: widget.planStore,
      ),
    );
  }

}

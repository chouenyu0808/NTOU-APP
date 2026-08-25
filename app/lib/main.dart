import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/config/selectors.dart';
import 'src/data/ais_repository.dart';
import 'src/storage/credential_store.dart';
import 'src/storage/timetable_cache.dart';
import 'src/ui/app_controller.dart';
import 'src/ui/timetable_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await SelectorConfig.loadFromAsset();

  final repository = AisRepository(
    config: config,
    cache: TimetableCache(),
    // log 只收得到 URL / 狀態碼 / 長度（見 AisSession._absorb），
    // 而且只在 debug build 印出來。release 版一行都不留。
    log: kDebugMode ? (line) => debugPrint(line) : null,
  );

  final controller = AppController(
    repository: repository,
    credentials: CredentialStore(),
  );
  await controller.init();

  runApp(NtouApp(controller: controller));
}

class NtouApp extends StatefulWidget {
  const NtouApp({super.key, required this.controller});

  final AppController controller;

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
    // App 離開前景就登出。
    //
    // 學校系統一個帳號同時只允許一個 session，而 App 掛著的 session
    // 會擋住使用者自己在瀏覽器登入 —— 症狀是「系統同時一次僅許可一個帳號登入」，
    // 完全看不出是自己手機上的 App 造成的。
    //
    // 代價是回到 App 要重新登入（含驗證碼）。這是刻意的取捨：
    // 課表有快取，看得到；擋住使用者選課則是不能接受的。
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // 這裡不能 await（lifecycle callback 是同步的），但 logout 內部
      // 就算請求失敗也會把本機 cookie 清掉，所以不會留下半個狀態。
      unawaited(widget.controller.handleBackgrounded());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '海大課表',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: TimetablePage(controller: widget.controller),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF00587A), // 海大的海
      );
}

import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import '../storage/plan_store.dart';
import 'app_controller.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'module_list_page.dart';
import 'planner_page.dart';
import 'timetable_page.dart';

/// App 的骨架：課表在前面，校務系統的 13 個模組在後面。
///
/// 課表為什麼獨立一頁而不是塞進「教務系統」底下：那是每天都會看好幾次的東西，
/// 藏在三層選單裡等於沒做。其餘 49 個功能是一年用幾次的，放在選單裡剛好。
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    required this.catalog,
    required this.planStore,
    this.promptLoginOnOpen = true,
  });

  final AppController controller;
  final MenuCatalog catalog;
  final PlanStore planStore;

  /// 開 App 時自動跳登入頁。
  ///
  /// 測試會關掉它 —— 開著的話畫面一掛載就去打學校的伺服器，
  /// 而 widget test 裡的 HttpClient 是被擋住的。
  final bool promptLoginOnOpen;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 開 App 直接進登入頁。
    //
    // 這一頁一掛載就會去開登入頁、通過排隊關卡、抓驗證碼 —— 那要三個請求、
    // 好幾秒。使用者在讀畫面的時候就讓它跑，比先看到課表、按了「登入」
    // 才開始等要快。
    //
    // 是用 push 的，所以按返回就能退出去看快取的課表 ——
    // 學校系統掛掉或帳號在別處登著的時候，那是唯一還看得到的東西。
    if (widget.promptLoginOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptLogin());
    }
  }

  Future<void> _promptLogin() async {
    if (!mounted || widget.controller.phase == AppPhase.ready) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoginPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(
            controller: widget.controller,
            onOpenTab: (i) => setState(() => _index = i),
          ),
          TimetablePage(controller: widget.controller),
          PlannerPage(controller: widget.controller, store: widget.planStore),
          ModuleListPage(
            controller: widget.controller,
            catalog: widget.catalog,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首頁',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '課表',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '預排',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: '校務系統',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import '../storage/plan_store.dart';
import 'app_controller.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'module_list_page.dart';
import 'planner_page.dart';
import 'timetable_page.dart';
import 'transit_page.dart';

/// App 的骨架：首頁 / 課表 / 校務 / 交通。
///
/// 課表為什麼獨立一頁而不是塞進「教務系統」底下：那是每天都會看好幾次的東西，
/// 藏在三層選單裡等於沒做。其餘 49 個功能是一年用幾次的，放在選單裡剛好。
///
/// **「本學期」和「預排」合併成同一個分頁。** 兩者畫的是同一種東西（一週的
/// 格子），底部分成兩個按鈕的話，使用者得先看標題才知道自己在看哪一份。
/// 改成同一頁上的切換鈕，兩份課表的關係就變成「同一件事的兩個版本」。
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

  /// 課表分頁裡看的是哪一份：0 = 本學期、1 = 預排。
  int _schedule = 0;

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

  /// 課表分頁標題位置的切換鈕。
  Widget _scheduleSwitch() => SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('本學期')),
          ButtonSegment(value: 1, label: Text('預排')),
        ],
        selected: {_schedule},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _schedule = v.first),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(controller: widget.controller),
          // 又一層 IndexedStack，不是三元運算子。
          //
          // 用 `_schedule == 0 ? A : B` 的話，切換時同一個位置換成不同型別的
          // widget，Flutter 會把舊的 Element 整個丟掉重建 —— 預排頁選好的
          // 學年學期（右上角那顆）就跟著沒了。使用者排下學期排到一半，
          // 點一下「本學期」再點回來，就被丟回當學期，而且不會有任何提示。
          IndexedStack(
            index: _schedule,
            children: [
              TimetablePage(
                controller: widget.controller,
                titleWidget: _scheduleSwitch(),
              ),
              PlannerPage(
                controller: widget.controller,
                store: widget.planStore,
                titleWidget: _scheduleSwitch(),
              ),
            ],
          ),
          ModuleListPage(
            controller: widget.controller,
            catalog: widget.catalog,
          ),
          // 交通只有這一頁需要知道自己有沒有被看著。
          //
          // 外面這個 IndexedStack 會讓四個分頁**從開 App 起就一直掛載**，
          // 而交通頁裡有一個每 30 秒重抓一次的計時器。不告訴它現在是不是
          // 在前景的話，使用者整天在看課表，它照樣整天打交通部的伺服器。
          TransitPage(isActive: _index == 3),
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
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: '校務',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bus_outlined),
            selectedIcon: Icon(Icons.directions_bus),
            label: '交通',
          ),
        ],
      ),
    );
  }
}

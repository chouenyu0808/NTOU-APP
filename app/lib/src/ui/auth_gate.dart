import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import '../storage/plan_store.dart';
import 'app_controller.dart';
import 'home_shell.dart';
import 'login_page.dart';

/// 登入關卡。
///
/// 登入成功之前，畫面上就只有登入頁 —— **不是蓋在功能上面的一層，是唯一的一頁**。
/// 掛在背景太久被登出之後，也是直接退回這裡（見
/// [AppController.backgroundGrace]）。
///
/// 用 [AnimatedSwitcher] 而不是 Navigator：登入狀態是 App 的模式，不是導覽層級。
/// 用 push/pop 表達的話，「session 逾時要退回登入」就得從任何一層強制彈出，
/// 那種程式碼很快就會失控。
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.catalog,
    required this.planStore,
  });

  final AppController controller;
  final MenuCatalog catalog;
  final PlanStore planStore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final signedIn = controller.phase == AppPhase.ready;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: signedIn
              ? HomeShell(
                  key: const ValueKey('shell'),
                  controller: controller,
                  catalog: catalog,
                  planStore: planStore,
                )
              : LoginPage(
                  key: const ValueKey('login'),
                  controller: controller,
                ),
        );
      },
    );
  }
}

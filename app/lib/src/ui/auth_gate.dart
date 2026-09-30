import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import '../storage/plan_store.dart';
import 'app_controller.dart';
import 'home_shell.dart';

/// 登入只保護學校查詢，本機資料與交通保持可用。
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => HomeShell(
      controller: controller,
      catalog: catalog,
      planStore: planStore,
      promptLoginOnOpen:
          controller.hasSavedPassword && controller.username.isNotEmpty,
    ),
  );
}

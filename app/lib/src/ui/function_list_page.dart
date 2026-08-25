import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import 'app_controller.dart';
import 'function_page.dart';

/// 一個模組底下的功能清單。
///
/// 保留學校選單原本的中間層（例如「教務系統 > 選課系統」）—— 排序過或攤平的
/// 清單跟網頁對不起來，使用者要重新找一次。
class FunctionListPage extends StatelessWidget {
  const FunctionListPage({
    super.key,
    required this.controller,
    required this.catalog,
    required this.module,
    required this.color,
  });

  final AppController controller;
  final MenuCatalog catalog;
  final String module;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final groups = catalog.groupsOf(module);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(module)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final entry in groups.entries) ...[
            if (entry.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  entry.key,
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              )
            else
              const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final f in entry.value)
                    FunctionTile(
                      controller: controller,
                      function: f,
                      color: color,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

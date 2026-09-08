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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 系辦報表全部抽出來擺到最後。教務系統這一頁 53 個項目裡有 12 個是
    // 它們，而且全部集中在「選課系統」那一組（26 個裡佔 12 個）——
    // 混在裡面的時候，那一組看起來像是「選課有一半的功能我看不懂」。
    final staff = <AisFunction>[];
    final groups = <String, List<AisFunction>>{};
    for (final entry in catalog.groupsOf(module).entries) {
      final keep = <AisFunction>[];
      for (final f in entry.value) {
        (f.staffOnly ? staff : keep).add(f);
      }
      if (keep.isNotEmpty) groups[entry.key] = keep;
    }

    final hasMutating =
        groups.values.any((list) => list.any((f) => f.mutating));

    return Scaffold(
      appBar: AppBar(title: Text(module)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 每一列各掛一行「會送出資料」的話，這一頁會有 21 行紅字。
          // 說一次就好 —— 那顆紅色圖示在每一列上都看得到。
          if (hasMutating)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '紅色的會送出申請或修改資料，點進去前會再問一次',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
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
          if (staff.isNotEmpty) ...[
            const SizedBox(height: 24),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: Icon(Icons.inventory_2_outlined,
                    size: 20, color: scheme.onSurfaceVariant),
                title: const Text('系辦報表'),
                // 不寫「你用不到」—— 那是替使用者下結論。說清楚它是什麼，
                // 讓他自己判斷；真的要看的人一樣打得開。
                subtitle: Text(
                  '${staff.length} 項　行政統計用，學生查通常是空的',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                children: [
                  for (final f in staff)
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

import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import 'app_controller.dart';
import 'function_list_page.dart';
import 'function_page.dart';
import 'theme.dart';

/// 學校系統的 13 個模組。
///
/// 用彩色圖示網格而不是展開式清單：13 個模組展開之後有 50 個功能，
/// 攤在一個捲動清單上要找很久。網格一眼掃得完，顏色和位置固定之後
/// 會變成肌肉記憶（「請假是紫色那個」）。
///
/// 路徑來自 `assets/menu_tree.json`（spike 遞迴展開整棵 TreeView 抓下來的），
/// **App 不自己走選單** —— 那套 callback 是整個逆向裡最脆的一段。
class ModuleListPage extends StatelessWidget {
  const ModuleListPage({
    super.key,
    required this.controller,
    required this.catalog,
  });

  final AppController controller;
  final MenuCatalog catalog;

  static const Map<String, IconData> _icons = {
    '教務系統': Icons.school_outlined,
    '暑修作業': Icons.wb_sunny_outlined,
    '學生宿舍管理系統': Icons.bed_outlined,
    '校外租賃訊息管理': Icons.home_work_outlined,
    '就學貸款-減免補助': Icons.savings_outlined,
    '學生請假': Icons.event_busy_outlined,
    '學生社團活動資訊系統': Icons.groups_outlined,
    '學生兵役管理': Icons.military_tech_outlined,
    '新生體檢收件作業': Icons.health_and_safety_outlined,
    '體育室辦證系統': Icons.fitness_center_outlined,
    'SDGs': Icons.public_outlined,
    '電子公布欄': Icons.campaign_outlined,
    '連結校內資訊系統': Icons.link_outlined,
  };

  /// 顯示用的短名稱。網格的格子放不下「學生社團活動資訊系統」這種長度。
  static const Map<String, String> _shortNames = {
    '學生宿舍管理系統': '學生宿舍',
    '校外租賃訊息管理': '校外租賃',
    '就學貸款-減免補助': '就貸減免',
    '學生社團活動資訊系統': '社團活動',
    '學生兵役管理': '兵役管理',
    '新生體檢收件作業': '新生體檢',
    '體育室辦證系統': '體育室辦證',
    '連結校內資訊系統': '校內系統',
  };

  @override
  Widget build(BuildContext context) {
    final modules = catalog.modules;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('校務系統')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.82,
                children: [
                  for (var i = 0; i < modules.length; i++)
                    _ModuleTile(
                      label: _shortNames[modules[i]] ?? modules[i],
                      icon: _icons[modules[i]] ?? Icons.folder_outlined,
                      color: NtouTheme.moduleColor(i),
                      count: catalog.inModule(modules[i]).length,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FunctionListPage(
                            controller: controller,
                            catalog: catalog,
                            module: modules[i],
                            color: NtouTheme.moduleColor(i),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('帳號', style: theme.textTheme.titleSmall),
          ),
          Card(
            child: Column(
              children: [
                for (final f in catalog.standalone)
                  if (!f.path.contains('LogOut') && !f.path.contains('Portal'))
                    FunctionTile(controller: controller, function: f),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(height: 1.15),
            ),
          ),
        ],
      ),
    );
  }
}

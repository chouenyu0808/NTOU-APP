import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import 'app_controller.dart';
import 'function_list_page.dart';
import 'function_page.dart';
import 'theme.dart';
import 'timetable_page.dart' show confirmLogout;

/// 學校系統的 13 個模組。
///
/// 用彩色圖示網格而不是展開式清單：13 個模組展開之後有 50 個功能，
/// 攤在一個捲動清單上要找很久。網格一眼掃得完，顏色和位置固定之後
/// 會變成肌肉記憶（「請假是紫色那個」）。
///
/// 路徑來自 `assets/menu_tree.json`（spike 遞迴展開整棵 TreeView 抓下來的），
/// **App 不自己走選單** —— 那套 callback 是整個逆向裡最脆的一段。
class ModuleListPage extends StatefulWidget {
  const ModuleListPage({
    super.key,
    required this.controller,
    required this.catalog,
  });

  final AppController controller;
  final MenuCatalog catalog;

  @override
  State<ModuleListPage> createState() => _ModuleListPageState();
}

class _ModuleListPageState extends State<ModuleListPage> {
  final _search = TextEditingController();
  String _query = '';

  MenuCatalog get catalog => widget.catalog;
  AppController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 比對功能名稱和整條麵包屑。
  ///
  /// **純字串比對，不打學校的伺服器。** 選單那 50 個功能是登入時就抓下來的
  /// （`menu_tree.json`），搜尋只是在本機的清單上過濾。
  ///
  /// 比 `trail` 而不只是名稱：使用者記得的常常是「請假那一區的東西」，
  /// 不是「取消請假申請」這個確切的字。
  List<AisFunction> get _matches {
    final q = _query.trim();
    if (q.isEmpty) return const [];
    return [
      for (final f in catalog.functions)
        if (f.title.contains(q) || f.trail.join(' ').contains(q)) f,
    ];
  }

  /// 這個功能屬於哪一個模組的顏色。顏色的位置是固定的（見 NtouTheme），
  /// 所以搜尋結果的圓點跟網格上的顏色會對得起來。
  Color _colorOf(AisFunction f) {
    final i = catalog.modules.indexOf(f.module);
    return i < 0 ? Theme.of(context).colorScheme.outline : NtouTheme.moduleColor(i);
  }

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
          // 13 個模組底下有 50 個功能，光「學生請假」就 8 個 ——
          // 顏色解的是「找模組」，沒解「找功能」。
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜尋功能，例如「請假」',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '清除',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),

          if (_query.trim().isNotEmpty) ..._searchResults(theme) else ...[
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
                // 登出從課表頁的 AppBar 搬過來 —— 那不屬於課表。
                if (controller.phase == AppPhase.ready)
                  ListTile(
                    leading: Icon(Icons.logout,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('登出',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    onTap: () => confirmLogout(context, controller),
                  ),
              ],
            ),
          ),
          ],
        ],
      ),
    );
  }

  List<Widget> _searchResults(ThemeData theme) {
    final hits = _matches;
    if (hits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              '這 ${catalog.functions.length} 個功能裡沒有符合「$_query」的。',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('${hits.length} 個功能', style: theme.textTheme.titleSmall),
      ),
      Card(
        child: Column(
          children: [
            for (var i = 0; i < hits.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              _SearchHit(
                controller: controller,
                function: hits[i],
                color: _colorOf(hits[i]),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

/// 一筆搜尋結果。
///
/// 附上「模組 › 群組」的麵包屑：50 個功能裡有好幾組名字很像的
/// （「查詢減免補助歷年申請資料」和「查詢就學貸款歷年申請資料」），
/// 只給名稱分不出來是哪一個。
class _SearchHit extends StatelessWidget {
  const _SearchHit({
    required this.controller,
    required this.function,
    required this.color,
  });

  final AppController controller;
  final AisFunction function;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trail = function.trail.length > 1
        ? function.trail.sublist(0, function.trail.length - 1).join(' › ')
        : function.module;

    return FunctionTile(
      controller: controller,
      function: function,
      color: color,
      subtitleOverride: trail,
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
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
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

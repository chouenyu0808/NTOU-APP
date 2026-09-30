import 'package:flutter/material.dart';

import '../menu/menu_catalog.dart';
import 'app_controller.dart';
import 'function_list_page.dart';
import 'function_page.dart';
import 'login_page.dart';
import '../storage/recent_functions.dart';
import 'timetable_page.dart' show confirmLogout;

/// 以常用功能和真實的最近使用紀錄為入口，完整分類保留在下方。
/// 選單從本機資產讀取，搜尋不用連到學校。
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
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    RecentFunctions.changes.addListener(_loadRecent);
  }

  Future<void> _loadRecent() async {
    final paths = await RecentFunctions.read();
    if (mounted) setState(() => _recent = paths);
  }

  MenuCatalog get catalog => widget.catalog;
  AppController get controller => widget.controller;

  @override
  void dispose() {
    RecentFunctions.changes.removeListener(_loadRecent);
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
    final q = _query.trim().toLowerCase();
    final aliases = {
      '缺課': '缺曠',
      '缺席': '缺曠',
      '分數': '成績',
      '宿舍維修': '修繕',
      '畢業學分': '畢業',
    };
    final terms = [q, if (aliases[q] != null) aliases[q]!];
    if (q.isEmpty) return const [];
    return [
      for (final f in catalog.functions)
        if (!f.staffOnly &&
            terms.any(
              (term) =>
                  f.title.toLowerCase().contains(term) ||
                  f.trail.join(' ').toLowerCase().contains(term),
            ))
          f,
    ];
  }

  Color _colorOf(AisFunction f) => Theme.of(context).colorScheme.primary;

  static const Map<String, String> _shortNames = {
    '學生宿舍管理系統': '學生宿舍',
    '校外租賃訊息管理': '校外租賃',
    '就學貸款-減免補助': '就貸減免',
    '學生社團活動資訊系統': '社團活動',
    '學生兵役管理': '兵役管理',
    '新生體檢收件作業': '新生體檢',
    '體育室辦證系統': '體育室辦證',
    '連結校內資訊系統': '校內系統',
    // ↓ 新模組裡名字放不下的。沒有短名的（職涯發展、五育護照…）本來就夠短。
    '學生證補發作業': '學生證補發',
    '學生宿舍修繕系統': '宿舍修繕',
    '導師工作-班級系統': '導師班級',
    '學生團體保險': '團體保險',
    '獎助學金管理': '獎助學金',
    '學習助學金系統': '學習助學金',
    '獎懲-操行管理': '獎懲操行',
    '遺失物-拾獲物管理': '遺失物',
    '問卷調查系統': '問卷調查',
    '教育學程作業': '教育學程',
    '網路服務申請': '網路服務',
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

          if (_query.trim().isNotEmpty)
            ..._searchResults(theme)
          else ...[
            if (controller.phase != AppPhase.ready)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('登入後查詢個人校務資料'),
                trailing: TextButton(
                  onPressed: () => ensureSignedIn(context, controller),
                  child: const Text('登入'),
                ),
              ),
            Text('常用功能', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final code in ['GRD5010', 'GRD7050', 'ENRG010', 'TKE2011'])
              if (catalog.byCode(code) case final function?)
                FunctionTile(controller: controller, function: function),
            if (_recent.isNotEmpty) ...[
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Text('最近使用', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: '更新最近使用',
                    onPressed: _loadRecent,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
              for (final path in _recent)
                for (final function in catalog.functions.where(
                  (f) => f.path == path,
                ))
                  FunctionTile(controller: controller, function: function),
            ],
            const Divider(height: 32),
            Text('全部服務', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns = constraints.maxWidth >= 480 * scale
                    ? 3
                    : constraints.maxWidth >= 320 * scale
                    ? 2
                    : 1;
                return Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < modules.length; i++)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          title: Text(_shortNames[modules[i]] ?? modules[i]),
                          subtitle: Text(
                            '${catalog.inModule(modules[i]).length} 項服務',
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 16),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => FunctionListPage(
                                  controller: controller,
                                  catalog: catalog,
                                  module: modules[i],
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            );
                            await _loadRecent();
                          },
                        ),
                      ),
                  ],
                );
              },
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
                    if (!f.path.contains('LogOut') &&
                        !f.path.contains('Portal'))
                      FunctionTile(controller: controller, function: f),
                  // 登出從課表頁的 AppBar 搬過來 —— 那不屬於課表。
                  if (controller.phase == AppPhase.ready)
                    ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        '登出',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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

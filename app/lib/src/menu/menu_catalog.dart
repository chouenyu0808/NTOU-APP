import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 選單裡的一個功能。
class AisFunction {
  const AisFunction({
    required this.title,
    required this.path,
    required this.trail,
  });

  final String title;

  /// `Application/<模組>/<子模組>/<代碼>_.aspx?progcd=<代碼>`
  ///
  /// **這是派發器不是內容頁** —— GET 完要跟 JS 導向才會到真正的表單。
  final String path;

  /// 麵包屑：`['教務系統', '選課系統', '課程課表查詢']`。
  final List<String> trail;

  String get module => trail.isEmpty ? '' : trail.first;

  /// 中間那層（例如「選課系統」）。頂層功能沒有。
  String get group => trail.length > 2 ? trail[1] : '';

  /// 功能代碼，例如 `TKE2211`。用來比對危險清單。
  String get code {
    final m = RegExp(r'/(\w+?)_\.aspx').firstMatch(path);
    return m?.group(1) ?? '';
  }

  /// 這一頁會不會改到資料。
  ///
  /// 清單抄自 `spike/login.py` 的 `MUTATING_PATTERNS` —— 那份是用來讓
  /// `--fetch-all` 掃頁時避開的，這裡是用來在使用者點進去之前先問一句。
  ///
  /// **選課期間誤觸「線上加退選」一次，後果不是重跑一次能解決的。**
  bool get mutating => _mutatingCodes.any(path.toUpperCase().contains);

  static const List<String> _mutatingCodes = [
    'TKE2011', // 線上加退選
    'ENRD140', // 申請休退學
    'SDM2010', 'SDM2070', // 申請住宿 / 換床
    'SAC3010', 'SAC2010', // 申請減免 / 就學貸款
    'ENR6030', // 申請抵免學分
    'SEC6000', 'SEC2020', 'SEC2030', // 請假申請 / 取消 / 刪除
    'ENR3030', 'ENR3040', 'ENR3090', // 維護新生/舊生資料、線上註冊
    'SMM1010', 'SMM5010', // 維護兵役資料、上傳附件
    'SDG2010', // 質化指標填報
    'SCM2030', // 申請運動證
    'PWD1020', // 修改密碼
    'LOGOUT', // 登出會作廢 session
  ];

  /// 這一頁按下去會真的送出什麼 —— 給提醒對話框用的一句話。
  String get mutationWarning {
    final upper = path.toUpperCase();
    if (upper.contains('TKE2011')) {
      return '這一頁會真的加選或退選課程。選課期間誤觸一次，後果不是重跑一次能解決的。';
    }
    if (upper.contains('ENRD140')) return '這一頁會真的送出休學／退學申請。';
    if (upper.contains('PWD1020')) return '這一頁會真的修改你的密碼。改完之後 App 存的舊密碼會失效。';
    if (upper.contains('LOGOUT')) return '這會結束學校系統上的登入狀態。';
    return '這一頁會送出申請或修改資料，不只是查詢。';
  }

  factory AisFunction.fromJson(Map<String, dynamic> j) {
    final trail = (j['trail'] as String? ?? '')
        .split('>')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return AisFunction(
      title: j['text'] as String? ?? '',
      path: j['href'] as String? ?? '',
      trail: trail.isEmpty ? [j['text'] as String? ?? ''] : trail,
    );
  }
}

/// 整棵選單。
///
/// 從 `assets/menu_tree.json` 讀 —— 那份是 spike 用 TreeView callback 遞迴展開
/// 整棵選單得到的（50 個功能）。**App 不自己走選單**：那套
/// （`__CALLBACKPARAM` 組法 + 每次換發的 `__EVENTVALIDATION`）是整個逆向裡最脆的
/// 一段，學校改版最可能先壞在那裡。路徑抄下來直接用，穩得多。
class MenuCatalog {
  const MenuCatalog(this.functions);

  final List<AisFunction> functions;

  static const String assetPath = 'assets/menu_tree.json';

  static Future<MenuCatalog> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return MenuCatalog.fromJson(jsonDecode(raw) as List);
  }

  factory MenuCatalog.fromJson(List<dynamic> list) => MenuCatalog([
        for (final e in list)
          AisFunction.fromJson((e as Map).cast<String, dynamic>()),
      ]);

  /// 有子功能的模組（畫面上那 13 個可展開的項目），照選單原本的順序。
  List<String> get modules {
    final seen = <String>[];
    for (final f in functions) {
      if (f.trail.length > 1 && !seen.contains(f.module)) seen.add(f.module);
    }
    return seen;
  }

  /// 頂層就是功能的項目（修改密碼、登入記錄查詢、回首頁、登出…）。
  List<AisFunction> get standalone =>
      functions.where((f) => f.trail.length == 1).toList();

  List<AisFunction> inModule(String module) =>
      functions.where((f) => f.module == module && f.trail.length > 1).toList();

  /// 模組底下再依中間那層分組，維持選單原本的層次。
  Map<String, List<AisFunction>> groupsOf(String module) {
    final out = <String, List<AisFunction>>{};
    for (final f in inModule(module)) {
      out.putIfAbsent(f.group, () => []).add(f);
    }
    return out;
  }

  AisFunction? byCode(String code) {
    for (final f in functions) {
      if (f.code.toUpperCase() == code.toUpperCase()) return f;
    }
    return null;
  }
}

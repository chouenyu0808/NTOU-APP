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
  ///
  /// 三種路徑形狀都要認得，少一種就有一批功能抽不出代碼（`byCode` 查不到）：
  ///
  /// - `TKE2211_.aspx`      —— 派發器，最常見
  /// - `TKE2070_01.aspx`    —— 直接給內容頁，不經派發器
  /// - `QUE2010_.ASPX`      —— **副檔名大寫**，只有「填寫問卷」這一支
  ///
  /// `PAGETYPE` 要排在檔名前面：12 個「XX 學生名單查詢」**共用同一支
  /// `TKE2070_01.aspx`**，靠檔名的話 12 個功能的代碼會一模一樣，
  /// `byCode` 隨便回一個給你，而且畫面上完全看不出來拿錯了。
  String get code {
    final t = RegExp('PAGETYPE=(\\w+)', caseSensitive: false).firstMatch(path);
    if (t != null) return t.group(1)!;
    final m = RegExp(r'/(\w+?)_(?:\d+)?\.aspx', caseSensitive: false)
        .firstMatch(path);
    return m?.group(1) ?? '';
  }

  /// 這一頁會不會改到資料。
  ///
  /// 清單抄自 `spike/login.py` 的 `MUTATING_PATTERNS` —— 那份是用來讓
  /// `--fetch-all` 掃頁時避開的，這裡是用來在使用者點進去之前先問一句。
  ///
  /// **選課期間誤觸「線上加退選」一次，後果不是重跑一次能解決的。**
  bool get mutating => _mutatingCodes.any(path.toUpperCase().contains);

  /// **判斷依據是功能名稱的動詞，不是它在哪個模組底下。** 同一個模組裡
  /// 「申請」和「查詢申請紀錄」永遠成對出現，只有前者該擋。
  ///
  /// 相反的例外只有一個：`ENRD160` 叫「查詢/撤銷休退學申請記錄」，
  /// 名字以「查詢」開頭，但那一頁上有撤銷按鈕。
  static const List<String> _mutatingCodes = [
    // 選課 —— 這一組時效最短、後果最不可逆
    'TKE2011', 'STU1010', // 線上加退選
    'STU1020', // 預選電腦抽籤
    'STU1030', // 預選志願輸入
    'STU1040', // 人工加選申請
    'STU1050', // 期中退選申請

    // 學籍異動
    'ENRD140', // 申請休退學
    'ENRD160', // 查詢/撤銷休退學 —— 名字是查詢，但頁上有撤銷
    'ENRD030', // 申請轉系
    'ENRD100', // 申請輔系/雙主修
    'ENRD180', // 申請逕升博/碩士先修
    'ENR8040', 'ENR8060', // 申請學分學程 / 申請審核學程證書
    'ENR6030', // 申請抵免學分
    'STU3190', 'MAP0010', // 英檢成績申請抵免（兩個入口同一頁）
    'ENRA200', // 申請/查詢校外會考認證
    'STU3270', 'MAP0021', // 服役彈性修業/超修申請
    'ENRC030', // 申請補發學生證
    'STU3160', 'MAP0001', // 在學證明申請列印 —— 會產生申請記錄
    'ENR3030', 'ENR3040', 'ENR3090', // 維護新生/舊生資料、線上註冊

    // 填報類 —— 送出之後改不回來
    'CET2020', // 填寫課程問卷（教學評鑑）
    'QUE2010', // 填寫問卷
    'SDG2010', // 質化指標填報
    'SCSZ001', // 填寫班會紀錄

    'SEC6000', 'SEC2020', 'SEC2030', 'SEC2080', // 請假申請/取消/刪除/補件
    'SDM2010', 'SDM2070', 'SDR3010', // 申請住宿 / 換床 / 修繕
    'SUM1010', // 登記暑修課程

    // 錢
    'SAC3010', 'SAC2010', // 申請減免 / 就學貸款
    'SGM1050', // 申請獎助學金
    'STU3180', 'MAP0006', // 外語檢定補助與獎勵申請
    'SIS2020', // 申請保險理賠

    'SCD1170', 'SCD1180', // 預約 / 取消職涯諮詢
    'SCD1070', 'SCD1150', // 求職登錄 / 維護學習歷程檔案

    // 兵役 —— 檔名是 SMM1010、progcd 是 SMM1012，兩個都在 path 裡。
    // 比對的是整個 path，所以哪一個都中；兩個都留是為了學校哪天改掉其中一邊。
    'SMM1010', 'SMM1012', 'SMM5010',

    'TED2040', 'TED5030', 'TED6030', 'TED6040', // 教育學程：申請/實習/證書/維護科目表
    'SIP1010', // 申請五育護照
    'SCM2030', // 申請運動證
    'LPR1020', 'LPR1030', // 遺失物登記 / 註銷
    'NDM2010', // VPN 服務申請

    'PWD1020', // 修改密碼
    'LOGOUT', // 登出會作廢 session
  ];

  /// 這一頁按下去會真的送出什麼 —— 給提醒對話框用的一句話。
  String get mutationWarning {
    final upper = path.toUpperCase();
    if (upper.contains('TKE2011')) {
      return '這一頁會真的加選或退選課程。選課期間誤觸一次，後果不是重跑一次能解決的。';
    }
    if (upper.contains('STU1050')) {
      return '這一頁會真的送出期中退選。退掉的課這學期加不回來，學分也不退費。';
    }
    if (upper.contains('STU1030') || upper.contains('STU1020')) {
      return '這一頁是預選志願／抽籤，送出的志願序會直接參與電腦分發。';
    }
    if (upper.contains('STU1040')) return '這一頁會真的送出人工加選申請。';
    if (upper.contains('CET2020')) {
      return '這是教學評鑑問卷，送出之後不能修改，也不能重填。';
    }
    if (upper.contains('ENRD160')) {
      return '這一頁除了查詢，還可以撤銷已經送出的休學／退學申請。';
    }
    if (upper.contains('ENRD140')) return '這一頁會真的送出休學／退學申請。';
    if (upper.contains('ENRD030')) return '這一頁會真的送出轉系申請。';
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

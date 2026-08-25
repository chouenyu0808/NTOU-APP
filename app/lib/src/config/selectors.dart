import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// `selectors.json` 的型別化版本。
///
/// **所有會因為學校改版而爛掉的字串都在這裡**，程式碼裡一個都不寫死。
/// 這樣學校改欄位名的時候，修正是一份 JSON，不是一次 App Store 送審。
///
/// 目前從 bundle 讀（`assets/selectors.json`，跟 `spike/selectors.json` 同一份）。
/// [loadRemote] 之後接 GitHub raw / Remote Config，介面已經留好了。
class SelectorConfig {
  const SelectorConfig({
    required this.version,
    required this.baseUrl,
    required this.minInterval,
    required this.timeout,
    required this.login,
    required this.timetable,
    this.logoutPath = 'LogOut.aspx',
  });

  final int version;
  final String baseUrl;
  final Duration minInterval;

  /// 單一請求的逾時。
  ///
  /// 設成 0 或負數代表**不設逾時** —— 測試用的，正式執行不要這樣配。
  /// （dio 為每個逾時排一個計時器，widget test 會因為那個計時器還掛著而失敗。）
  final Duration timeout;

  final LoginConfig login;
  final TimetableConfig timetable;
  final String logoutPath;

  static const String assetPath = 'assets/selectors.json';

  static Future<SelectorConfig> loadFromAsset() async {
    final raw = await rootBundle.loadString(assetPath);
    return SelectorConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory SelectorConfig.fromJson(Map<String, dynamic> json) {
    final pages = (json['pages'] as Map<String, dynamic>?) ?? const {};
    return SelectorConfig(
      version: (json['version'] as num?)?.toInt() ?? 0,
      baseUrl: json['base_url'] as String? ?? 'https://ais.ntou.edu.tw/',
      minInterval: Duration(
        milliseconds:
            (((json['min_interval_seconds'] as num?) ?? 1.0) * 1000).round(),
      ),
      timeout: Duration(
        milliseconds:
            (((json['timeout_seconds'] as num?) ?? 20) * 1000).round(),
      ),
      login: LoginConfig.fromJson(
        (json['login'] as Map<String, dynamic>?) ?? const {},
      ),
      timetable: TimetableConfig.fromJson(
        (pages['timetable'] as Map<String, dynamic>?) ?? const {},
      ),
      logoutPath: json['logout_path'] as String? ?? 'LogOut.aspx',
    );
  }
}

class LoginConfig {
  const LoginConfig({
    required this.path,
    required this.usernameField,
    required this.passwordField,
    required this.captchaField,
    required this.captchaImgId,
    required this.submitField,
    required this.submitValue,
    required this.failureMarkers,
    this.queuePath,
    this.queueRedirectMarker = 'DefaultQ.aspx',
    this.submitEventTarget = '',
    this.submitEventArgument = '',
    this.successMarkers = const [],
    this.extraFields = const {},
  });

  final String path;

  /// 登入前的虛擬排隊頁。跳過它，驗證碼圖永遠沒有 src，登入必定失敗。
  final String? queuePath;
  final String queueRedirectMarker;

  final String usernameField;
  final String passwordField;
  final String captchaField;
  final String captchaImgId;

  /// 校方自己把 LOGIN 拼成 `LGOIN_BTN`。照抄，不要「順手修正」。
  final String submitField;
  final String submitValue;
  final String submitEventTarget;
  final String submitEventArgument;

  final List<String> successMarkers;
  final List<String> failureMarkers;
  final Map<String, String> extraFields;

  factory LoginConfig.fromJson(Map<String, dynamic> json) => LoginConfig(
        path: json['path'] as String? ?? 'Default.aspx',
        queuePath: json['queue_path'] as String?,
        queueRedirectMarker:
            json['queue_redirect_marker'] as String? ?? 'DefaultQ.aspx',
        usernameField: json['username_field'] as String? ?? '',
        passwordField: json['password_field'] as String? ?? '',
        captchaField: json['captcha_field'] as String? ?? '',
        captchaImgId: json['captcha_img_id'] as String? ?? 'importantImg',
        submitField: json['submit_field'] as String? ?? '',
        submitValue: json['submit_value'] as String? ?? '登入',
        submitEventTarget: json['submit_event_target'] as String? ?? '',
        submitEventArgument: json['submit_event_argument'] as String? ?? '',
        successMarkers: _strings(json['success_markers']),
        failureMarkers: _strings(json['failure_markers']),
        extraFields: _stringMap(json['extra_fields']),
      );
}

class TimetableConfig {
  const TimetableConfig({
    required this.path,
    required this.yearField,
    required this.semesterField,
    required this.listButton,
    required this.timetableButton,
  });

  /// 個人課表的入口。**這是派發器，不是內容頁** —— GET 完要跟 JS 導向。
  final String path;

  final String yearField;
  final String semesterField;

  /// 「選課清單」。回傳 `<table id="DataGrid">`，是 v1 用的資料來源。
  final String listButton;

  /// 「選課課表」。掛在 Crystal Reports 上，輸出格式未驗證 —— v1 不碰。
  final String timetableButton;

  factory TimetableConfig.fromJson(Map<String, dynamic> json) {
    final q = (json['query'] as Map<String, dynamic>?) ?? const {};
    return TimetableConfig(
      path: json['path'] as String? ??
          'Application/TKE/TKE22/TKE2240_.aspx?progcd=STU1220',
      yearField: q['year_field'] as String? ?? 'Q_AYEAR',
      semesterField: q['semester_field'] as String? ?? 'Q_SMS',
      listButton: q['list_button'] as String? ?? 'QUERY_BTN1',
      timetableButton: q['timetable_button'] as String? ?? 'QUERY_BTN3',
    );
  }
}

List<String> _strings(Object? v) =>
    (v as List?)?.whereType<String>().toList() ?? const [];

Map<String, String> _stringMap(Object? v) =>
    (v as Map?)?.map((k, val) => MapEntry('$k', '$val')) ?? const {};

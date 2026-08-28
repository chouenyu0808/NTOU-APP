import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/models.dart';

/// 抓過的課表存在本機。
///
/// **這不是效能優化，是這個 App 能不能用的關鍵。**
/// 學校系統一個帳號同時只能有一個 session —— 使用者在電腦上開著選課系統時，
/// App 一定登不進去。沒有快取的話，那段時間 App 就是一片空白，
/// 而那正好是學生最需要看課表的時候（選課期間）。
///
/// 存 `SharedPreferences` 不存 Keychain：課表是個資但不是憑證，
/// 而且它要能快速讀出來畫第一幀。App 的私有目錄對其他 App 是隔離的。
/// **密碼不在這裡，密碼在 [CredentialStore]。**
class TimetableCache {
  TimetableCache({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= _injected ?? await SharedPreferences.getInstance();

  static String _key(String year, String semester) => 'timetable.$year.$semester';
  static const _kLastViewed = 'timetable.last_viewed';

  Future<TimetableResult?> read(String year, String semester) async {
    final raw = (await _p).getString(_key(year, semester));
    if (raw == null) return null;
    try {
      return TimetableResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // 舊版寫的格式讀不動就當作沒有。壞掉的快取不該讓 App 開不起來。
      return null;
    }
  }

  Future<void> write(TimetableResult result) async {
    final prefs = await _p;
    await prefs.setString(
      _key(result.year, result.semester),
      jsonEncode(result.toJson()),
    );
    await prefs.setStringList(_kLastViewed, [result.year, result.semester]);
  }

  /// 上次看的學年學期，開 App 時直接回到那裡。
  Future<({String year, String semester})?> lastViewed() async {
    final v = (await _p).getStringList(_kLastViewed);
    if (v == null || v.length != 2) return null;
    return (year: v[0], semester: v[1]);
  }

  /// **換帳號**時清掉 —— 不是登出時。
  ///
  /// 登出刻意留著（登出對話框也是這樣講的）：學校一次只允許一個 session，
  /// 帳號在瀏覽器登著的時候，舊課表是唯一還看得到的東西。那個理由只在
  /// 「同一個人」時成立，所以真正該清的時機是
  /// [AppController.submitLogin] 發現學號換了的那一刻。
  Future<void> clear() async {
    final prefs = await _p;
    for (final k in prefs.getKeys().where((k) => k.startsWith('timetable.')).toList()) {
      await prefs.remove(k);
    }
  }
}

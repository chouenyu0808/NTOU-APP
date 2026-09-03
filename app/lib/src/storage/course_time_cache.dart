import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/models.dart';

/// 查過的課「上課時間」存在本機。
///
/// 存在的理由：學校的課程查詢結果**沒有上課時間**那一欄，每一門都要另外走
/// 「點課號 → fn_open → GET 課程詳細頁」兩次請求才問得到。加課清單上要標
/// 衝堂就得每一門都問一次 —— 不存起來的話，同一個系所搜第二次、或是離開
/// 這一頁再進來，整批又要重問一遍，使用者就在那邊等第二次。
///
/// **同一個學期裡課的上課時間不會變**，所以存到學期為止是安全的。
/// 學校真的改了時間的話，這裡會慢一拍 —— 換學期就自動失效（key 帶學年學期），
/// 而選課期間看到的時間本來就以學校的頁面為準。
///
/// 查不到時間的也要存。有些課學校根本沒排時間（例如要親洽系辦的實習），
/// 不記下來的話它們每次都會被重問一次，而答案永遠是同一個。
class CourseTimeCache {
  CourseTimeCache({SharedPreferences? prefs}) : _injected = prefs;

  /// 給 widget 的預設建構子用 —— `const` 才能放進 const 建構子的初始化列表。
  const CourseTimeCache.shared() : _injected = null;

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _p async =>
      _injected ?? await SharedPreferences.getInstance();

  static String _key(String year, String semester) =>
      'course_times.$year.$semester';

  /// 一個學期的全部：課的 key → 時段（空陣列代表「問過了，學校沒給時間」）。
  Future<Map<String, List<TimeSlot>>> read(
    String year,
    String semester,
  ) async {
    final raw = (await _p).getString(_key(year, semester));
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: [
            for (final s in e.value as List)
              TimeSlot.fromJson(s as Map<String, dynamic>),
          ],
      };
    } on FormatException {
      // 壞掉的快取當作沒有，重問一次就好 —— 不該讓加課清單開不起來。
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<void> write(
    String year,
    String semester,
    Map<String, List<TimeSlot>> times,
  ) async {
    await (await _p).setString(
      _key(year, semester),
      jsonEncode({
        for (final e in times.entries)
          e.key: [for (final s in e.value) s.toJson()],
      }),
    );
  }
}

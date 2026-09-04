import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/models.dart';

/// 查過的課程細節（上課時間、上課地點）存在本機，一個學期一張表。
///
/// 存在的理由：學校的課程查詢結果**沒有上課時間、也沒有教室**，每一門都要
/// 另外走「點課號 → fn_open → GET 課程詳細頁」兩次請求才問得到。通識這種
/// 一次開上百門的，光是把整批問完就是幾百次請求、好幾分鐘 —— 不存起來的話，
/// 同一個系所搜第二次、或是離開這一頁再進來，整批又要重問一遍。
///
/// **同一個學期裡課的上課時間和教室不會變**，所以存到學期為止是安全的。
/// key 帶學年學期，換學期就自動失效。學校真的改了時間的話這裡會慢一拍 ——
/// 而選課期間看到的時間本來就以學校的頁面為準。
///
/// **只有學校答過的才進來。** 抓失敗的（連線斷了、詳細頁回空殼）一律不存 ——
/// 存下去的話那門課會永遠停在「查不到上課時間」，而且重開 App 也好不了，
/// 因為表上已經有一筆「問過了，沒有」。這是實際發生過的：通識搜到後面幾十門
/// 全部寫「查不到上課時間」，重搜也一樣。
///
/// 學校答了「這門課沒排時間」的要存（有些課本來就沒時間，例如要親洽系辦的
/// 實習）—— 那種重問一百次答案都一樣。存進來的樣子是 [CourseDetail.slots]
/// 空的，但 [CourseDetail.isBlank] 為假。
class CourseDetailCache {
  CourseDetailCache({SharedPreferences? prefs}) : _injected = prefs;

  /// 給 widget 的預設建構子用 —— `const` 才能放進 const 建構子的初始化列表。
  const CourseDetailCache.shared() : _injected = null;

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _p async =>
      _injected ?? await SharedPreferences.getInstance();

  static String _key(String year, String semester) =>
      'course_details.$year.$semester';

  /// 舊格式：只存時間（`{key: [slot, ...]}`），而且**把抓失敗也存成空陣列**。
  static String _legacyKey(String year, String semester) =>
      'course_times.$year.$semester';

  /// 一個學期的整張表：課的 key（課號＋班別）→ 細節。
  Future<Map<String, CourseDetail>> read(String year, String semester) async {
    final prefs = await _p;
    final raw = prefs.getString(_key(year, semester));
    if (raw == null) return _migrate(prefs, year, semester);
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: CourseDetail.fromJson((e.value as Map).cast<String, dynamic>()),
      };
    } on FormatException {
      // 壞掉的快取當作沒有，重問一次就好 —— 不該讓加課清單開不起來。
      return {};
    } on TypeError {
      return {};
    }
  }

  /// 把舊的「只有時間」那張表搬過來，順手丟掉裡面的空陣列。
  ///
  /// **空陣列一律不搬。** 舊版把抓失敗和「學校沒排時間」都存成空陣列，
  /// 分不出來 —— 搬過來的話那些課會繼續卡在「查不到上課時間」。
  /// 重問一次比較貴，但至少會有答案。
  Future<Map<String, CourseDetail>> _migrate(
    SharedPreferences prefs,
    String year,
    String semester,
  ) async {
    final raw = prefs.getString(_legacyKey(year, semester));
    if (raw == null) return {};

    final out = <String, CourseDetail>{};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final slots = [
          for (final s in e.value as List)
            TimeSlot.fromJson((s as Map).cast<String, dynamic>()),
        ];
        if (slots.isNotEmpty) out[e.key] = CourseDetail(slots: slots);
      }
    } on FormatException {
      // 舊表壞掉就整張丟掉。
    } on TypeError {
      // 同上。
    }

    await prefs.remove(_legacyKey(year, semester));
    if (out.isNotEmpty) await write(year, semester, out);
    return out;
  }

  Future<void> write(
    String year,
    String semester,
    Map<String, CourseDetail> details,
  ) async {
    await (await _p).setString(
      _key(year, semester),
      jsonEncode({for (final e in details.entries) e.key: e.value.toJson()}),
    );
  }

  /// 把新查到的幾門併進表裡。
  ///
  /// **不要用 [write] 蓋掉整張表。** 頁面上記憶體裡那份是開頁時非同步讀回來的，
  /// 讀完之前就有探測回來的話，用記憶體那份去蓋等於把整張表清掉，
  /// 而症狀要到下一次開 App 才看得到。
  Future<void> merge(
    String year,
    String semester,
    Map<String, CourseDetail> entries,
  ) async {
    if (entries.isEmpty) return;
    final all = await read(year, semester);
    all.addAll(entries);
    await write(year, semester, all);
  }
}

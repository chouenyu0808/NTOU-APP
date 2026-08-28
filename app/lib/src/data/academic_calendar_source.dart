import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../parsing/academic_calendar.dart';

/// 校園行事曆的來源：學校官網那一頁，抓回來存著。
///
/// **這是整個 App 唯一一個不打 AIS 的資料來源。**
/// 行事曆在 `www.ntou.edu.tw`，不用登入 —— 它跟課表、成績那些不一樣，
/// 是公開資訊。
///
/// 所以這裡**開一個乾淨的 Dio，沒有 cookie jar**。不共用 `AisSession` 的那個：
/// AIS 的 session cookie 如果是設在 `.ntou.edu.tw` 這一層，共用 client 就會
/// 把它一起送到官網去。官網沒有理由收到那個東西，而一旦送出去了，
/// 它會出現在誰的日誌裡就不是我們能決定的了。
///
/// 抓一次存一天。行事曆一學年更新一次，每次開 App 都去要一次是白費 ——
/// 而且那是別人的伺服器。
class AcademicCalendarSource {
  AcademicCalendarSource({Dio? dio, SharedPreferences? prefs})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // 官網回的是 HTML；responseType 不設成 plain 的話 dio 會想幫忙
          // 解析 JSON 然後在別的地方炸掉。
          responseType: ResponseType.plain,
        )),
        _injected = prefs;

  final Dio _dio;
  final SharedPreferences? _injected;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= _injected ?? await SharedPreferences.getInstance();

  static const String url = 'https://www.ntou.edu.tw/calendar';

  static const _kEvents = 'calendar.events';
  static const _kFetchedAt = 'calendar.fetched_at';

  /// 多久重抓一次。
  static const Duration maxAge = Duration(days: 1);

  /// 行事曆。**失敗一律回快取，沒有快取就回空的。**
  ///
  /// 這是首頁上的一塊，不是使用者按下去要的東西 —— 官網掛掉、手機沒網路的
  /// 時候，正確的行為是那一區安靜地不顯示，不是讓首頁跳錯誤。
  Future<List<CalendarEvent>> load({DateTime? now, bool force = false}) async {
    final cached = await _readCache();
    if (!force && cached != null && _isFresh(cached.fetchedAt, now)) {
      return cached.events;
    }

    try {
      final res = await _dio.get<String>(url);
      final body = res.data;
      if (body == null || body.isEmpty) return cached?.events ?? const [];

      final events = parseAcademicCalendar(body);
      // 解出 0 筆通常代表官網改版了，不是「今年沒有行事曆」——
      // 這種時候寧可續用舊的，也不要把好好的快取覆蓋成空的。
      if (events.isEmpty) return cached?.events ?? const [];

      await _writeCache(events, now ?? DateTime.now());
      return events;
    } catch (_) {
      return cached?.events ?? const [];
    }
  }

  bool _isFresh(DateTime fetchedAt, DateTime? now) =>
      (now ?? DateTime.now()).difference(fetchedAt).abs() < maxAge;

  Future<({List<CalendarEvent> events, DateTime fetchedAt})?>
      _readCache() async {
    final prefs = await _p;
    final raw = prefs.getString(_kEvents);
    final at = prefs.getString(_kFetchedAt);
    if (raw == null || at == null) return null;
    try {
      return (
        events: [
          for (final e in jsonDecode(raw) as List)
            CalendarEvent.fromJson((e as Map).cast<String, dynamic>()),
        ],
        fetchedAt: DateTime.parse(at),
      );
    } catch (_) {
      // 舊版寫的格式讀不動就當作沒有。壞掉的快取不該讓首頁開不起來。
      return null;
    }
  }

  Future<void> _writeCache(List<CalendarEvent> events, DateTime at) async {
    final prefs = await _p;
    await prefs.setString(
      _kEvents,
      jsonEncode([for (final e in events) e.toJson()]),
    );
    await prefs.setString(_kFetchedAt, at.toIso8601String());
  }
}

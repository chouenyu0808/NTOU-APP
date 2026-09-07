import 'package:shared_preferences/shared_preferences.dart';

import '../transit/nearest_stop.dart';

/// 交通頁的本機偏好：釘起來的路線、收起來的站牌。
///
/// 兩者都存在本機，跟學校帳號無關，也不會送去任何地方 —— 這一頁本來就
/// 不用登入。存的都只是名字和 id，沒有任何個人資料。
class TransitPrefsStore {
  TransitPrefsStore({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= _injected ?? await SharedPreferences.getInstance();

  /// 釘起來的路線。
  ///
  /// **只存路線名（`103`、`1813`），不存站牌。** 同一條路線在海大體育館和
  /// 濱海校門都會出現，而會搭 103 的人在哪一站都想先看到 103 —— 綁定站牌
  /// 只會讓他在每個站牌各釘一次。
  static const _favoritesKey = 'transit.favorites';

  /// 收起來的站牌，存的是 `transit.json` 裡的 `id`。
  ///
  /// **用 id 不用站名**：站名哪天被改掉（或 TDX 改了），收合狀態不該跟著
  /// 錯亂 —— 那會變成使用者收起來的站自己跳回來，而且沒有理由。
  static const _collapsedKey = 'transit.collapsed';

  /// 使用者指定小組件優先顯示哪一站，存的是 `transit.json` 的 `id`。
  ///
  /// 空字串 = 沒指定，那時候才輪到定位。**釘選優先於定位**：他每天搭的就是
  /// 那一站，而定位在校內只差幾百公尺，本來就比他自己知道的少。
  static const _pinnedStopKey = 'transit.pinned_stop';

  /// 上次量到的位置（`緯度|經度|epoch millis`）。
  ///
  /// **為什麼要存**：小組件在背景更新，而 Android 10 之後背景取位置要
  /// `ACCESS_BACKGROUND_LOCATION`（Google Play 要人工審查）。所以位置只能
  /// 在 App 於前景時量，記下來給小組件用。
  ///
  /// 存的是**經緯度不是站名**：站的清單會改，而座標是一個獨立的事實。
  static const _placeKey = 'transit.last_place';

  Future<Set<String>> readFavorites() => _read(_favoritesKey);
  Future<Set<String>> toggleFavorite(String route) =>
      _toggle(_favoritesKey, route);

  Future<Set<String>> readCollapsed() => _read(_collapsedKey);
  Future<Set<String>> toggleCollapsed(String stopId) =>
      _toggle(_collapsedKey, stopId);

  /// 釘選的站 id。沒釘過就是 null。
  Future<String?> readPinnedStop() async {
    final v = (await _p).getString(_pinnedStopKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 釘一站，或再按一次取消。回傳變更後的值（null = 取消了）。
  Future<String?> togglePinnedStop(String stopId) async {
    final prefs = await _p;
    final now = prefs.getString(_pinnedStopKey);
    final next = now == stopId ? null : stopId;
    if (next == null) {
      await prefs.remove(_pinnedStopKey);
    } else {
      await prefs.setString(_pinnedStopKey, next);
    }
    return next;
  }

  Future<LastKnownPlace?> readPlace() async =>
      LastKnownPlace.decode((await _p).getString(_placeKey));

  Future<void> writePlace(LastKnownPlace place) async =>
      (await _p).setString(_placeKey, place.encode());

  Future<Set<String>> _read(String key) async =>
      ((await _p).getStringList(key) ?? const []).toSet();

  /// 加上去或拿掉，回傳變更後的整份清單。
  ///
  /// 回傳整份而不是回傳「現在是不是開著」，是因為畫面要拿它重畫 ——
  /// 讓呼叫端自己去猜新狀態，遲早會跟實際存下來的東西不一致。
  Future<Set<String>> _toggle(String key, String value) async {
    if (value.isEmpty) return _read(key);
    final prefs = await _p;
    final now = (prefs.getStringList(key) ?? const []).toSet();
    if (!now.remove(value)) now.add(value);
    // 排序後再存：順序穩定的話比對和除錯都容易些。
    await prefs.setStringList(key, now.toList()..sort());
    return now;
  }
}

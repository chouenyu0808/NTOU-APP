import 'package:shared_preferences/shared_preferences.dart';

/// 使用者釘起來的公車路線。
///
/// **只存路線名（`103`、`1813`），不存站牌。** 同一條路線在海大體育館和
/// 濱海校門都會出現，而會搭 103 的人在哪一站都想先看到 103 —— 綁定站牌
/// 只會讓他在每個站牌各釘一次。
///
/// 存在本機，跟學校帳號無關，也不會送去任何地方。這一頁本來就不用登入。
class FavoriteRouteStore {
  FavoriteRouteStore({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= _injected ?? await SharedPreferences.getInstance();

  static const _key = 'transit.favorites';

  Future<Set<String>> read() async =>
      ((await _p).getStringList(_key) ?? const []).toSet();

  /// 釘上去或取消，回傳變更後的整份清單。
  ///
  /// 回傳整份而不是回傳「現在是不是最愛」，是因為畫面要拿它重新排序 ——
  /// 讓呼叫端自己去猜新狀態，遲早會跟實際存下來的東西不一致。
  Future<Set<String>> toggle(String route) async {
    final prefs = await _p;
    final now = (prefs.getStringList(_key) ?? const []).toSet();
    if (!now.remove(route)) now.add(route);
    // 排序後再存：SharedPreferences 存的是清單，順序穩定的話
    // 比對和除錯都容易些。
    await prefs.setStringList(_key, now.toList()..sort());
    return now;
  }
}

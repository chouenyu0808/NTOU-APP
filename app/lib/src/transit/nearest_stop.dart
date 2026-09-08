import 'dart:math' as math;

import 'transit_models.dart';

/// 使用者上次被定位到的地方。
///
/// **帶著時間**，因為小組件用得到它而小組件拿不到當下的位置：Android 10 之後
/// 背景取位置要 `ACCESS_BACKGROUND_LOCATION`（Google Play 要人工審查），
/// 所以小組件只能用「App 上次在前景時記下來的」。那份可能是幾小時前的。
class LastKnownPlace {
  const LastKnownPlace({
    required this.lat,
    required this.lon,
    required this.at,
  });

  final double lat;
  final double lon;

  /// 什麼時候量到的。
  final DateTime at;

  /// 存成一行字（`緯度|經度|epoch millis`）。
  String encode() => '$lat|$lon|${at.millisecondsSinceEpoch}';

  static LastKnownPlace? decode(String? raw) {
    final parts = raw?.split('|');
    if (parts == null || parts.length != 3) return null;
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    final ms = int.tryParse(parts[2]);
    if (lat == null || lon == null || ms == null) return null;
    return LastKnownPlace(
      lat: lat,
      lon: lon,
      at: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}

/// 距離與「最近的站」。
///
/// 抽成純函式是刻意的：這一段的錯誤**在畫面上完全看不出來** —— 挑錯站的話
/// 顯示的是一個真實存在、看起來完全合理的站名，只是不是使用者站的那一個。
/// 所以它不埋在 UI 裡，獨立測。
class NearestStop {
  const NearestStop._();

  /// 兩點之間的公尺數。
  ///
  /// 用等距圓柱近似（把經度乘上 cos(緯度)）而不是 haversine：這裡要比的
  /// 距離最遠不過幾公里，在那個尺度兩者差不到千分之一，而這個看得懂。
  static double metresBetween(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const metresPerDegree = 111320.0;
    final dy = (lat2 - lat1) * metresPerDegree;
    final dx =
        (lon2 - lon1) * metresPerDegree * math.cos(lat1 * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// [stops] 裡離 [place] 最近的那一站。
  ///
  /// 回 null 的情況：沒有位置、沒有任何一站帶座標。**那時候呼叫端要照原本的
  /// 順序顯示，不要猜一個** —— 猜出來的「最近的站」跟真的長得一模一樣。
  ///
  /// 沒有座標的站不參與比較（見 [TransitStop.hasPosition]）。
  static TransitStop? of(List<TransitStop> stops, LastKnownPlace? place) {
    if (place == null) return null;

    TransitStop? best;
    var bestMetres = double.infinity;
    for (final s in stops) {
      if (!s.hasPosition) continue;
      final m = metresBetween(place.lat, place.lon, s.lat!, s.lon!);
      if (m < bestMetres) {
        bestMetres = m;
        best = s;
      }
    }
    return best;
  }

  /// 小組件要顯示哪一站，以及**那是不是使用者自己指定的**。
  ///
  /// 順序是**釘選優先於定位**：使用者自己指定過的話，那就是他要的，
  /// 定位不該把它蓋掉 —— 他每天搭的就是那一站，而定位在校內只差幾百公尺，
  /// 本來就比他自己知道的少。
  ///
  /// `pinned` 決定小組件是「只顯示這一站」還是「把它排最前面」，兩者差很多：
  ///
  /// - **釘選是一句明確的話**（「我只在乎這一站」），所以只顯示它 ——
  ///   而且那一站的路線可以多列幾條，那正是他要的。
  /// - **定位是一個猜測**。位置可能是幾小時前在別的地方量的（小組件拿不到
  ///   當下的位置，見 [LastKnownPlace]）。猜錯的時候只顯示一站，等於把
  ///   使用者要的東西整個藏起來；排最前面則最多只是順序不理想。
  ///
  /// 兩個都沒有就 stop 是 null，照設定檔原本的順序。
  static ({TransitStop? stop, bool pinned}) preferred(
    List<TransitStop> stops, {
    String? pinnedId,
    LastKnownPlace? place,
  }) {
    if (pinnedId != null && pinnedId.isNotEmpty) {
      for (final s in stops) {
        if (s.id == pinnedId) return (stop: s, pinned: true);
      }
      // 釘的那一站不在設定檔裡了（改版拿掉、改名）——**不要退回定位**，
      // 那會變成「我明明釘了，它自己跑掉」。照原本順序，讓使用者重新釘。
      return (stop: null, pinned: false);
    }
    return (stop: of(stops, place), pinned: false);
  }
}

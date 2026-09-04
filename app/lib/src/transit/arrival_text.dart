import 'transit_models.dart';

/// 到站資料 → 畫面上那幾句話。
///
/// 這裡的每一段本來都是 `transit_page.dart` 的私有方法。桌面小組件要說
/// **一模一樣的話**才抽出來 —— 兩邊各寫一份的話，同一班車在 App 裡是
/// 「往 八斗子車站（經 海大濱海校門）」、在桌面上是「往 八斗子車站」，
/// 使用者會以為其中一邊壞了，而且沒有任何測試會紅。
///
/// [ArrivalLabel] 沒有搬進來 —— 它本來就在 `transit_models.dart` 裡了。
class ArrivalText {
  const ArrivalText._();

  /// 「往哪裡」那一行。
  ///
  /// 平常就是終點站。**但同一條路線在同一張卡片上出現兩次的時候，終點站
  /// 分不出方向** —— 103 是環狀線，馬路兩邊的車終點都是八斗子車站。那時候
  /// 補上下一站：一邊「經 海大濱海校門」（往市區），一邊「經 北寧路」
  /// （往八斗子），使用者才知道要站哪一邊。
  ///
  /// 連終點都查不到時，下一站就是唯一的線索，直接拿它當方向講。
  static String towards(BusArrival arrival, {required bool needsDirection}) {
    final to = arrival.destination;
    final next = arrival.nextStop;
    if (to.isEmpty) return next.isEmpty ? '' : '往 $next 方向';
    if (needsDirection && next.isNotEmpty) return '往 $to（經 $next）';
    return '往 $to';
  }

  /// 每條路線在這一站出現幾次。
  ///
  /// 出現不只一次 = 馬路兩邊的兩個站牌都停這條路線。那兩列的終點站是一樣的
  /// （103 是環狀線），所以得額外標出方向，否則看起來一模一樣。
  static Map<String, int> routeCounts(StopBoard board) {
    final counts = <String, int>{};
    for (final b in board.boardableBuses) {
      counts[b.routeName] = (counts[b.routeName] ?? 0) + 1;
    }
    return counts;
  }

  /// 這一站沒有可搭乘的班次時要說的話。
  ///
  /// **「都到站收班」和「沒有班次」是兩件事**，對使用者的意義完全不同
  /// （一個是等下一班，一個是今天沒有了），所以分開講。
  static String empty(StopBoard board) {
    if (board.endingHere > 0) {
      return '只有 ${board.endingHere} 班到站後收班的車，沒有可搭乘的班次';
    }
    return board.stop.kind == TransitStopKind.train
        ? '目前沒有即將進站的列車'
        : '目前沒有班次資訊';
  }
}

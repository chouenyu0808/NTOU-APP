import '../transit/arrival_text.dart';
import '../transit/transit_config.dart';
import '../transit/transit_models.dart';

/// 桌面小組件上的一班車。
///
/// 跟 [TimetableWidgetRow] 一樣，全部是**已經算好的字串** —— 秒數換算成
/// 「12 分」、方向拼成「往 八斗子車站（經 海大濱海校門）」都在 Dart 這邊
/// 做完。小組件那一端不碰 TDX 的任何欄位。
class TransitWidgetRow {
  const TransitWidgetRow({
    required this.route,
    required this.towards,
    required this.eta,
    required this.tone,
    required this.favorite,
  });

  /// 「103」、「1579」。
  final String route;

  /// 「往 八斗子車站（經 海大濱海校門）」。查不到就是空字串，那時候不猜。
  final String towards;

  /// 「12 分」／「進站中」／「末班已過」。
  final String eta;

  final ArrivalTone tone;

  /// 使用者在 App 裡釘起來的路線。畫面上會排前面。
  final bool favorite;

  Map<String, dynamic> toJson() => {
        'route': route,
        'towards': towards,
        'eta': eta,
        'tone': tone.name,
        'favorite': favorite,
      };

  static TransitWidgetRow fromJson(Map<String, dynamic> j) => TransitWidgetRow(
        route: j['route'] as String? ?? '',
        towards: j['towards'] as String? ?? '',
        eta: j['eta'] as String? ?? '',
        tone: ArrivalTone.values.firstWhere(
          (t) => t.name == j['tone'],
          orElse: () => ArrivalTone.idle,
        ),
        favorite: j['favorite'] as bool? ?? false,
      );
}

/// 小組件上的一站。
class TransitWidgetStop {
  const TransitWidgetStop({
    required this.name,
    required this.rows,
    this.note,
  });

  final String name;
  final List<TransitWidgetRow> rows;

  /// 沒有可搭乘的班次時那句話，或這一站的錯誤。null = 有車。
  ///
  /// **一站失敗不影響其他站**（五個站是各自獨立的查詢），所以錯誤掛在
  /// 站上而不是整份 payload 上。
  final String? note;

  Map<String, dynamic> toJson() => {
        'name': name,
        'rows': [for (final r in rows) r.toJson()],
        if (note != null) 'note': note,
      };

  static TransitWidgetStop fromJson(Map<String, dynamic> j) => TransitWidgetStop(
        name: j['name'] as String? ?? '',
        rows: [
          for (final r in (j['rows'] as List? ?? const []))
            TransitWidgetRow.fromJson(r as Map<String, dynamic>),
        ],
        note: j['note'] as String?,
      );
}

/// 交通小組件要顯示的一整份東西。
///
/// **這份會存下來。** 跟課表那份不一樣 —— 課表的來源（[TimetableCache]）
/// 本來就在本機，隨時重算得出來；交通的來源是網路，抓失敗的時候我們手上
/// 只剩上一次的結果。存著才能在失敗時照樣畫出「上次的資料 + 更新失敗」，
/// 而不是把畫面清空或留一張時間戳已經騙人的舊圖。
class TransitWidgetPayload {
  const TransitWidgetPayload({
    required this.stops,
    this.updatedAt,
    this.refreshFailed = false,
  });

  final List<TransitWidgetStop> stops;

  /// 這份資料是什麼時候抓的。
  ///
  /// **一定要畫在小組件上。** Android 小組件最快也只能 30 分鐘自動更新一次
  /// （`updatePeriodMillis` 的系統下限），所以上面的數字**必然是舊的** ——
  /// 不標時間的話「12 分」看起來跟即時的一模一樣，使用者會照著出門。
  final DateTime? updatedAt;

  /// 這次更新失敗了，畫面上是上一次的資料。
  ///
  /// 失敗時不覆寫 [updatedAt] —— 那個時間講的是「資料多舊」，
  /// 拿失敗的時刻蓋上去等於謊報新鮮度。
  final bool refreshFailed;

  bool get isEmpty => stops.every((s) => s.rows.isEmpty);

  TransitWidgetPayload copyWith({bool? refreshFailed}) => TransitWidgetPayload(
        stops: stops,
        updatedAt: updatedAt,
        refreshFailed: refreshFailed ?? this.refreshFailed,
      );

  Map<String, dynamic> toJson() => {
        'stops': [for (final s in stops) s.toJson()],
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
        'refresh_failed': refreshFailed,
      };

  static TransitWidgetPayload fromJson(Map<String, dynamic> j) =>
      TransitWidgetPayload(
        stops: [
          for (final s in (j['stops'] as List? ?? const []))
            TransitWidgetStop.fromJson(s as Map<String, dynamic>),
        ],
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
        refreshFailed: j['refresh_failed'] as bool? ?? false,
      );
}

/// 抓回來的看板 → 小組件要顯示的東西。
///
/// [favorites] 是使用者在 App 裡釘起來的路線名。**釘起來的排前面，
/// 兩組各自照到站時間排**，跟交通分頁同一套 —— 釘 103 的人要的是
/// 「一眼找到 103」，不是「103 在最上面但下面亂掉」。
///
/// 小組件放不下所有東西，但**取捨在畫的那一層做，不在這裡**。這裡照實
/// 全部帶著，畫面按實際尺寸決定塞得下幾列 —— 在這裡先砍掉的話，使用者
/// 把小組件拉大也不會多出東西來。
TransitWidgetPayload buildTransitWidgetPayload({
  required List<StopBoard> boards,
  required TransitConfig config,
  Set<String> favorites = const {},
  required DateTime now,
}) {
  final stops = <TransitWidgetStop>[];

  for (final board in boards) {
    final counts = ArrivalText.routeCounts(board);
    final rows = <TransitWidgetRow>[];

    for (final b in _sortedBuses(board, favorites)) {
      final label = ArrivalLabel.of(
        b.estimateSeconds,
        b.stopStatus,
        config.stopStatus,
      );
      rows.add(
        TransitWidgetRow(
          route: b.routeName,
          towards: ArrivalText.towards(
            b,
            needsDirection: (counts[b.routeName] ?? 0) > 1,
          ),
          eta: label.text,
          tone: label.tone,
          favorite: favorites.contains(b.routeName),
        ),
      );
    }

    for (final t in board.boardableTrains) {
      rows.add(
        TransitWidgetRow(
          route: t.trainType.isEmpty ? t.trainNo : t.trainType,
          towards: t.destination.isEmpty ? '' : '往 ${t.destination}',
          // 列車給的是表定時間，不是「還有幾分」—— 誤點另外標。
          // 換算成「還有 N 分」會把誤點吃掉，那是使用者最需要看到的東西。
          eta: t.delayMinutes > 0
              ? '${t.scheduledTime} 誤點 ${t.delayMinutes} 分'
              : t.scheduledTime,
          tone: t.delayMinutes > 0 ? ArrivalTone.idle : ArrivalTone.normal,
          favorite: false,
        ),
      );
    }

    stops.add(
      TransitWidgetStop(
        name: board.stop.name,
        rows: rows,
        // 錯誤優先：這一站根本沒問到，說「沒有班次」是錯的。
        note: board.error ?? (rows.isEmpty ? ArrivalText.empty(board) : null),
      ),
    );
  }

  return TransitWidgetPayload(stops: stops, updatedAt: now);
}

/// 釘起來的排前面，兩組各自照到站時間。
///
/// [StopBoard.boardableBuses] 已經是照時間排好的（repository 那邊排的），
/// 所以這裡只要穩定地拆成兩堆再接起來。
List<BusArrival> _sortedBuses(StopBoard board, Set<String> favorites) {
  if (favorites.isEmpty) return board.boardableBuses;
  final pinned = <BusArrival>[];
  final rest = <BusArrival>[];
  for (final b in board.boardableBuses) {
    (favorites.contains(b.routeName) ? pinned : rest).add(b);
  }
  return [...pinned, ...rest];
}

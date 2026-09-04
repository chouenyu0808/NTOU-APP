/// 交通看板的資料模型。
///
/// 這一批東西跟學校的 AIS session 完全無關 —— 資料來自交通部的 TDX，
/// 不用登入就看得到。所以交通分頁在沒登入、甚至學校系統掛掉的時候照常能用。
library;

/// 站點是哪一種。決定要打 TDX 的哪一組 API，以及畫面上長什麼樣。
enum TransitStopKind {
  /// 市區公車（基隆市公車）。海大那三個站牌都是這種。
  cityBus,

  /// 國道客運 / 公路客運。基隆轉運站。
  interCityBus,

  /// 台鐵。
  train;

  static TransitStopKind parse(String? raw) => switch (raw) {
        'city_bus' => TransitStopKind.cityBus,
        'intercity_bus' => TransitStopKind.interCityBus,
        'train' => TransitStopKind.train,
        _ => TransitStopKind.cityBus,
      };
}

/// 一個站點的定義（來自 `assets/transit.json`）。
class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.kind,
    this.extraKinds = const [],
    this.city = 'Keelung',
    this.matchNames = const [],
    this.stationId = '',
    this.stationName = '',
    this.note,
  });

  final String id;

  /// 畫面上顯示的名字（「海大體育館」）。
  final String name;

  final TransitStopKind kind;

  /// 這一站還要問哪些來源。
  ///
  /// **一個站牌可能同時有市區公車和國道客運。** 海大體育館就是：基隆市公車
  /// 103/104/108 在 `EstimatedTimeOfArrival/City/Keelung`，但首都客運 1579
  /// （圓山轉運站直達）在 `EstimatedTimeOfArrival/InterCity` —— 只問前者的話
  /// 1579 永遠不會出現，而畫面上看起來就只是「這站沒有這條路線」。
  ///
  /// 多問一種來源**不會多打請求**：所有站的國道客運查詢會跟基隆轉運站那次
  /// 合併成同一個，只是 filter 裡多幾個站名。
  final List<TransitStopKind> extraKinds;

  /// 這一站要問的全部來源。
  List<TransitStopKind> get kinds => [kind, ...extraKinds];

  /// TDX 的縣市代碼。基隆市是 `Keelung`。
  final String city;

  /// 拿去跟 TDX 回傳的站名比對的候選名稱。
  ///
  /// **不只放一個**：同一個站牌在不同資料來源裡可能叫「海大濱海校門」
  /// 也可能叫「海洋大學濱海校門」，去問的時候不知道對方用哪個。
  final List<String> matchNames;

  /// 台鐵車站代碼。空字串代表還沒查到，要用 [stationName] 去問。
  final String stationId;
  final String stationName;

  /// 給使用者看的補充（哪幾條路線會停）。
  final String? note;

  factory TransitStop.fromJson(Map<String, dynamic> json) => TransitStop(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        kind: TransitStopKind.parse(json['kind'] as String?),
        extraKinds: [
          for (final k in (json['also'] as List?) ?? const [])
            if (k is String) TransitStopKind.parse(k),
        ],
        city: json['city'] as String? ?? 'Keelung',
        matchNames: [
          for (final n in (json['match_names'] as List?) ?? const [])
            if (n is String) n,
        ],
        stationId: json['station_id'] as String? ?? '',
        stationName: json['station_name'] as String? ?? '',
        note: json['note'] as String?,
      );

  /// 比對用的名字集合。[name] 一定包含在內，不用在 JSON 裡重複寫一次。
  List<String> get allNames => [
        name,
        if (stationName.isNotEmpty) stationName,
        ...matchNames,
      ];
}

/// 一班公車還有多久到這一站。
class BusArrival {
  const BusArrival({
    required this.routeName,
    this.destination = '',
    this.estimateSeconds,
    this.stopStatus = 0,
    this.plateNumber = '',
    this.stopsAway,
    this.isLastBus = false,
    this.nextStop = '',
    this.fromIntercity = false,
    this.endsHere = false,
  });

  /// 路線名（`103`、`1579`）。
  final String routeName;

  /// 往哪裡。TDX 的到站資料本身不帶終點站，是另外從路線資料補上的，
  /// 補不到就是空字串 —— 畫面上那一行會收起來，不顯示「往 」。
  final String destination;

  /// 還有幾秒到。**null 代表沒有預估值**，不是 0。
  ///
  /// 沒有預估值的原因看 [stopStatus]：還沒發車、末班過了、今天不營運，
  /// 都會是 null。把 null 當 0 處理的話畫面會顯示「進站中」——
  /// 使用者會為了一班根本不存在的車跑去站牌等。
  final int? estimateSeconds;

  /// TDX 的 `StopStatus`。0 = 正常，其餘見 `transit.json` 的對照表。
  final int stopStatus;

  final String plateNumber;

  /// 這班車離這一站還有幾站（TDX 的 `StopCountDown`）。
  ///
  /// **這是站數不是秒數。** 同一筆資料裡 `EstimateTime: 725` 配
  /// `StopCountDown: 19` —— 十二分鐘、十九站。當成時間用會變成「19 秒」。
  ///
  /// 沒有車的那幾筆這個值是 0，跟「已經到站了」分不出來，所以畫面上
  /// 只在真的有預估時間的時候才顯示它。
  final int? stopsAway;

  /// 這一班是不是這條路線今天的最後一班（TDX 的 `IsLastBus`）。
  ///
  /// **注意它的意思不是「還會來的末班車」。** 它標的是「這個班次是今天
  /// 最後一班」，跟那班車還在不在路上無關 —— 深夜抓下來的 15 筆裡有 11 筆
  /// 帶著 true，因為那個時間剩下的班次本來就都是末班，而且大多已經開走了。
  ///
  /// 所以畫面上只在 [isRunning] 的時候才顯示它。不擋的話深夜整張卡片會有
  /// 十幾行同時喊「末班車」，那是雜訊；擋掉之後它才會變成它該有的意思：
  /// **這是最後一班，而且還沒走。** 對學生來說那是整排資訊裡最要緊的一件事。
  final bool isLastBus;

  /// 這班車離開這一站之後的下一站。
  ///
  /// **拿來分辨馬路兩邊。** 「海大體育館」這個站名在 TDX 裡是兩個實體站牌：
  /// `KEE306429` 的下一站是海大濱海校門（往市區），`KEE306430` 的下一站是
  /// 北寧路（往八斗子）。兩邊的終點站都是八斗子車站（103 是環狀線），
  /// 所以**終點分不出方向，下一站才分得出**。
  ///
  /// 只有在同一張卡片上同一條路線出現不只一次的時候才會去查，因為那時候
  /// 才需要分辨。查不到就是空字串。
  final String nextStop;

  /// 這一筆是從國道客運那個端點回來的。
  ///
  /// **點進路線詳情時要靠它決定去問哪一組 API。** 不能用站牌的 `kind` 判斷 ——
  /// 海大體育館的主要類別是市區公車，但 1579、1813 是國道客運，用站牌類別
  /// 去問會查到基隆市公車那邊，回 0 筆，畫面上變成「查不到這條路線的站序」。
  ///
  /// 來源要由「這班車是哪個查詢回來的」決定，那是唯一不會錯的依據。
  final bool fromIntercity;

  /// 這一站就是這班車的終點 —— 它到了之後就收班。
  ///
  /// **這種車搭不了，所以畫面上不顯示。** 基隆轉運站有好幾條國道客運是
  /// 以那裡為終點的（1800、1813 等），列出來只是佔位子，使用者還得一條條
  /// 看過去才發現搭不了。
  final bool endsHere;

  /// 這一筆到底有沒有車。
  ///
  /// 沒有預估時間就是沒有車在路上（末班已過、還沒發車、今天不營運）。
  /// 「還有幾站」和「末班車」都只在有車的時候才有意義。
  bool get isRunning => estimateSeconds != null;

  /// 排序用的鍵：有預估值的照時間排在前面，沒有的沉到後面。
  int get sortKey => estimateSeconds ?? 1 << 30;
}

/// 一班列車。
///
/// [endsHere] 是「這一站就是它的終點」。基隆是端點站，所以**一整批列車都是
/// 這樣** —— 那些車到站就收班，搭不了。畫面上會濾掉，但要記得數量：
/// 全部濾光的時候必須說清楚是「只有收班的車」，不能說成「沒有列車」。
class TrainDeparture {
  const TrainDeparture({
    this.endsHere = false,
    required this.trainNo,
    this.trainType = '',
    this.destination = '',
    this.scheduledTime = '',
    this.delayMinutes = 0,
    this.platform = '',
  });

  /// 車次號碼。
  /// 這一站就是終點，到了就收班 —— 搭不了，畫面上不顯示。
  final bool endsHere;

  final String trainNo;

  /// 車種（自強、區間）。
  final String trainType;

  /// 終點站。
  final String destination;

  /// 表定時間，`HH:mm`。
  final String scheduledTime;

  /// 誤點幾分鐘。0 = 準點。
  final int delayMinutes;

  final String platform;
}

/// 一個站的看板：站點定義 + 這一刻的內容。
class StopBoard {
  const StopBoard({
    required this.stop,
    this.buses = const [],
    this.trains = const [],
    this.updatedAt,
    this.error,
  });

  final TransitStop stop;
  final List<BusArrival> buses;
  final List<TrainDeparture> trains;

  /// 這份資料是什麼時候抓的。畫面上要標 —— 交通資訊過期一分鐘就沒有意義，
  /// 使用者得看得出自己在看的是不是舊的。
  final DateTime? updatedAt;

  /// 畫面上真的要顯示的公車：**以本站為終點的搭不了，不畫。**
  ///
  /// 基隆轉運站有好幾條國道客運以那裡為終點，列出來只是佔位子。
  /// 資料層照實回報（見 [BusArrival.endsHere]），要不要畫是這裡決定的。
  List<BusArrival> get boardableBuses => [
        for (final b in buses)
          if (!b.endsHere) b,
      ];

  /// 同上，列車的。基隆是端點站，深夜可能整批都是這種。
  List<TrainDeparture> get boardableTrains => [
        for (final t in trains)
          if (!t.endsHere) t,
      ];

  /// 被藏起來的「到站就收班」的班次有幾個。
  ///
  /// **全部被藏起來的時候要靠它講實話。** 說「目前沒有即將進站的列車」
  /// 是錯的 —— 明明有車，只是都到站收班。那兩件事對使用者的意義完全不同。
  int get endingHere =>
      (buses.length - boardableBuses.length) +
      (trains.length - boardableTrains.length);

  /// 這一站抓失敗的原因。**一站失敗不影響其他站** ——
  /// 五個站是五次獨立的查詢，台鐵掛了公車還是要能看。
  final String? error;

  bool get isEmpty => buses.isEmpty && trains.isEmpty;

  StopBoard copyWith({
    List<BusArrival>? buses,
    List<TrainDeparture>? trains,
    DateTime? updatedAt,
    String? error,
    bool clearError = false,
  }) =>
      StopBoard(
        stop: stop,
        buses: buses ?? this.buses,
        trains: trains ?? this.trains,
        updatedAt: updatedAt ?? this.updatedAt,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 秒數 → 畫面上那句話。
///
/// 這是整個交通分頁唯一一段「會被使用者拿來做決定」的邏輯 ——
/// 看到「進站中」是用跑的，看到「12 分」是可以先去買早餐的。所以它獨立
/// 出來、獨立測，不埋在 widget 的 build 裡。
///
/// 分界抄 Bus+ 的習慣：進站中 / 將到站 / N 分。**不做「N 分 M 秒」** ——
/// 公車的預估本來就有一兩分鐘的誤差，把秒數寫出來是假的精確。
class ArrivalLabel {
  const ArrivalLabel(this.text, this.tone);

  final String text;
  final ArrivalTone tone;

  /// [status] 是 TDX 的 StopStatus，[statusNames] 是 `transit.json` 的對照表。
  static ArrivalLabel of(
    int? seconds,
    int status,
    Map<String, String> statusNames,
  ) {
    // 沒有預估值 —— 用狀態碼解釋為什麼。認不得的代碼原樣顯示，不猜。
    if (seconds == null || seconds < 0) {
      if (status == 0) return const ArrivalLabel('--', ArrivalTone.idle);
      final name = statusNames['$status'];
      return ArrivalLabel(name ?? '狀態 $status', ArrivalTone.idle);
    }
    if (seconds < 30) return const ArrivalLabel('進站中', ArrivalTone.now);
    if (seconds < 120) return const ArrivalLabel('將到站', ArrivalTone.soon);
    return ArrivalLabel('${seconds ~/ 60} 分', ArrivalTone.normal);
  }
}

/// 到站時間的輕重。畫面用它決定顏色，不在 widget 裡重算一次分界。
enum ArrivalTone { now, soon, normal, idle }

// ------------------------------------------------- 點進一條路線之後看到的東西

/// 路線上的一個站牌。
class RouteStop {
  const RouteStop({
    required this.stopUid,
    required this.name,
    required this.sequence,
    this.estimateSeconds,
    this.stopStatus = 0,
  });

  final String stopUid;
  final String name;

  /// 車還有多久到**這一站**。null 代表沒有預估值（原因看 [stopStatus]）。
  ///
  /// 跟看板上那個數字是同一種東西，只是那邊問的是「一個站牌的所有路線」，
  /// 這邊問的是「一條路線的所有站牌」—— 同一個端點，換個 filter。
  final int? estimateSeconds;

  /// TDX 的 `StopStatus`。沒有預估值時靠它解釋為什麼（末班已過、尚未發車…）。
  final int stopStatus;

  /// 這是這條子路線的第幾站（TDX 的 `StopSequence`，從 1 開始）。
  ///
  /// 公車的即時位置也是用同一個編號回報的，兩邊靠它對上。
  final int sequence;
}

/// 一台正在跑的車現在在哪。
class BusPosition {
  const BusPosition({
    required this.plate,
    required this.subRouteUid,
    required this.stopSequence,
    this.stopName = '',
    this.leaving = false,
  });

  final String plate;

  /// 這台車跑的是哪一條子路線。
  ///
  /// **配對一定要用這個，不能只用方向。** 103 是環狀線，它的兩條站序
  /// 都是 Direction 0 —— 只看方向的話，車會被畫到錯的那一條上面。
  final String subRouteUid;

  /// 現在在第幾站。跟 [RouteStop.sequence] 對上就知道畫在哪一列。
  final int stopSequence;
  final String stopName;

  /// 已經離站了（TDX 的 `A2EventType`：0 是進站、1 是離站）。
  ///
  /// 離站代表它正往下一站移動，畫面上講「已離開」比「在這一站」準確。
  final bool leaving;
}

/// 一條子路線：一串站序，加上現在跑在上面的車。
class RouteVariant {
  const RouteVariant({
    required this.subRouteUid,
    required this.subRouteName,
    required this.direction,
    this.stops = const [],
    this.buses = const [],
  });

  final String subRouteUid;
  final String subRouteName;
  final int direction;
  final List<RouteStop> stops;
  final List<BusPosition> buses;

  /// 這條子路線開到哪為止 —— 拿來當分頁標題。
  String get destination => stops.isEmpty ? '' : stops.last.name;

  RouteVariant withBuses(List<BusPosition> buses) => RouteVariant(
        subRouteUid: subRouteUid,
        subRouteName: subRouteName,
        direction: direction,
        stops: stops,
        buses: buses,
      );

  RouteVariant withStops(List<RouteStop> stops) => RouteVariant(
        subRouteUid: subRouteUid,
        subRouteName: subRouteName,
        direction: direction,
        stops: stops,
        buses: buses,
      );
}

/// 點進一條路線看到的全部。
class RouteDetail {
  const RouteDetail({
    required this.routeName,
    this.variants = const [],
    this.error,
  });

  final String routeName;

  /// 這條路線有幾種走法。環狀線會有兩條站序、去回程的路線也是兩條。
  final List<RouteVariant> variants;

  /// 抓不到時給使用者看的那句話。
  final String? error;

  bool get isEmpty => variants.isEmpty;
}

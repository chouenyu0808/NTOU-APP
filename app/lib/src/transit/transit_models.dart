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

  /// 排序用的鍵：有預估值的照時間排在前面，沒有的沉到後面。
  int get sortKey => estimateSeconds ?? 1 << 30;
}

/// 一班列車。
class TrainDeparture {
  const TrainDeparture({
    required this.trainNo,
    this.trainType = '',
    this.destination = '',
    this.scheduledTime = '',
    this.delayMinutes = 0,
    this.platform = '',
  });

  /// 車次號碼。
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

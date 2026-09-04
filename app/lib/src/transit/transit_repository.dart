import 'transit_config.dart';
import 'transit_models.dart';
import 'tdx_client.dart';

/// TDX 的回應 → 畫面要的模型。
///
/// ## 為什麼這一整份都寫得這麼「寬容」
///
/// TDX 同時活著 v2 和 v3 兩代 API，而兩代的形狀不一樣：
///
/// - 多語系欄位：v2 是 `{"Zh_tw": "103", "En": "103"}`，v3 有的地方扁平成
///   `"103"`。
/// - 外層包裝：v2 回裸陣列，v3 包成 `{"TrainLiveBoards": [...]}`。
/// - 同一個意思的欄位在不同端點叫不同名字（`StopName` / `StationName`、
///   `EstimateTime` / `EstimatedTime`）。
///
/// 公開的 swagger 檔在 schema 那一段是截斷的，而沒有金鑰打不到真實回應 ——
/// 所以這裡的欄位名一開始全都是**候選清單**而不是單一答案。賭一個名字的話，
/// 猜錯的下場是解析出一片空白，而畫面上「解析失敗」跟「這站現在沒車」
/// 長得一模一樣，沒有人會發現。
///
/// ## 現在對到哪了（2026-09-03）
///
/// - **公車（市區 + 國道）：對完了。** 拿真實金鑰跑過 `spike/tdx.py --save`，
///   四個站的回應存在 `spike/fixtures/tdx/`，[_busFrom] 已經收斂成確定的
///   欄位名，不再是候選。
/// - **台鐵：對完了。** 第一次跑被 429 擋掉，補跑之後 [_trainFrom] 也收斂了。
///   回應是 v3 的形狀（包在 `StationLiveBoards` 底下），`unwrap` 吃得下。
class TransitRepository {
  TransitRepository({required this.config, required this.client});

  final TransitConfig config;
  final TdxClient client;

  bool get isConfigured => client.isConfigured;

  /// 抓一個站的看板。**不丟例外** —— 失敗包成 [StopBoard.error] 回來。
  ///
  /// 台鐵那次爆掉不該讓公車站也跟著空白。
  Future<StopBoard> board(TransitStop stop) async {
    try {
      return switch (stop.kind) {
        TransitStopKind.train => await _trainBoard(stop),
        TransitStopKind.interCityBus => (await _busBoards([
          stop,
        ], intercity: true)).single,
        TransitStopKind.cityBus => (await _busBoards([
          stop,
        ], intercity: false)).single,
      };
    } on TransitUnavailable catch (e) {
      return StopBoard(stop: stop, error: e.message, updatedAt: DateTime.now());
    }
  }

  /// 一次抓好幾個站的看板。
  ///
  /// **同一個城市的市區公車會合併成一個請求。** 海大那三個站牌打的是同一個
  /// 端點（`EstimatedTimeOfArrival/City/Keelung`），只有站名不同 —— 分成三次
  /// 問等於白白多打兩個請求。這一頁每 30 秒重整一次，而 TDX 會回 429，
  /// 那兩個請求是真的會把畫面打成「服務忙碌中」的。
  ///
  /// 合併之後每次重整是 3 個請求（基隆市公車一次、國道客運一次、台鐵一次），
  /// 不是 5 個。
  Future<List<StopBoard>> boards(List<TransitStop> stops) async {
    // 照「資料來源」分組，一組一個請求。
    //
    // **一個站可能屬於兩組。** 海大體育館的基隆市公車和首都客運 1579 分別
    // 在兩個端點裡，所以它要問兩次 —— 但那兩次分別跟其他站合併，
    // 總請求數還是每個來源一個。
    final groups = <String, List<TransitStop>>{};
    final trains = <TransitStop>[];
    for (final s in stops) {
      for (final kind in s.kinds) {
        switch (kind) {
          case TransitStopKind.train:
            trains.add(s);
          case TransitStopKind.cityBus:
            groups.putIfAbsent('city:${s.city}', () => []).add(s);
          case TransitStopKind.interCityBus:
            groups.putIfAbsent('intercity', () => []).add(s);
        }
      }
    }

    // 一個站可能從兩個來源各拿到一批車，合起來才是完整的那一張看板。
    final buses = <String, List<BusArrival>>{};
    final errors = <String, String>{};
    final trainBoards = <String, StopBoard>{};

    await Future.wait([
      for (final entry in groups.entries)
        _busBoards(entry.value, intercity: entry.key == 'intercity')
            .then((boards) {
              for (final b in boards) {
                (buses[b.stop.id] ??= []).addAll(b.buses);
              }
            })
            .catchError((Object e) {
              // 一個來源掛掉不該讓另一個來源的車也消失 —— 錯誤先記著，
              // 最後只有在「一台車都沒有」的時候才顯示出來。
              final message = e is TransitUnavailable
                  ? e.message
                  : '交通資料暫時取不到';
              for (final s in entry.value) {
                errors[s.id] ??= message;
              }
            }),
      for (final s in trains) board(s).then((b) => trainBoards[s.id] = b),
    ]);

    // 照原本的順序回傳 —— 畫面上的卡片順序是設定檔決定的，不是抓完的順序。
    final now = DateTime.now();
    return [
      for (final s in stops)
        if (trainBoards.containsKey(s.id))
          trainBoards[s.id]!
        else
          StopBoard(
            stop: s,
            buses: (buses[s.id] ?? [])
              ..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
            // 有車就不要因為另一個來源失敗而蓋掉整張卡片。
            error: (buses[s.id]?.isEmpty ?? true) ? errors[s.id] : null,
            updatedAt: now,
          ),
    ];
  }

  // ---------------------------------------------------------------- 公車

  /// 一個請求問完一整組站牌，再把回來的資料照站名分回各自的看板。
  Future<List<StopBoard>> _busBoards(
    List<TransitStop> stops, {
    required bool intercity,
  }) async {
    if (stops.isEmpty) return const [];
    final city = stops.first.city;
    final path = intercity
        ? config.endpoint('intercity_arrivals')
        : config.endpoint('city_bus_arrivals', city: city);
    final template =
        config.endpoints[intercity ? 'intercity_filter' : 'city_bus_filter'] ??
        '';

    final rows = await client.get(
      path,
      query: {
        if (template.isNotEmpty)
          '\$filter': _nameFilter(template, [
            for (final s in stops) ...s.allNames,
          ]),
        // 一站大約 15 筆，而且一個站名可能對到馬路兩邊兩個站牌。
        // 三個站合併問，上限要跟著放大。
        '\$top': '${stops.length * 80}',
      },
    );

    await _learnRoutes(rows, intercity: intercity, city: city);

    // 只問一個站的時候不用拆 —— filter 送出去的就是那一個站名，回來的
    // 每一筆都是它的。**而且不拆比較安全**：真要靠站名比對才分得回去的話，
    // 哪天 StopName 換了形狀，整批資料會一筆不剩地消失，畫面上看起來
    // 就只是「這幾站都沒有車」。
    final split = stops.length > 1;
    final perStop = [
      for (final stop in stops) _dedupe(split ? _rowsFor(stop, rows) : rows),
    ];

    // 同一張卡片上出現不只一次的路線才需要標方向 —— 那是馬路兩邊。
    // **只查這些**，站序的回應很大，全部路線都拉會拖垮首次載入。
    final ambiguous = <String>{};
    for (final kept in perStop) {
      final seen = <String>{};
      for (final r in kept) {
        final name = _text(r['RouteName']);
        if (!seen.add(name)) ambiguous.add(name);
      }
    }
    await _learnStopOrder(ambiguous, city: city, intercity: intercity);

    final now = DateTime.now();
    return [
      for (var i = 0; i < stops.length; i++)
        StopBoard(
          stop: stops[i],
          buses: [for (final r in perStop[i]) _busFrom(r)]
            ..sort((a, b) => a.sortKey.compareTo(b.sortKey)),
          updatedAt: now,
        ),
    ];
  }

  /// 從整批回應裡挑出屬於這一站的那幾筆。
  static List<Map<String, dynamic>> _rowsFor(
    TransitStop stop,
    List<Map<String, dynamic>> rows,
  ) {
    final names = stop.allNames.toSet();
    return [
      for (final r in rows)
        if (names.contains(_text(r['StopName']))) r,
    ];
  }

  /// 同一條路線在同一個站牌上只留一筆。
  ///
  /// **TDX 會把同一個站牌的同一條路線報好幾次**，因為它是按「子路線」拆的：
  /// 103 是環狀線，有 `KEE035501` 和 `KEE035601` 兩條子路線，兩條都經過
  /// 海大體育館 —— 於是同一個站牌同一條路線就出現兩筆。104 更多，因為它
  /// 還有一條區間車。使用者看到的是「一站冒出四個 103」。
  ///
  /// 去重的鍵是**（路線名, 實體站牌）**。站牌一定要放進鍵裡：「海大體育館」
  /// 這個站名對到馬路兩邊兩個站牌（`KEE306429` 往濱海校門、`KEE306430`
  /// 往北寧路），那是**真的不同方向的兩班車**，併掉就等於叫使用者站錯邊。
  ///
  /// 同一個鍵有多筆時留最快到的那一筆 —— 使用者問的是「下一班什麼時候」。
  static List<Map<String, dynamic>> _dedupe(List<Map<String, dynamic>> rows) {
    int sortKeyOf(Map<String, dynamic> r) => _int(r['EstimateTime']) ?? 1 << 30;

    final best = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final key = '${_text(r['RouteName'])}\u0000${_text(r['StopUID'])}';
      final existing = best[key];
      if (existing == null || sortKeyOf(r) < sortKeyOf(existing)) {
        best[key] = r;
      }
    }
    return best.values.toList();
  }

  /// 把多個候選站名串成一條 OData filter。
  ///
  /// 一個站牌在 TDX 裡叫「海大濱海校門」還是「海洋大學濱海校門」我們不知道，
  /// 所以全部都問，`or` 起來 —— 對的那個會有資料，錯的那個不會有，
  /// 不用先查一次「這站到底叫什麼」。
  static String _nameFilter(String template, List<String> names) {
    final seen = <String>{};
    final clauses = [
      for (final n in names)
        // OData 的字串用單引號包，值裡面的單引號要疊成兩個。
        // 站名裡不會有單引號，但這是字串拼接進查詢語言，該擋還是要擋。
        if (n.isNotEmpty && seen.add(n))
          template.replaceAll('{name}', n.replaceAll("'", "''")),
    ];
    return clauses.join(' or ');
  }

  // -------------------------------------------------- 路線的兩頭（往哪裡）

  /// RouteUID → 這條路線的起點與終點站名。
  ///
  /// **到站資料裡沒有終點站名**，只有 `DestinationStop`（StopID，像
  /// `"306195"`）。要顯示「往八斗子車站」就得拿 `RouteUID` 去路線資料
  /// 查這條路線的兩頭，再靠 `Direction` 決定要顯示哪一邊。
  ///
  /// 查過就記著，整個 session 不再問第二次 —— 路線的起訖站不會在一天之內
  /// 改變，而每 30 秒重整一次的頁面禁不起每次都多打一輪請求（TDX 會回 429，
  /// 我們已經撞過一次）。查不到的也要記起來（記成空的），否則那條路線
  /// 每次重整都會再問一遍。
  final Map<String, ({String departure, String destination})> _routeEnds = {};

  /// 補充資料（路線起訖站、站序）查失敗之後，最早什麼時候可以再試。
  ///
  /// **沒有這個東西，一次 429 會變成永久的 429。** 這兩種查詢原本失敗就
  /// 直接放棄、不留記錄，所以下一次重整又會整輪重問 —— 每 30 秒、四個公車
  /// 站各一次。TDX 一旦開始擋，重試本身就把請求量撐在高點，讓它停不下來，
  /// 畫面上五張卡片就一直是「服務忙碌中」。
  ///
  /// 這兩份資料**純粹是錦上添花**（「往哪裡」和方向標記），到站時間不靠它們。
  /// 所以失敗就退開幾分鐘，讓真正重要的那三個請求有機會過去。
  DateTime? _extrasBlockedUntil;

  static const _extrasBackoff = Duration(minutes: 5);

  bool get _extrasBlocked {
    final until = _extrasBlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _blockExtras() =>
      _extrasBlockedUntil = DateTime.now().add(_extrasBackoff);

  /// 使用者自己下拉重整時，把退避解除 —— 那是他明確要求「現在再試一次」。
  void retryExtrasNow() => _extrasBlockedUntil = null;

  /// 路線查詢排成一列跑。
  ///
  /// 五個站是同時開始抓的，其中三個是同一個城市的公車 —— 沒有這個的話
  /// 它們會同時發現「這些路線沒查過」而各送一次幾乎一樣的請求。
  Future<void>? _routeQueue;

  Future<void> _learnRoutes(
    List<Map<String, dynamic>> rows, {
    required bool intercity,
    required String city,
  }) {
    final next = (_routeQueue ?? Future<void>.value()).then(
      (_) => _fetchRouteEnds(rows, intercity: intercity, city: city),
    );
    _routeQueue = next;
    return next;
  }

  Future<void> _fetchRouteEnds(
    List<Map<String, dynamic>> rows, {
    required bool intercity,
    required String city,
  }) async {
    final missing = <String>{};
    for (final r in rows) {
      final uid = _text(r['RouteUID']);
      if (uid.isNotEmpty && !_routeEnds.containsKey(uid)) missing.add(uid);
    }
    if (missing.isEmpty) return;

    final path = intercity
        ? config.endpoint('intercity_routes')
        : config.endpoint('city_bus_routes', city: city);
    final template = config.endpoints['route_filter'] ?? '';
    if (path.isEmpty || template.isEmpty || _extrasBlocked) return;

    try {
      final routes = await client.get(
        path,
        query: {
          '\$filter': _nameFilter(template, missing.toList()),
          '\$top': '${missing.length}',
        },
      );
      for (final r in routes) {
        final uid = _text(r['RouteUID']);
        if (uid.isEmpty) continue;
        _routeEnds[uid] = (
          departure: _text(r['DepartureStopNameZh']),
          destination: _text(r['DestinationStopNameZh']),
        );
      }
    } on TransitUnavailable {
      // 路線查不到只是少了「往哪裡」，到站時間還在 —— 不要讓它把整站弄爆。
      //
      // **但也不能下次重整就再問一遍。** 那正是把一次 429 拖成永久 429 的
      // 原因：每 30 秒四個註定失敗的請求，把請求量撐在高點。退開五分鐘。
      _blockExtras();
      return;
    }

    // 問過但對方沒給的，記成空的。否則這條路線每 30 秒就會再被問一次。
    for (final uid in missing) {
      _routeEnds.putIfAbsent(uid, () => (departure: '', destination: ''));
    }
  }

  /// 這班車往哪裡。
  ///
  /// **`Direction` 0 是去程、1 是返程**，所以 0 看終點欄位、1 看起點欄位。
  /// 這是 TDX 的慣例，而且對過真實資料（`spike/tdx.py --probe-direction`，
  /// 2026-09-04）：40 組（路線, 方向）裡 **36 組精準命中** ——
  /// Direction 0 對終點欄位 21 筆、Direction 1 對起點欄位 15 筆。
  ///
  /// 剩下 4 組是**短程／區間班次**：那班車真正的終點停在路線名義終點之前
  /// （`THB1573` 返程實際停到港西街下客站，路線寫的是基隆轉運站；`THB1550`
  /// 的路線資料兩頭甚至都寫成基隆轉運站）。**方向仍然是對的**，只是顯示的
  /// 站名比實際遠一點。要更精準得把 `DestinationStop` 那個 StopID 也解成
  /// 站名，那是每次重整多一輪查詢換一點點精確度 —— 不划算，先不做。
  ///
  /// **弄反了不會有錯誤訊息** —— 畫面上是一個看起來完全合理的終點站名，
  /// 只是方向相反，使用者照著搭反邊。所以認不得的 Direction 寧可留白。
  String _destinationFor(Map<String, dynamic> r) {
    final ends = _routeEnds[_text(r['RouteUID'])];
    if (ends == null) return '';

    final name = switch (_int(r['Direction'])) {
      0 => ends.destination,
      1 => ends.departure,
      _ => '',
    };

    // 終點就是現在站著的這一站時不要說「往 海大體育館」——
    // 跟台鐵那邊同一個道理，那句話沒有告訴使用者任何事。
    if (name.isNotEmpty && name == _text(r['StopName'])) return '本站為終點';
    return name;
  }

  /// 公車的欄位**已經對過真實回應了**（2026-09-03，spike/tdx.py --save，
  /// fixture 在 `spike/fixtures/tdx/`），所以下面不再是候選清單而是確定的名字。
  ///
  /// 對的時候學到三件事，每一件都值得寫下來：
  ///
  /// 1. **`EstimateTime` 是選擇性欄位** —— 只有真的有車在跑的那一筆才有它。
  ///    深夜抓下來的 15 筆裡只有 1 筆帶，其餘 14 筆連這個 key 都不存在。
  ///    所以「沒有這個欄位」是常態，不是解析失敗，[BusArrival.estimateSeconds]
  ///    才會刻意分 null 和 0。
  ///
  /// 2. **`StopCountDown` 不是秒數，是「還有幾站」。** 同一筆資料裡
  ///    `EstimateTime: 725` 配 `StopCountDown: 19`、`1979` 配 `13`。
  ///    把它當秒數的備援會讓「還有 19 站」顯示成「19 秒 → 進站中」——
  ///    畫面上一切正常，只有時間全錯。**不要把它加進下面的候選。**
  ///
  /// 3. **`DestinationStop` 給的是 StopID 不是站名**（`"306195"`）。
  ///    見 [BusArrival.destination] 下面那段。
  BusArrival _busFrom(Map<String, dynamic> r) => BusArrival(
    routeName: _text(r['RouteName']),
    // 到站資料本身**沒有終點站名**，只有 `DestinationStop`（StopID）。
    // 站名是從路線資料補上的，見 [_destinationFor]。補不到就空著，
    // 畫面上那一行會收起來 —— 空白比「往 306195」好。
    destination: _destinationFor(r),
    estimateSeconds: _int(r['EstimateTime']),
    stopStatus: _int(r['StopStatus']) ?? 0,
    // `-1` 是 TDX 的哨兵值，代表「沒有車」，不是車牌。
    plateNumber: _plate(_text(r['PlateNumb'])),
    stopsAway: _int(r['StopCountDown']),
    isLastBus: r['IsLastBus'] == true,
    nextStop: _nextStopOn(
      _text(r['SubRouteUID']),
      _int(r['StopSequence']) ?? 0,
    ),
  );

  static String _plate(String raw) => raw == '-1' ? '' : raw;

  // ------------------------------------------------------- 下一站（分辨方向）

  /// 這班車離開這一站之後停哪。查不到回空字串。
  String _nextStopOn(String subRouteUid, int sequence) {
    if (subRouteUid.isEmpty || sequence <= 0) return '';
    for (final variants in _routeStops.values) {
      for (final v in variants) {
        if (v.subRouteUid != subRouteUid) continue;
        for (final s in v.stops) {
          if (s.sequence == sequence + 1) return s.name;
        }
        // 這一站就是終點，後面沒有了。
        return '';
      }
    }
    return '';
  }

  /// 把這幾條路線的站序抓回來快取起來。
  ///
  /// **只在需要分辨方向的時候才呼叫**（同一張卡片上同一條路線出現兩次）。
  /// 站序的回應很大 —— 光 103 兩條子路線就有 132 個站牌 —— 把一個站牌經過的
  /// 所有路線都拉下來會讓首次載入變得很慢，而且大部分資料根本用不到。
  ///
  /// 查過就不再查，**查不到的也記起來**：否則那條路線每 30 秒會被重問一次，
  /// 而一次 429 就會變成每半分鐘再撞一次。
  Future<void> _learnStopOrder(
    Set<String> routeNames, {
    required String city,
    required bool intercity,
  }) async {
    final missing = routeNames
        .where((n) => n.isNotEmpty && !_routeStops.containsKey(n))
        .toList();
    if (missing.isEmpty || _extrasBlocked) return;

    try {
      await _fetchStopsOfRoute(missing, city: city, intercity: intercity);
    } on TransitUnavailable {
      // 抓不到就只是少了方向標記，到站時間還在。跟路線起訖站同一個道理：
      // 不要每 30 秒再撞一次，退開五分鐘。
      _blockExtras();
      return;
    }
    for (final n in missing) {
      _routeStops.putIfAbsent(n, () => const []);
    }
  }

  // ------------------------------------------------ 點進一條路線（站序 + 車在哪）

  /// 這條路線的站序快取。站序一天之內不會變，查一次就好。
  final Map<String, List<RouteVariant>> _routeStops = {};

  /// 點進一條路線要看的東西：它經過哪些站、現在有幾台車、各在第幾站。
  ///
  /// **不丟例外** —— 失敗包成 [RouteDetail.error] 回來，跟 [board] 同一個慣例。
  ///
  /// 兩個請求：站序（有快取，通常只有第一次會打）和即時位置（每次都要，
  /// 那就是「現在開到哪」本身）。
  Future<RouteDetail> routeDetail(
    String routeName, {
    required String city,
    required bool intercity,
  }) async {
    try {
      final variants = await _stopsOfRoute(
        routeName,
        city: city,
        intercity: intercity,
      );
      if (variants.isEmpty) {
        return RouteDetail(routeName: routeName, error: '查不到這條路線的站序');
      }
      final buses = await _busPositions(
        routeName,
        city: city,
        intercity: intercity,
      );

      // 車按子路線分堆。**配對用 SubRouteUID，不是方向** —— 環狀線的
      // 兩條站序方向相同，只看方向會把車畫到錯的那一條上。
      return RouteDetail(
        routeName: routeName,
        variants: [
          for (final v in variants)
            v.withBuses([
              for (final b in buses)
                if (b.subRouteUid == v.subRouteUid) b,
            ]),
        ],
      );
    } on TransitUnavailable catch (e) {
      return RouteDetail(routeName: routeName, error: e.message);
    }
  }

  Future<List<RouteVariant>> _stopsOfRoute(
    String routeName, {
    required String city,
    required bool intercity,
  }) async {
    final cached = _routeStops[routeName];
    if (cached != null) return cached;
    await _fetchStopsOfRoute([routeName], city: city, intercity: intercity);
    return _routeStops[routeName] ?? const [];
  }

  /// 一個請求抓好幾條路線的站序，照路線名分好存進快取。
  Future<void> _fetchStopsOfRoute(
    List<String> routeNames, {
    required String city,
    required bool intercity,
  }) async {
    final path = intercity
        ? config.endpoint('intercity_stops_of_route')
        : config.endpoint('city_bus_stops_of_route', city: city);
    final template = config.endpoints['route_name_filter'] ?? '';
    if (path.isEmpty || template.isEmpty) {
      throw const TransitUnavailable('這項資料尚未設定');
    }

    final rows = await client.get(
      path,
      query: {'\$filter': _nameFilter(template, routeNames)},
    );

    final byRoute = <String, List<RouteVariant>>{};
    for (final r in rows) {
      final variant = RouteVariant(
        subRouteUid: _text(r['SubRouteUID']),
        subRouteName: _text(r['SubRouteName']),
        direction: _int(r['Direction']) ?? 0,
        stops: _stopsFrom(r['Stops']),
      );
      if (variant.stops.isEmpty) continue;
      // 只問一條路線的時候，回來的東西一定是它的 —— 就算 RouteName 沒帶
      // 也認得出來。**沒有這條退路的話，少一個欄位會讓整批站序安靜消失**，
      // 而畫面上只是「這條路線沒有站序資料」，看不出是欄位的問題。
      final name = _text(r['RouteName']);
      final key = name.isNotEmpty
          ? name
          : (routeNames.length == 1 ? routeNames.single : '');
      if (key.isEmpty) continue;
      byRoute.putIfAbsent(key, () => []).add(variant);
    }
    _routeStops.addAll(byRoute);
  }

  static List<RouteStop> _stopsFrom(Object? raw) {
    if (raw is! List) return const [];
    final stops = [
      for (final e in raw)
        if (e is Map<String, dynamic>)
          RouteStop(
            stopUid: _text(e['StopUID']),
            name: _text(e['StopName']),
            sequence: _int(e['StopSequence']) ?? 0,
          ),
    ];
    // TDX 回來的順序通常已經是對的，但站序是這一頁的骨架 ——
    // 順序錯掉的話畫面會變成一條走不通的路線，而且看起來很像真的。
    stops.sort((a, b) => a.sequence.compareTo(b.sequence));
    return stops;
  }

  Future<List<BusPosition>> _busPositions(
    String routeName, {
    required String city,
    required bool intercity,
  }) async {
    final path = intercity
        ? config.endpoint('intercity_realtime')
        : config.endpoint('city_bus_realtime', city: city);
    final template = config.endpoints['route_name_filter'] ?? '';
    if (path.isEmpty || template.isEmpty) return const [];

    try {
      final rows = await client.get(
        path,
        query: {
          '\$filter': _nameFilter(template, [routeName]),
        },
      );
      return [
        for (final r in rows)
          BusPosition(
            plate: _plate(_text(r['PlateNumb'])),
            subRouteUid: _text(r['SubRouteUID']),
            stopSequence: _int(r['StopSequence']) ?? 0,
            stopName: _text(r['StopName']),
            // A2EventType：0 進站、1 離站。
            leaving: _int(r['A2EventType']) == 1,
          ),
      ];
    } on TransitUnavailable {
      // 查不到車就是「現在沒有車在跑」的樣子 —— 站序還是要看得到。
      // 深夜本來就沒車，那不該讓整頁變成錯誤訊息。
      return const [];
    }
  }

  // ---------------------------------------------------------------- 台鐵

  Future<StopBoard> _trainBoard(TransitStop stop) async {
    final stationId = stop.stationId.isNotEmpty
        ? stop.stationId
        : await _lookUpStationId(stop);

    final template = config.endpoints['train_liveboard_filter'] ?? '';
    final rows = await client.get(
      config.endpoint('train_liveboard'),
      query: {
        if (template.isNotEmpty)
          '\$filter': template.replaceAll('{station}', stationId),
        '\$top': '30',
      },
    );

    final trains = [for (final r in rows) _trainFrom(r, stationId)];
    return StopBoard(stop: stop, trains: trains, updatedAt: DateTime.now());
  }

  /// 台鐵車站代碼查一次就記著。
  ///
  /// `transit.json` 的 `station_id` 現在填的是 `0900`（2026-09-03 用
  /// `spike/tdx.py` 對 TDX 的車站清單查證過），所以正常情況下**根本不會走到
  /// 這裡** —— 這條路是留給「代碼哪天被改掉」的退路。
  ///
  /// 當初留空是刻意的：**填一個錯的代碼會安靜地查出別站的車**，畫面上一切
  /// 正常，只是列車全是別的地方的。所以那個空值不是還沒寫完，是在等查證。
  String? _cachedStationId;

  Future<String> _lookUpStationId(TransitStop stop) async {
    final cached = _cachedStationId;
    if (cached != null) return cached;

    final template = config.endpoints['train_station_filter'] ?? '';
    final rows = await client.get(
      config.endpoint('train_stations'),
      query: {
        if (template.isNotEmpty)
          '\$filter': _nameFilter(template, [
            if (stop.stationName.isNotEmpty) stop.stationName,
            ...stop.matchNames,
          ]),
        '\$top': '5',
      },
    );

    for (final r in rows) {
      final id = _text(_pick(r, const ['StationID', 'StationId']));
      if (id.isNotEmpty) return _cachedStationId = id;
    }
    throw const TransitUnavailable('查不到這個車站');
  }

  /// 台鐵的欄位**已經對過真實回應了**（2026-09-04，`spike/fixtures/tdx/
  /// tra-keelung.json`），所以下面也不再是候選清單。
  ///
  /// 對出來一個原本會安靜壞掉的地方：**表定時間的欄位是 `ScheduleXxxTime`，
  /// 不是 `ScheduledXxxTime`** —— 少一個 d。原本三個候選全部沒命中，
  /// 解析出空字串，而那一欄是列車那一列右邊的主角。畫面上不會有錯誤，
  /// 只會有一片空白，看起來像「這班車沒有時間」。
  ///
  /// [stationId] 是這個看板屬於哪一站，拿來判斷「終點就是本站」。
  static TrainDeparture _trainFrom(Map<String, dynamic> r, String stationId) {
    // 到站和發車時間在端點站是同一個值（`23:18:00` / `23:18:00`）。
    // 先看發車 —— 對中途站來說「幾點開」才是要等的那個時間。
    final time = _pick(r, const [
      'ScheduleDepartureTime',
      'ScheduleArrivalTime',
    ]);

    return TrainDeparture(
      trainNo: _text(r['TrainNo']),
      trainType: _text(r['TrainTypeName']),
      destination: _destinationOf(r, stationId),
      scheduledTime: _clock(_text(time)),
      delayMinutes: _int(r['DelayTime']) ?? 0,
      platform: _text(r['Platform']),
    );
  }

  /// 列車要開去哪。**終點就是本站的時候不要說「往 基隆」。**
  ///
  /// 基隆是端點站，深夜抓到的三班車 `EndingStationID` 全都是 `0900`，
  /// 也就是基隆自己。照著印會變成站在基隆站看到「往 基隆」—— 那句話
  /// 沒有告訴使用者任何事情。這種車是進站後就收班的，講「本站為終點」
  /// 才是使用者要知道的事。
  static String _destinationOf(Map<String, dynamic> r, String stationId) {
    final endId = _text(r['EndingStationID']);
    if (endId.isNotEmpty && endId == stationId) return '本站為終點';
    return _text(r['EndingStationName']);
  }

  // ------------------------------------------------------------ 小工具

  /// 從幾個候選 key 裡挑第一個有值的。
  static Object? _pick(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v != null) return v;
    }
    return null;
  }

  /// 多語系欄位 → 中文字串。
  ///
  /// 值可能是 `"103"`，也可能是 `{"Zh_tw": "103", "En": "103"}`。
  /// 兩種都吃，取不到中文就退回英文 —— 顯示英文站名，比顯示空白好。
  static String _text(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num) return '$v';
    if (v is Map) {
      for (final k in const ['Zh_tw', 'ZhTw', 'Zh_TW', 'zh_tw', 'En', 'en']) {
        final s = v[k];
        if (s is String && s.isNotEmpty) return s;
      }
    }
    return '';
  }

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// `HH:mm:ss` → `HH:mm`。
  ///
  /// 台鐵給的是帶秒的時間字串，而秒數對「幾點的車」沒有意義 ——
  /// 顯示 `07:32:00` 只是讓那一欄變寬、變難掃。認不得的格式原樣回傳。
  static String _clock(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw);
    if (m == null) return raw;
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }
}

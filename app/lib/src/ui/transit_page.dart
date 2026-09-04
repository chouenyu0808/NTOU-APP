import 'dart:async';

import 'package:flutter/material.dart';

import '../transit/tdx_client.dart';
import '../transit/transit_config.dart';
import '../transit/transit_models.dart';
import '../storage/transit_prefs_store.dart';
import '../transit/transit_repository.dart';
import 'route_page.dart';
import 'theme.dart';

/// 交通分頁：學生每天在用的那幾個站，現在有什麼車。
///
/// 排版抄 Bus+ 的習慣 —— **右邊那一欄的到站時間是主角**，路線號在左邊當索引，
/// 中間放往哪裡。使用者的動作是「掃右邊那一欄找一個夠大的數字」，
/// 所以那一欄要大、要對齊、要有顏色分輕重，其他東西都退到後面去。
///
/// 這一頁跟學校的 AIS session 沒有關係，**沒登入也能看** ——
/// 資料來自交通部的 TDX。學校系統掛掉的時候這頁照常運作。
class TransitPage extends StatefulWidget {
  const TransitPage({
    super.key,
    this.repository,
    this.prefs,
    this.isActive = true,
    this.autoRefresh = const Duration(seconds: 30),
  });

  /// 測試會注入一個假的。正式執行時是 null，開頁的時候自己建。
  final TransitRepository? repository;

  /// 本機偏好（最愛路線、收起來的站牌）存哪裡。
  /// 測試注入一個吃假 SharedPreferences 的。
  final TransitPrefsStore? prefs;

  /// 使用者現在是不是正在看這一頁。
  ///
  /// **[HomeShell] 用的是 `IndexedStack`，所有分頁從開 App 起就一直掛載著。**
  /// 沒有這個旗標的話，使用者在看課表，這一頁的計時器照樣每 30 秒打一次
  /// 交通部的伺服器 —— 一整天沒人看的分頁可以打掉上千個請求。
  final bool isActive;

  /// 自動重新整理的間隔。交通資訊放著兩分鐘就沒有意義了。
  final Duration autoRefresh;

  @override
  State<TransitPage> createState() => _TransitPageState();
}

class _TransitPageState extends State<TransitPage> {
  TransitRepository? _repo;
  late final TransitPrefsStore _prefs = widget.prefs ?? TransitPrefsStore();
  Set<String> _favorites = const {};

  /// 被收起來的站牌 id。
  ///
  /// 五張卡片攤開來要捲很久，而大部分人只固定看其中一兩站 ——
  /// 收起來之後那些站只剩一行標題，需要的時候再點開。
  Set<String> _collapsed = const {};
  List<StopBoard> _boards = const [];
  bool _loading = true;
  bool _configured = true;
  String? _fatal;
  Timer? _timer;

  /// 這一頁到底有沒有開始載入過。
  ///
  /// **開 App 的時候不要載。** 使用者停在首頁的時候這一頁已經掛在
  /// `IndexedStack` 裡了，先載等於為一個沒人看的分頁去讀設定檔、打網路。
  /// 等第一次真的被切到再開始。
  ///
  /// 這件事還順便修掉一個很難查的測試問題：載入中轉的那顆
  /// `CircularProgressIndicator` 是**無限動畫**，它只要在畫面上，
  /// 整個 App 的任何 `pumpAndSettle` 就永遠等不到穩定 —— 而失敗訊息
  /// （「pumpAndSettle timed out」）完全看不出跟交通頁有關。
  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _boot();
  }

  @override
  void didUpdateWidget(TransitPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive == old.isActive) return;
    if (widget.isActive) {
      if (!_started) {
        // 第一次被切到 —— 現在才開始載設定、建 client。
        _boot();
      } else {
        // 切回來 —— 剛才沒在看的期間資料已經舊了，馬上補一次再開始計時。
        _refresh();
        _startTimer();
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!widget.isActive) return;
    _timer = Timer.periodic(widget.autoRefresh, (_) => _refresh());
  }

  Future<void> _boot() async {
    _started = true;
    // 最愛**不擋著看板**。
    //
    // 它是本機的東西，跟公車時間毫無關係 —— 讀它讀得慢或讀不到的時候，
    // 使用者要看的到站時間不該跟著一起等。所以這裡不 await，
    // 讀到了再把愛心補上去就好。
    unawaited(_loadPrefs());

    try {
      var repo = widget.repository;
      if (repo == null) {
        final config = await TransitConfig.loadFromAsset();
        repo = TransitRepository(
          config: config,
          client: TdxClient(config: config),
        );
      }
      if (!mounted) return;
      _repo = repo;
      _configured = repo.isConfigured;
      // 沒有金鑰就不要去打 —— 五個站會各失敗一次，畫面上五張紅卡片，
      // 而真正該說的只有一句「還沒設定」。
      if (!_configured) {
        setState(() => _loading = false);
        return;
      }
      await _refresh();
      _startTimer();
    } catch (_) {
      // 這裡吃掉的是「設定檔讀不到 / 格式壞了」。**不要把例外原文顯示出來** ——
      // 那是給我們看的，而且可能帶著網址。
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fatal = '交通設定讀不到';
      });
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final favs = await _prefs.readFavorites();
      final collapsed = await _prefs.readCollapsed();
      if (!mounted || (favs.isEmpty && collapsed.isEmpty)) return;
      setState(() {
        _favorites = favs;
        _collapsed = collapsed;
      });
    } catch (_) {
      // 讀不到就當作沒有釘過、也沒有收過。這一頁照常能用。
    }
  }

  void _openRoute(StopBoard board, BusArrival arrival) {
    final repo = _repo;
    if (repo == null || arrival.routeName.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutePage(
          routeName: arrival.routeName,
          repository: repo,
          city: board.stop.city,
          // **來源看這班車是從哪個查詢回來的，不看站牌的類別。**
          // 海大體育館的主要類別是市區公車，但 1579、1813 是國道客運 ——
          // 用站牌類別去問會查到基隆市公車那邊，回 0 筆，畫面上變成
          // 「查不到這條路線的站序」。
          intercity: arrival.fromIntercity,
          // 從哪一站點進來的就標哪一站 —— 68 站的路線攤開來很長。
          // 用整組名字比對：國道客運那邊這個站叫「海大(體育館)」，
          // 只傳主要名字的話點進 1579 會整條路線都沒有標記。
          highlightStops: board.stop.allNames.toSet(),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(String route) async {
    if (route.isEmpty) return;
    try {
      final next = await _prefs.toggleFavorite(route);
      if (!mounted) return;
      setState(() => _favorites = next);
    } catch (_) {
      // 存不進去就算了，不要為了一個愛心跳錯誤訊息給使用者。
    }
  }

  Future<void> _toggleCollapsed(String stopId) async {
    // 先動畫面再寫檔 —— 收合是即時的動作，等儲存回來才收會卡一下。
    setState(() {
      final next = {..._collapsed};
      if (!next.remove(stopId)) next.add(stopId);
      _collapsed = next;
    });
    try {
      await _prefs.toggleCollapsed(stopId);
    } catch (_) {
      // 存不進去就只是下次開 App 又展開，不值得跳錯誤訊息。
    }
  }

  /// [manual] 是使用者自己按的（下拉或按重新整理鈕），不是計時器。
  ///
  /// 手動的時候要把補充資料的退避解除 —— 那是他明確在說「現在再試一次」。
  Future<void> _refresh({bool manual = false}) async {
    final repo = _repo;
    if (repo == null || !_configured) return;
    if (manual) repo.retryExtrasNow();

    // 整批交給 repository —— 同一個城市的市區公車會被合併成一個請求。
    // 海大那三個站牌打的是同一個端點，分開問等於白白多打兩個請求，
    // 而那正是畫面上一直冒「服務忙碌中」的原因。
    final boards = await repo.boards(repo.config.stops);
    if (!mounted) return;
    setState(() {
      _boards = boards;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('交通'),
        actions: [
          if (_configured && !_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新整理',
              onPressed: () => _refresh(manual: true),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    // 還沒被切到過 —— 什麼都不畫。這裡放轉圈圈的話，它會在背景一直轉。
    if (!_started) return const SizedBox.shrink();
    if (_loading) return const Center(child: CircularProgressIndicator());
    final fatal = _fatal;
    if (fatal != null) return _Notice(text: fatal);
    if (!_configured) return const _SetupGuide();

    return RefreshIndicator(
      onRefresh: () => _refresh(manual: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        // 多一列給最上面那行「資料更新於」。
        itemCount: _boards.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => i == 0
            ? _UpdatedAt(boards: _boards)
            : _StopCard(
                board: _boards[i - 1],
                config: _repo!.config,
                favorites: _favorites,
                isCollapsed: _collapsed.contains(_boards[i - 1].stop.id),
                onToggleCollapsed: () =>
                    _toggleCollapsed(_boards[i - 1].stop.id),
                onToggleFavorite: _toggleFavorite,
                onOpenRoute: (a) => _openRoute(_boards[i - 1], a),
              ),
      ),
    );
  }
}

/// 一個站一張卡。
class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.board,
    required this.config,
    this.favorites = const {},
    this.isCollapsed = false,
    this.onToggleCollapsed,
    this.onToggleFavorite,
    this.onOpenRoute,
  });

  final StopBoard board;
  final TransitConfig config;
  final Set<String> favorites;

  /// 這張卡片收起來了 —— 只留標題那一行。
  final bool isCollapsed;
  final VoidCallback? onToggleCollapsed;
  final void Function(String route)? onToggleFavorite;
  final void Function(BusArrival arrival)? onOpenRoute;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = board.stop.note;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 整個標題列都可以點來收合 —— 觸控目標愈大愈好，
          // 不要逼使用者去戳右邊那個小箭頭。
          InkWell(
            onTap: onToggleCollapsed,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Icon(_icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          board.stop.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        // 收起來的時候備註也一起收 —— 那一行是兩行字，
                        // 留著的話「收合」省不到多少高度。
                        if (note != null && !isCollapsed)
                          Text(
                            note,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        // 收起來之後看不到內容，所以標題底下補一句摘要，
                        // 讓人不用展開就知道這站現在有沒有車。
                        if (isCollapsed)
                          Text(
                            _summary,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (onToggleCollapsed != null)
                    Icon(
                      isCollapsed ? Icons.expand_more : Icons.expand_less,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (!isCollapsed) ...[
            const Divider(height: 1),
            _content(context, scheme),
          ],
        ],
      ),
    );
  }

  /// 收起來的時候標題底下那一句。
  ///
  /// **收合最怕的是把資訊藏掉之後就看不出「還要不要展開」。** 所以這裡講的
  /// 是最少但足夠的一件事：現在有沒有車、最快的那班還有多久。
  String get _summary {
    final error = board.error;
    if (error != null) return error;

    final trains = board.trains;
    if (trains.isNotEmpty) return '${trains.length} 班列車';

    final running = board.buses.where((b) => b.isRunning).toList();
    if (running.isEmpty) {
      return board.buses.isEmpty ? '目前沒有班次資訊' : '目前沒有車在路上';
    }
    final soonest = running.first;
    final label = ArrivalLabel.of(
      soonest.estimateSeconds,
      soonest.stopStatus,
      config.stopStatus,
    );
    return '${running.length} 班在路上 · 最快 ${soonest.routeName} ${label.text}';
  }

  /// 每條路線在這張卡片上出現幾次。
  ///
  /// 出現不只一次 = 馬路兩邊的兩個站牌都停這條路線。那兩列的終點站是一樣的
  /// （103 是環狀線），所以得額外標出方向，否則看起來一模一樣。
  Map<String, int> get _routeCounts {
    final counts = <String, int>{};
    for (final b in board.buses) {
      counts[b.routeName] = (counts[b.routeName] ?? 0) + 1;
    }
    return counts;
  }

  /// 釘起來的路線排最前面，其餘照到站時間。
  ///
  /// **兩組各自照時間排，不是把最愛全部打散重排。** 釘 103 的人要的是
  /// 「一眼找到 103」，不是「103 一定在最上面但下面亂掉」。
  List<BusArrival> get _sortedBuses {
    if (favorites.isEmpty) return board.buses;
    final pinned = <BusArrival>[];
    final rest = <BusArrival>[];
    for (final b in board.buses) {
      (favorites.contains(b.routeName) ? pinned : rest).add(b);
    }
    return [...pinned, ...rest];
  }

  IconData get _icon => switch (board.stop.kind) {
    TransitStopKind.train => Icons.train,
    TransitStopKind.interCityBus => Icons.directions_bus_filled,
    TransitStopKind.cityBus => Icons.directions_bus,
  };

  Widget _content(BuildContext context, ColorScheme scheme) {
    final error = board.error;
    if (error != null) {
      return _Inset(
        child: Text(error, style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    if (board.isEmpty) {
      // 「沒有車」和「查不到」要分開講。深夜沒有班次是正常的，
      // 講成錯誤會讓使用者一直重按重新整理。
      return _Inset(
        child: Text(
          board.stop.kind == TransitStopKind.train ? '目前沒有即將進站的列車' : '目前沒有班次資訊',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        for (final b in _sortedBuses)
          _BusRow(
            arrival: b,
            config: config,
            needsDirection: (_routeCounts[b.routeName] ?? 0) > 1,
            isFavorite: favorites.contains(b.routeName),
            onToggleFavorite: onToggleFavorite,
            onOpenRoute: onOpenRoute,
          ),
        for (final t in board.trains) _TrainRow(train: t),
      ],
    );
  }
}

class _Inset extends StatelessWidget {
  const _Inset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: child);
}

/// 一列公車：路線號 · 往哪 · 還有多久。
class _BusRow extends StatelessWidget {
  const _BusRow({
    required this.arrival,
    required this.config,
    this.needsDirection = false,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.onOpenRoute,
  });

  final BusArrival arrival;
  final TransitConfig config;

  /// 這條路線在同一張卡片上出現不只一次，得標出方向才分得開。
  final bool needsDirection;
  final bool isFavorite;
  final void Function(String route)? onToggleFavorite;
  final void Function(BusArrival arrival)? onOpenRoute;

  /// 「往哪裡」那一行。
  ///
  /// 平常就是終點站。**但同一條路線在這張卡片上出現兩次的時候，終點站分不出
  /// 方向** —— 103 是環狀線，馬路兩邊的車終點都是八斗子車站。那時候補上
  /// 下一站：一邊「經 海大濱海校門」（往市區），一邊「經 北寧路」
  /// （往八斗子），使用者才知道要站哪一邊。
  ///
  /// 連終點都查不到時，下一站就是唯一的線索，直接拿它當方向講。
  String get _towards {
    final to = arrival.destination;
    final next = arrival.nextStop;
    if (to.isEmpty) return next.isEmpty ? '' : '往 $next 方向';
    if (needsDirection && next.isNotEmpty) return '往 $to（經 $next）';
    return '往 $to';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = ArrivalLabel.of(
      arrival.estimateSeconds,
      arrival.stopStatus,
      config.stopStatus,
    );

    // 整列可以點進去看這條路線開到哪。愛心是列裡面的另一個按鈕，
    // Flutter 會讓它先吃掉自己的點擊，不會連帶開頁。
    return InkWell(
      onTap: onOpenRoute == null ? null : () => onOpenRoute!(arrival),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // 路線號固定寬度。**不要讓它跟著字數縮放** ——
            // 「103」和「1579」寬度不同的話，整欄的「往哪裡」會左右參差。
            SizedBox(
              width: 64,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(NtouTheme.radiusXs),
                ),
                child: Text(
                  arrival.routeName.isEmpty ? '—' : arrival.routeName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_towards.isNotEmpty)
                    Text(
                      _towards,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // 只有真的有車在路上時才講站數和末班車。
                  //
                  // 沒車的那幾筆 StopCountDown 一律是 0，跟「已經到站了」
                  // 分不出來 —— 印出來會變成一排「還有 0 站」，那是雜訊。
                  if (arrival.isRunning) _Detail(arrival: arrival),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Eta(label: label),
            if (onToggleFavorite != null)
              IconButton(
                // 觸控範圍要夠大，但視覺上不能跟到站時間搶。
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? scheme.primary : scheme.outline,
                ),
                tooltip: isFavorite
                    ? '取消釘選 ${arrival.routeName}'
                    : '釘選 ${arrival.routeName}',
                onPressed: () => onToggleFavorite!(arrival.routeName),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一列火車：車種車次 · 往哪 · 幾點（誤點幾分）。
class _TrainRow extends StatelessWidget {
  const _TrainRow({required this.train});

  final TrainDeparture train;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final head = [
      train.trainType,
      train.trainNo,
    ].where((s) => s.isNotEmpty).join(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              head.isEmpty ? '—' : head,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              train.destination.isEmpty ? '' : '往 ${train.destination}',
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                train.scheduledTime,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              // 準點就什麼都不說。每一列都掛一個「準點」的話，
              // 真正誤點的那一列就不顯眼了 —— 而那是唯一需要被看見的。
              if (train.delayMinutes > 0)
                Text(
                  '誤點 ${train.delayMinutes} 分',
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 路線底下那一行小字：還有幾站、是不是末班車。
///
/// **刻意壓得很小很淡。** 這一列的主角是右邊的到站時間，這裡只是補充；
/// 做得太顯眼會跟主角搶注意力，整頁就變得難掃。
///
/// 例外是「末班車」—— 那個用強調色，因為對學生來說錯過末班車跟晚五分鐘
/// 是完全不同量級的事，它值得從一片灰字裡跳出來。
class _Detail extends StatelessWidget {
  const _Detail({required this.arrival});

  final BusArrival arrival;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final stops = arrival.stopsAway;

    // **分隔點要用 join，不能讓每一段各自決定要不要在前面加一個。**
    // 那樣寫的話「只有車牌、沒有站數」的那一列會渲染成「· FAC-211」——
    // 一個前面什麼都沒有的分隔點。
    final parts = <Widget>[
      if (stops != null && stops > 0) Text('還有 $stops 站', style: muted),
      if (arrival.isLastBus)
        Text(
          '末班車',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.error,
          ),
        ),
      // 車牌排最後，而且最淡。同一條路線同時有兩台車的時候它才有用
      // （分得出哪一台是哪一台），其餘時候它只是一串沒人要記的字。
      if (arrival.plateNumber.isNotEmpty)
        Text(
          arrival.plateNumber,
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) Text(' · ', style: muted),
            parts[i],
          ],
        ],
      ),
    );
  }
}

/// 最上面那行「資料更新於 HH:mm」。
///
/// TDX 的資料每 30 秒才換一次，而畫面也是每 30 秒重整一次 —— 沒有這一行的話
/// 使用者會以為數字卡住了。標出時間，「它就是還沒變」跟「它壞了」才分得開。
///
/// 取的是**最舊的**那一張看板的時間。五個站是排隊送出的，彼此差幾秒，
/// 報最新的那個等於宣稱資料比實際更新 —— 寧可講保守的那一邊。
class _UpdatedAt extends StatelessWidget {
  const _UpdatedAt({required this.boards});

  final List<StopBoard> boards;

  @override
  Widget build(BuildContext context) {
    final times = [for (final b in boards) ?b.updatedAt];
    if (times.isEmpty) return const SizedBox.shrink();
    final oldest = times.reduce((a, b) => a.isBefore(b) ? a : b);
    final hh = oldest.hour.toString().padLeft(2, '0');
    final mm = oldest.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 2),
      child: Text(
        '資料更新於 $hh:$mm',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 右邊那個到站時間。整頁的視覺焦點。
class _Eta extends StatelessWidget {
  const _Eta({required this.label});

  final ArrivalLabel label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (label.tone) {
      ArrivalTone.now => scheme.error,
      ArrivalTone.soon => scheme.primary,
      ArrivalTone.normal => scheme.onSurface,
      ArrivalTone.idle => scheme.onSurfaceVariant,
    };
    return SizedBox(
      width: 72,
      child: Text(
        label.text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: color,
          // 數字要對齊 —— 這一欄是拿來上下掃的。
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 還沒設定金鑰時顯示的引導。
///
/// 這一頁在沒有金鑰的時候會是空的，而**空白畫面看起來就像壞了**。
/// 講清楚少了什麼比顯示五張錯誤卡片有用。
///
/// 這裡刻意不提 TDX、API、金鑰怎麼放 —— 使用者要知道的是「這功能還沒開通」，
/// 不是我們的 build 流程。
class _SetupGuide extends StatelessWidget {
  const _SetupGuide();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus, size: 48, color: scheme.outline),
            const SizedBox(height: 16),
            Text('交通資訊還沒開通', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '公車與火車的到站時間來自交通部的開放資料，'
              '這個版本還沒有帶上查詢用的授權。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

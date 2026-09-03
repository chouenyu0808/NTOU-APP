import 'dart:async';

import 'package:flutter/material.dart';

import '../transit/tdx_client.dart';
import '../transit/transit_config.dart';
import '../transit/transit_models.dart';
import '../transit/transit_repository.dart';
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
    this.isActive = true,
    this.autoRefresh = const Duration(seconds: 30),
  });

  /// 測試會注入一個假的。正式執行時是 null，開頁的時候自己建。
  final TransitRepository? repository;

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

  Future<void> _refresh() async {
    final repo = _repo;
    if (repo == null || !_configured) return;

    // 五個站同時發，不要一個等一個 —— 排隊是 TdxClient 內部在管的，
    // 這裡串起來只會讓使用者多等四倍。
    final boards = await Future.wait([
      for (final stop in repo.config.stops) repo.board(stop),
    ]);
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
              onPressed: _refresh,
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
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _boards.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _StopCard(
          board: _boards[i],
          config: _repo!.config,
        ),
      ),
    );
  }
}

/// 一個站一張卡。
class _StopCard extends StatelessWidget {
  const _StopCard({required this.board, required this.config});

  final StopBoard board;
  final TransitConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final note = board.stop.note;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
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
                      if (note != null)
                        Text(
                          note,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _content(context, scheme),
        ],
      ),
    );
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
          board.stop.kind == TransitStopKind.train
              ? '目前沒有即將進站的列車'
              : '目前沒有班次資訊',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        for (final b in board.buses) _BusRow(arrival: b, config: config),
        for (final t in board.trains) _TrainRow(train: t),
      ],
    );
  }
}

class _Inset extends StatelessWidget {
  const _Inset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: child,
      );
}

/// 一列公車：路線號 · 往哪 · 還有多久。
class _BusRow extends StatelessWidget {
  const _BusRow({required this.arrival, required this.config});

  final BusArrival arrival;
  final TransitConfig config;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = ArrivalLabel.of(
      arrival.estimateSeconds,
      arrival.stopStatus,
      config.stopStatus,
    );

    return Padding(
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
            child: Text(
              arrival.destination.isEmpty ? '' : '往 ${arrival.destination}',
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _Eta(label: label),
        ],
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
    final head =
        [train.trainType, train.trainNo].where((s) => s.isNotEmpty).join(' ');

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
            Text(
              '交通資訊還沒開通',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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

import 'package:flutter/material.dart';

import '../transit/transit_models.dart';
import '../transit/transit_repository.dart';

/// 點一條路線進來看到的：這班車經過哪些站、現在開到哪一站。
///
/// 排版跟站牌看板刻意不同 —— 看板是「掃右邊那一欄找一個數字」，
/// 這一頁是「順著一條線往下看，找到那台車在哪」。所以這裡用時間軸的形狀，
/// 站名靠左對齊成一條直線，車子畫在那條線上。
class RoutePage extends StatefulWidget {
  const RoutePage({
    super.key,
    required this.routeName,
    required this.repository,
    required this.city,
    required this.intercity,
    this.highlightStops = const {},
  });

  final String routeName;
  final TransitRepository repository;
  final String city;
  final bool intercity;

  /// 使用者是從哪一站點進來的。那一列會標起來 —— 一條 68 站的路線攤開來
  /// 很長，沒有這個標記的話他得自己一站一站找「我在哪」。
  ///
  /// **是一組名字不是一個。** 同一個站牌在不同資料集裡叫不同名字：市區公車
  /// 叫「海大體育館」，國道客運叫「海大(體育館)」—— 只比對一個的話，
  /// 點進 1579（國道客運）會整條 27 站都沒有標記。
  final Set<String> highlightStops;

  /// 分頁標題。
  ///
  /// 一條路線的子路線可以很多 —— 1579 有八條（`1579`／`1579A`／`1579B`／
  /// `1579C` 各有去回兩程），103 有兩條。標題要能把它們分開，而且要看得懂。
  ///
  /// 四層退路，一層比一層囉唆，用第一個分得開的：
  ///
  /// 1. **子路線名**（`1579A`）—— 最短，但去回兩程同名所以常常不夠
  /// 2. **往終點站** —— 103 的兩條終點都是八斗子車站，所以也常常不夠
  /// 3. **子路線名 + 往終點站**（`1579A 往 八斗子車站`）—— 1579 靠這層分開
  /// 4. **再補站數** —— 103 靠這層（兩條都往八斗子車站，只有站數不同）
  ///
  /// 分不開的分頁比沒有分頁更糟：使用者切過去看到兩個一樣的標題，
  /// 會以為自己點錯了。
  static List<String> labelsFor(List<RouteVariant> variants) {
    bool unique(List<String> labels) =>
        labels.toSet().length == variants.length;

    final names = [for (final v in variants) v.subRouteName];
    if (!names.any((n) => n.isEmpty) && unique(names)) return names;

    final byDestination = [
      for (final v in variants)
        v.destination.isEmpty ? '路線' : '往 ${v.destination}',
    ];
    if (unique(byDestination)) return byDestination;

    final combined = [
      for (var i = 0; i < variants.length; i++)
        names[i].isEmpty ? byDestination[i] : '${names[i]} ${byDestination[i]}',
    ];
    if (unique(combined)) return combined;

    return [
      for (var i = 0; i < variants.length; i++)
        '${byDestination[i]}（${variants[i].stops.length} 站）',
    ];
  }

  @override
  State<RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<RoutePage> {
  RouteDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await widget.repository.routeDetail(
      widget.routeName,
      city: widget.city,
      intercity: widget.intercity,
    );
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final variants = detail?.variants ?? const <RouteVariant>[];

    return DefaultTabController(
      length: variants.isEmpty ? 1 : variants.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.routeName),
          actions: [
            if (!_loading)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新整理',
                onPressed: _load,
              ),
          ],
          bottom: variants.length > 1
              ? TabBar(
                  // 三條以上就改成可捲的。1579 有八條子路線 —— 硬塞進
                  // 螢幕寬度的話每個標題只剩幾個字，等於全部看不懂。
                  isScrollable: variants.length > 2,
                  tabAlignment: variants.length > 2
                      ? TabAlignment.start
                      : TabAlignment.fill,
                  tabs: [
                    for (final label in RoutePage.labelsFor(variants))
                      Tab(text: label),
                  ],
                )
              : null,
        ),
        body: _body(detail, variants),
      ),
    );
  }

  Widget _body(RouteDetail? detail, List<RouteVariant> variants) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = detail?.error;
    if (error != null) return _Centered(text: error);
    if (variants.isEmpty) return const _Centered(text: '這條路線沒有站序資料');

    return TabBarView(
      children: [
        for (final v in variants)
          _StopTimeline(variant: v, highlightStops: widget.highlightStops),
      ],
    );
  }
}

/// 一條子路線的站序，車畫在上面。
class _StopTimeline extends StatelessWidget {
  const _StopTimeline({required this.variant, required this.highlightStops});

  final RouteVariant variant;
  final Set<String> highlightStops;

  @override
  Widget build(BuildContext context) {
    // 站序編號 → 停在那一站的車。一站可能同時有兩台。
    final byStop = <int, List<BusPosition>>{};
    for (final b in variant.buses) {
      byStop.putIfAbsent(b.stopSequence, () => []).add(b);
    }

    return ListView.builder(
      itemCount: variant.stops.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _Summary(count: variant.buses.length);
        final stop = variant.stops[i - 1];
        return _StopTile(
          stop: stop,
          buses: byStop[stop.sequence] ?? const [],
          isHighlighted: highlightStops.contains(stop.name),
          isFirst: i == 1,
          isLast: i == variant.stops.length,
        );
      },
    );
  }
}

/// 最上面那一句「現在路上有 N 台車」。
///
/// 沒有這句的話，一條沒有任何車的路線看起來就只是一長串站名，
/// 使用者會以為是資料沒載到。
class _Summary extends StatelessWidget {
  const _Summary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        count == 0 ? '現在路上沒有這條路線的車' : '現在路上有 $count 台車',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// 一站一列：左邊是那條線和車，右邊是站名。
class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.buses,
    required this.isHighlighted,
    required this.isFirst,
    required this.isLast,
  });

  final RouteStop stop;
  final List<BusPosition> buses;
  final bool isHighlighted;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBus = buses.isNotEmpty;

    return Container(
      color: isHighlighted
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rail(hasBus: hasBus, isFirst: isFirst, isLast: isLast),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.name,
                      style: TextStyle(
                        fontWeight: isHighlighted
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    for (final b in buses)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          // 離站代表它正往下一站移動 —— 講「在這一站」
                          // 會讓使用者以為還追得上。
                          b.leaving ? '${b.plate} 已離站' : '${b.plate} 在站上',
                          style: TextStyle(fontSize: 12, color: scheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左邊那條時間軸：一條線加一個點，有車的時候點變成公車圖示。
class _Rail extends StatelessWidget {
  const _Rail({
    required this.hasBus,
    required this.isFirst,
    required this.isLast,
  });

  final bool hasBus;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant;

    return SizedBox(
      width: 24,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: 2,
              color: isFirst ? Colors.transparent : line,
            ),
          ),
          hasBus
              ? Icon(Icons.directions_bus, size: 18, color: scheme.primary)
              : Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.outline,
                  ),
                ),
          Expanded(
            child: Container(
              width: 2,
              color: isLast ? Colors.transparent : line,
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

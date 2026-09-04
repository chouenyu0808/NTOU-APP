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

  /// 照方向把子路線分堆，保持原本的順序。
  ///
  /// **這是「往基隆」和「往台北」分開的依據。** 1579 有八條子路線，
  /// 攤平成八個分頁很難找 —— 但它們其實只有兩個方向，`Direction` 0 全是
  /// 往台北那頭、1 全是往八斗子。分成兩個分頁之後，要找「下一班往台北的」
  /// 就只看一個分頁。
  ///
  /// 環狀線（103）兩條子路線的 Direction 都是 0，所以會歸成同一堆 ——
  /// 那是對的：對使用者來說它們就是同一個方向的兩種繞法。
  static List<List<RouteVariant>> byDirection(List<RouteVariant> variants) {
    final groups = <int, List<RouteVariant>>{};
    for (final v in variants) {
      groups.putIfAbsent(v.direction, () => []).add(v);
    }
    return groups.values.toList();
  }

  /// 方向分頁的標題：這個方向最多子路線開往的那個終點。
  ///
  /// 1579 的 dir 0 有三條到圓山、一條到松山高中 —— 取多數的那個，
  /// 標題就是「往 圓山轉運站(玉門)」。用真實站名而不是自己編的「往台北」，
  /// 因為終點站是資料裡有的東西，「台北」是我猜的。
  static String directionLabel(List<RouteVariant> group) {
    final counts = <String, int>{};
    for (final v in group) {
      if (v.destination.isEmpty) continue;
      counts[v.destination] = (counts[v.destination] ?? 0) + 1;
    }
    if (counts.isEmpty) return '路線';
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return '往 ${best.key}';
  }

  /// 同一個方向裡各條子路線的短標籤，畫在分頁底下那排晶片上。
  ///
  /// **比分頁標題短。** 方向分頁已經說了終點，晶片只要能把同一個方向裡的
  /// 幾條分開就好 —— 1579 那邊子路線名（`1579A`）本身就夠；103 那邊兩條
  /// 同名同終點，只剩站數分得開。
  static List<String> chipLabelsFor(List<RouteVariant> group) {
    bool unique(List<String> xs) => xs.toSet().length == group.length;

    final names = [for (final v in group) v.subRouteName];
    if (!names.any((n) => n.isEmpty) && unique(names)) return names;

    final dests = [for (final v in group) '往 ${v.destination}'];
    if (unique(dests)) return dests;

    return [for (final v in group) '${v.stops.length} 站'];
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
    // **分頁是「方向」不是「子路線」。** 1579 攤平成八個分頁很難找，
    // 但它們其實只有兩個方向；子路線退到分頁底下那排晶片。
    final groups = RoutePage.byDirection(variants);

    return DefaultTabController(
      length: groups.isEmpty ? 1 : groups.length,
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
          bottom: groups.length > 1
              ? TabBar(
                  isScrollable: groups.length > 2,
                  tabAlignment: groups.length > 2
                      ? TabAlignment.start
                      : TabAlignment.fill,
                  tabs: [
                    for (final g in groups)
                      Tab(text: RoutePage.directionLabel(g)),
                  ],
                )
              : null,
        ),
        body: _body(detail, groups),
      ),
    );
  }

  Widget _body(RouteDetail? detail, List<List<RouteVariant>> groups) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = detail?.error;
    if (error != null) return _Centered(text: error);
    if (groups.isEmpty) return const _Centered(text: '這條路線沒有站序資料');

    return TabBarView(
      children: [
        for (final g in groups)
          _DirectionView(
            group: g,
            highlightStops: widget.highlightStops,
            stopStatus: widget.repository.config.stopStatus,
          ),
      ],
    );
  }
}

/// 一個方向底下的東西：選子路線的那排晶片 + 站序。
///
/// 晶片只在這個方向有超過一條子路線的時候才出現 —— 只有一條的時候
/// 那排東西是純粹的雜訊。
class _DirectionView extends StatefulWidget {
  const _DirectionView({
    required this.group,
    required this.highlightStops,
    required this.stopStatus,
  });

  final List<RouteVariant> group;
  final Set<String> highlightStops;

  /// `transit.json` 的 StopStatus 對照表，沒有預估時間時用它解釋為什麼。
  final Map<String, String> stopStatus;

  @override
  State<_DirectionView> createState() => _DirectionViewState();
}

class _DirectionViewState extends State<_DirectionView> {
  int _picked = 0;

  @override
  Widget build(BuildContext context) {
    // 資料重整之後子路線數量可能變了，別讓索引指到不存在的地方。
    final index = _picked.clamp(0, widget.group.length - 1);
    final labels = RoutePage.chipLabelsFor(widget.group);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.group.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                for (var i = 0; i < widget.group.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(labels[i]),
                      selected: i == index,
                      onSelected: (_) => setState(() => _picked = i),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _StopTimeline(
            variant: widget.group[index],
            highlightStops: widget.highlightStops,
            stopStatus: widget.stopStatus,
          ),
        ),
      ],
    );
  }
}

/// 一條子路線的站序，車畫在上面。
class _StopTimeline extends StatelessWidget {
  const _StopTimeline({
    required this.variant,
    required this.highlightStops,
    required this.stopStatus,
  });

  final RouteVariant variant;
  final Set<String> highlightStops;
  final Map<String, String> stopStatus;

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
        if (i == 0) {
          return _Summary(
            count: variant.buses.length,
            stops: variant.stops,
            stopStatus: stopStatus,
          );
        }
        final stop = variant.stops[i - 1];
        return _StopTile(
          stop: stop,
          buses: byStop[stop.sequence] ?? const [],
          isHighlighted: highlightStops.contains(stop.name),
          isFirst: i == 1,
          isLast: i == variant.stops.length,
          stopStatus: stopStatus,
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
  const _Summary({
    required this.count,
    required this.stops,
    required this.stopStatus,
  });

  final int count;
  final List<RouteStop> stops;
  final Map<String, String> stopStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(_text, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }

  /// 沒有車的時候要說**為什麼**沒有車。
  ///
  /// 「現在路上沒有這條路線的車」是實話但沒有用 —— 使用者接著要問的是
  /// 「那是還沒發車，還是我錯過末班了？」那兩件事差很多。
  ///
  /// 答案在站牌狀態裡：實測 108 和 8021 在下午三點多是整條路線 97／148 筆
  /// 全部 `StopStatus 3`（末班已過），那是上午班次的路線。103 同一時間是
  /// 44 筆正常 + 88 筆尚未發車。
  String get _text {
    if (count > 0) return '現在路上有 $count 台車';

    // 取沒有預估時間的那些站裡最多的那個狀態 —— 一條路線通常整條同一個狀態。
    final counts = <int, int>{};
    for (final s in stops) {
      if (s.estimateSeconds != null) continue;
      counts[s.stopStatus] = (counts[s.stopStatus] ?? 0) + 1;
    }
    if (counts.isEmpty) return '現在路上沒有這條路線的車';

    final dominant = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    // 0 是「正常」—— 那個狀態說不出為什麼沒有車，講了反而更迷惑。
    final label = dominant.key == 0 ? null : stopStatus['${dominant.key}'];
    if (label == null) return '現在路上沒有這條路線的車';
    return '$label，現在路上沒有車';
  }
}

/// 一站一列：**左邊是還有多久、中間是站名、右邊是那條線和車。**
///
/// 這個順序是照 Bus+ 排的，而且有道理：使用者在這一頁的動作是「由上往下掃，
/// 找一個夠小的數字」，所以時間要在最左邊、對齊成一欄。車的位置是次要的
/// （「喔原來車在那裡」），放右邊那條線上。
class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.buses,
    required this.isHighlighted,
    required this.isFirst,
    required this.isLast,
    required this.stopStatus,
  });

  final RouteStop stop;
  final List<BusPosition> buses;
  final bool isHighlighted;
  final bool isFirst;
  final bool isLast;
  final Map<String, String> stopStatus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: isHighlighted
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      padding: const EdgeInsets.only(left: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              // **沒有預估時間就留一個破折號，不要把狀態重複二十遍。**
              //
              // 一條路線通常整條同一個狀態（108 收班時 97 個站牌全是
              // 末班已過），逐站印出來會變成一整欄一模一樣的字，把這一欄
              // 唯一的用處 —— 上下掃找一個夠小的數字 —— 完全淹掉。
              // 為什麼沒有車，最上面那一行說一次就夠了。
              child: _EtaPill(
                label: stop.estimateSeconds == null
                    ? const ArrivalLabel('—', ArrivalTone.idle)
                    : ArrivalLabel.of(
                        stop.estimateSeconds,
                        stop.stopStatus,
                        stopStatus,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  stop.name,
                  style: TextStyle(
                    fontWeight: isHighlighted
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
            // 車牌貼在右邊那條線旁邊 —— 它是「車在這裡」的註解，
            // 不是這一列的主角。
            if (buses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final b in buses)
                      Text(
                        // 離站代表它正往下一站移動 —— 講「在這一站」
                        // 會讓使用者以為還追得上。
                        b.leaving ? '${b.plate} 已離站' : b.plate,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            _Rail(hasBus: buses.isNotEmpty, isFirst: isFirst, isLast: isLast),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// 左邊那顆到站時間。
///
/// **這一頁的視覺焦點。** 用外框而不是填色，因為一條路線有二三十列，
/// 全部填色會變成一面牆；有車快到的那幾列才用顏色跳出來。
class _EtaPill extends StatelessWidget {
  const _EtaPill({required this.label});

  final ArrivalLabel label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (label.tone) {
      ArrivalTone.now => scheme.error,
      ArrivalTone.soon => scheme.primary,
      ArrivalTone.normal => scheme.onSurface,
      ArrivalTone.idle => scheme.outline,
    };

    return Container(
      width: 74,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
          // 數字要對齊 —— 這一欄是拿來上下掃的。
          fontFeatures: const [FontFeature.tabularFigures()],
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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/tdx_client.dart';
import 'package:ntou_app/src/transit/transit_config.dart';
import 'package:ntou_app/src/transit/transit_models.dart';
import 'package:ntou_app/src/transit/transit_repository.dart';
import 'package:ntou_app/src/ui/route_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

/// 點進一條路線之後看到的那一頁。
///
/// 這一頁要回答的問題只有一個：**這台車現在開到哪一站了。**
/// 所以測試釘的是「車有沒有畫在對的那一列」，以及那些會讓人看錯的地方 ——
/// 環狀線的兩個分頁分不分得開、離站和在站上有沒有講清楚。
void main() {
  group('路線詳情頁', () {
    testWidgets('站序照順序畫出來', (tester) async {
      await _pump(tester, _detail([
        _variant('A', ['八斗子分站', '基隆漁會', '海大體育館']),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('八斗子分站'), findsOneWidget);
      expect(find.text('基隆漁會'), findsOneWidget);
      expect(find.text('海大體育館'), findsOneWidget);
    });

    testWidgets('有車的那一站畫公車圖示，並標出車牌', (tester) async {
      await _pump(tester, _detail([
        _variant(
          'A',
          ['第一站', '第二站'],
          buses: const [
            BusPosition(plate: 'FAC-211', subRouteUid: 'A', stopSequence: 2),
          ],
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.directions_bus), findsOneWidget);
      expect(find.text('FAC-211 在站上'), findsOneWidget);
    });

    /// 離站代表它正往下一站移動 —— 講「在這一站」會讓使用者以為還追得上。
    testWidgets('離站和在站上講的是不同的話', (tester) async {
      await _pump(tester, _detail([
        _variant(
          'A',
          ['第一站', '第二站'],
          buses: const [
            BusPosition(
              plate: '走了的',
              subRouteUid: 'A',
              stopSequence: 1,
              leaving: true,
            ),
            BusPosition(plate: '還在的', subRouteUid: 'A', stopSequence: 2),
          ],
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('走了的 已離站'), findsOneWidget);
      expect(find.text('還在的 在站上'), findsOneWidget);
    });

    /// 沒有這句的話，一條沒有任何車的路線看起來只是一長串站名，
    /// 使用者會以為資料沒載到。
    testWidgets('沒有車的時候要說出來，不要只留一串站名', (tester) async {
      await _pump(tester, _detail([
        _variant('A', ['第一站', '第二站']),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('現在路上沒有這條路線的車'), findsOneWidget);
    });

    testWidgets('有車的時候報數量', (tester) async {
      await _pump(tester, _detail([
        _variant(
          'A',
          ['第一站'],
          buses: const [
            BusPosition(plate: '甲', subRouteUid: 'A', stopSequence: 1),
            BusPosition(plate: '乙', subRouteUid: 'A', stopSequence: 1),
          ],
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('現在路上有 2 台車'), findsOneWidget);
    });

    /// 一條 68 站的路線攤開來很長，沒有標記的話使用者得自己一站一站
    /// 找「我剛剛是從哪裡點進來的」。
    testWidgets('從哪一站點進來的，那一站要粗體標起來', (tester) async {
      await _pump(
        tester,
        _detail([
          _variant('A', ['第一站', '海大體育館', '第三站']),
        ]),
        highlightStop: '海大體育館',
      );
      await tester.pumpAndSettle();

      final marked = tester.widget<Text>(find.text('海大體育館'));
      expect(marked.style?.fontWeight, FontWeight.w700);
      final plain = tester.widget<Text>(find.text('第一站'));
      expect(plain.style?.fontWeight, FontWeight.w400);
    });

    testWidgets('查不到站序時給一句話', (tester) async {
      await _pump(
        tester,
        const RouteDetail(routeName: '103', error: '查不到這條路線的站序'),
      );
      await tester.pumpAndSettle();

      expect(find.text('查不到這條路線的站序'), findsOneWidget);
    });
  });

  /// 分頁標題分不開的話，使用者切過去看到兩個一樣的標題，
  /// 會以為自己點錯了 —— 比沒有分頁更糟。
  group('分頁標題', () {
    test('子路線名字不一樣就直接用', () {
      final labels = RoutePage.labelsFor([
        _variant('A', ['甲'], name: '103區間'),
        _variant('B', ['乙'], name: '103'),
      ]);
      expect(labels, ['103區間', '103']);
    });

    /// 103 就是這樣：兩條站序同名、連 Direction 都一樣。
    test('環狀線兩條同名時，退回用終點站分', () {
      final labels = RoutePage.labelsFor([
        _variant('A', ['甲一', '八斗子車站'], name: '103'),
        _variant('B', ['乙一', '基隆轉運站'], name: '103'),
      ]);
      expect(labels, ['往 八斗子車站', '往 基隆轉運站']);
    });

    test('連終點都一樣就補站數，至少兩個分頁分得開', () {
      final labels = RoutePage.labelsFor([
        _variant('A', ['甲一', '甲二', '八斗子車站'], name: '103'),
        _variant('B', ['乙一', '八斗子車站'], name: '103'),
      ]);
      expect(labels, ['往 八斗子車站（3 站）', '往 八斗子車站（2 站）']);
      expect(labels.toSet(), hasLength(2));
    });
  });
}

// --------------------------------------------------------------- 測試用具

RouteVariant _variant(
  String uid,
  List<String> names, {
  String name = '103',
  List<BusPosition> buses = const [],
}) =>
    RouteVariant(
      subRouteUid: uid,
      subRouteName: name,
      direction: 0,
      stops: [
        for (var i = 0; i < names.length; i++)
          RouteStop(stopUid: '$uid-$i', name: names[i], sequence: i + 1),
      ],
      buses: buses,
    );

RouteDetail _detail(List<RouteVariant> variants) =>
    RouteDetail(routeName: '103', variants: variants);

Future<void> _pump(
  WidgetTester tester,
  RouteDetail detail, {
  String highlightStop = '',
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: NtouTheme.of(Brightness.light),
    home: RoutePage(
      routeName: '103',
      repository: _FakeRepo(detail),
      city: 'Keelung',
      intercity: false,
      highlightStop: highlightStop,
    ),
  ));
}

class _FakeRepo extends TransitRepository {
  _FakeRepo(this.detail) : super(config: _config, client: _client);

  final RouteDetail detail;

  @override
  Future<RouteDetail> routeDetail(
    String routeName, {
    required String city,
    required bool intercity,
  }) async =>
      detail;

  static final TdxClient _client = TdxClient(
    config: _config,
    clientId: 'id',
    clientSecret: 'secret',
    dio: Dio(),
  );
}

/// `timeout` 和 `min_interval` 都是 0 —— 兩者都會排計時器，
/// 而 widget test 會以「Pending timers」失敗。
final TransitConfig _config = TransitConfig.fromJson({
  'auth': {'token_url': 'https://example.invalid/token'},
  'api': {
    'base_url': 'https://example.invalid/api/',
    'min_interval_seconds': 0,
    'timeout_seconds': 0,
  },
  'stops': const [],
});

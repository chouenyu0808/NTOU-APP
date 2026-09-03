import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/tdx_client.dart';
import 'package:ntou_app/src/transit/transit_config.dart';
import 'package:ntou_app/src/transit/transit_models.dart';
import 'package:ntou_app/src/transit/transit_repository.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:ntou_app/src/storage/favorite_route_store.dart';
import 'package:ntou_app/src/ui/route_page.dart';
import 'package:ntou_app/src/ui/transit_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('交通分頁', () {
    // 最愛存在 SharedPreferences。沒有這個的話 plugin 不存在，
    // 讀最愛會丟 MissingPluginException —— 那個錯誤被吞掉了，
    // 但畫面會因為多一次 async 往返而慢一拍，測試看起來像整頁沒畫出來。
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('沒有金鑰時給一句話，不是五張錯誤卡片', (tester) async {
      await _pump(tester, _FakeRepo(const [], configured: false));
      await tester.pump();

      expect(find.text('交通資訊還沒開通'), findsOneWidget);
      // 沒設定就不該去打 —— 打了會是五次失敗，畫面上五張紅卡片，
      // 而真正該說的只有一句話。
      expect(find.text('海大體育館'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('沒有金鑰時不會去打 TDX', (tester) async {
      final repo = _FakeRepo(const [], configured: false);
      await _pump(tester, repo);
      await tester.pump();

      expect(repo.calls, 0);
      await _teardown(tester);
    });

    testWidgets('站名、路線、到站時間都畫得出來', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(routeName: '103', destination: '八斗子', estimateSeconds: 90),
              BusArrival(routeName: '104', destination: '新豐街', estimateSeconds: 600),
            ],
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('海大體育館'), findsOneWidget);
      expect(find.text('103'), findsOneWidget);
      expect(find.text('往 八斗子'), findsOneWidget);
      expect(find.text('將到站'), findsOneWidget);
      expect(find.text('10 分'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('有車的那一列補上「還有幾站」和「末班車」', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(
                routeName: '104',
                destination: '八斗子車站',
                estimateSeconds: 725,
                stopsAway: 19,
                isLastBus: true,
              ),
            ],
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('還有 19 站'), findsOneWidget);
      expect(find.text('末班車'), findsOneWidget);
      expect(find.text('12 分'), findsOneWidget);
      await _teardown(tester);
    });

    /// 沒車的那幾筆 `StopCountDown` 一律是 0，`IsLastBus` 一律是 false。
    ///
    /// 照印會變成一整排「還有 0 站」—— 深夜的看板 15 筆裡有 14 筆是這種，
    /// 等於整張卡片被雜訊塞滿，而真正有車的那一筆反而找不到。
    testWidgets('沒車的那幾列不要印「還有 0 站」', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(routeName: '103', stopStatus: 1, stopsAway: 0),
              BusArrival(routeName: '108', stopStatus: 1, stopsAway: 0),
            ],
          ),
        ]),
      );
      await tester.pump();

      expect(find.textContaining('0 站'), findsNothing);
      expect(find.textContaining('還有'), findsNothing);
      // 該說的那句話還是要在 —— 為什麼沒車，靠這一欄講。
      expect(find.text('尚未發車'), findsNWidgets(2));
      await _teardown(tester);
    });

    testWidgets('車牌畫得出來，但沒有車牌就不留一個空的分隔點', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(
                routeName: '104',
                estimateSeconds: 725,
                plateNumber: 'FAC-211',
              ),
              BusArrival(routeName: '103', estimateSeconds: 300),
            ],
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('FAC-211'), findsOneWidget);
      // 第二班沒車牌 —— 不該因此多出一個孤零零的「 · 」。
      expect(find.text(' · '), findsNothing);
      await _teardown(tester);
    });

    /// TDX 每 30 秒才換一次資料，畫面也每 30 秒重整一次。
    /// 沒有這一行的話，使用者會以為數字卡住了。
    testWidgets('標出資料更新時間', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [BusArrival(routeName: '103', estimateSeconds: 60)],
            updatedAt: DateTime(2026, 9, 4, 7, 5),
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('資料更新於 07:05'), findsOneWidget);
      await _teardown(tester);
    });

    /// 五個站是排隊送出的，時間差幾秒。報最新的那個等於宣稱資料比實際更新，
    /// 所以取最舊的 —— 寧可講保守的那一邊。
    testWidgets('多張看板時間不同，取最舊的那個', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [BusArrival(routeName: '103', estimateSeconds: 60)],
            updatedAt: DateTime(2026, 9, 4, 7, 9),
          ),
          StopBoard(
            stop: _keelung,
            updatedAt: DateTime(2026, 9, 4, 7, 5),
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('資料更新於 07:05'), findsOneWidget);
      expect(find.text('資料更新於 07:09'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('火車那張卡顯示車次與誤點', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _keelung,
            trains: const [
              TrainDeparture(
                trainNo: '1234',
                trainType: '區間',
                destination: '樹林',
                scheduledTime: '07:32',
                delayMinutes: 5,
              ),
              TrainDeparture(
                trainNo: '110',
                trainType: '自強',
                destination: '潮州',
                scheduledTime: '07:45',
              ),
            ],
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('區間 1234'), findsOneWidget);
      expect(find.text('07:32'), findsOneWidget);
      expect(find.text('誤點 5 分'), findsOneWidget);
      // 準點的那一班什麼都不說 —— 每列都掛「準點」的話，
      // 真正誤點的那一列就不顯眼了。
      expect(find.textContaining('準點'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('一站壞掉，其他站照樣看得到', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(stop: _keelung, error: '連不上交通資料服務'),
          StopBoard(
            stop: _gym,
            buses: const [BusArrival(routeName: '103', estimateSeconds: 60)],
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('連不上交通資料服務'), findsOneWidget);
      expect(find.text('103'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('「沒有車」和「查不到」講的是不同的話', (tester) async {
      await _pump(
        tester,
        _FakeRepo([StopBoard(stop: _keelung), StopBoard(stop: _gym)]),
      );
      await tester.pump();

      // 深夜沒班次是正常的。講成錯誤會讓使用者一直重按重新整理。
      expect(find.text('目前沒有即將進站的列車'), findsOneWidget);
      expect(find.text('目前沒有班次資訊'), findsOneWidget);
      await _teardown(tester);
    });

    /// **這一條守的是 [HomeShell] 那個 `IndexedStack`。**
    ///
    /// 四個分頁從開 App 起就一直掛載著，交通頁裡有一個每 30 秒重抓的計時器。
    /// 不看 isActive 的話，使用者整天在看課表，這一頁照樣整天打交通部的
    /// 伺服器 —— 一天下來是上千個沒有人會看到的請求。
    testWidgets('按愛心會釘起來，而且存得住', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = FavoriteRouteStore();
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [BusArrival(routeName: '103', estimateSeconds: 300)],
          ),
        ]),
        favorites: store,
      );
      await tester.pump();

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      // 真的寫進去了，不是只有畫面上變色。
      expect(await store.read(), {'103'});
      await _teardown(tester);
    });

    /// 釘 103 的人要的是「一眼找到 103」。
    testWidgets('釘起來的路線排到最上面', (tester) async {
      SharedPreferences.setMockInitialValues({
        'transit.favorites': ['108'],
      });
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(routeName: '103', estimateSeconds: 60),
              BusArrival(routeName: '104', estimateSeconds: 300),
              BusArrival(routeName: '108', estimateSeconds: 900),
            ],
          ),
        ]),
        favorites: FavoriteRouteStore(),
      );
      // 最愛是非同步讀進來的 —— 多 pump 一次讓它到位。
      await tester.pump();
      await tester.pump();

      final rows = tester
          .widgetList<Text>(find.descendant(
            of: find.byType(Card),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .toList();
      // 108 雖然最久才到，但它被釘住了，要排在 103、104 前面。
      expect(rows.indexOf('108'), lessThan(rows.indexOf('103')));
      await _teardown(tester);
    });

    /// 讀不到最愛不該讓整頁停在轉圈圈 —— 公車時間跟本機儲存毫無關係。
    testWidgets('最愛讀不到時，到站時間照樣顯示', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [BusArrival(routeName: '103', estimateSeconds: 60)],
          ),
        ]),
        favorites: _BrokenFavorites(),
      );
      await tester.pump();

      expect(find.text('103'), findsOneWidget);
      expect(find.text('將到站'), findsOneWidget);
      await _teardown(tester);
    });

    /// 點一列公車要開到路線詳情頁去看「這台車開到哪一站」。
    testWidgets('點一列公車會打開那條路線', (tester) async {
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(routeName: '103', estimateSeconds: 300),
            ],
          ),
        ]),
      );
      await tester.pump();

      await tester.tap(find.text('103'));
      await tester.pumpAndSettle();

      // 詳情頁的標題就是路線名。看板那張卡片已經被蓋掉了。
      expect(find.text('海大體育館'), findsNothing);
      expect(find.byType(RoutePage), findsOneWidget);
      await _teardown(tester);
    });

    /// 愛心是那一列裡面的另一個按鈕。按它只能切換釘選，
    /// **不可以順便把詳情頁也打開** —— 使用者只是想釘一下。
    testWidgets('按愛心不會連帶打開路線頁', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(
        tester,
        _FakeRepo([
          StopBoard(
            stop: _gym,
            buses: const [
              BusArrival(routeName: '103', estimateSeconds: 300),
            ],
          ),
        ]),
        favorites: FavoriteRouteStore(),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(find.byType(RoutePage), findsNothing);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('沒在看這一頁的時候，計時器不會自己跑', (tester) async {
      final repo = _FakeRepo([
        StopBoard(
          stop: _gym,
          buses: const [BusArrival(routeName: '103', estimateSeconds: 60)],
        ),
      ]);
      await _pump(
        tester,
        repo,
        isActive: false,
        autoRefresh: const Duration(seconds: 1),
      );
      await tester.pump();

      final afterFirstBuild = repo.calls;
      // 讓時間走過好幾個間隔。
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));

      expect(repo.calls, afterFirstBuild,
          reason: '背景分頁不該自己去抓資料');
      await _teardown(tester);
    });

    testWidgets('切回這一頁會馬上補一次，不是等下一個間隔', (tester) async {
      final repo = _FakeRepo([
        StopBoard(
          stop: _gym,
          buses: const [BusArrival(routeName: '103', estimateSeconds: 60)],
        ),
      ]);

      // 先當作在別的分頁。
      await _pump(tester, repo, isActive: false, autoRefresh: _long);
      await tester.pump();
      final before = repo.calls;

      // 切過來。
      await _pump(tester, repo, isActive: true, autoRefresh: _long);
      await tester.pump();

      expect(repo.calls, greaterThan(before));
      await _teardown(tester);
    });
  });
}

const Duration _long = Duration(hours: 1);

const _gym = TransitStop(
  id: 'ntou-gym',
  name: '海大體育館',
  kind: TransitStopKind.cityBus,
);

const _keelung = TransitStop(
  id: 'tra-keelung',
  name: '台鐵基隆站',
  kind: TransitStopKind.train,
);

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  bool isActive = true,
  Duration autoRefresh = _long,
  FavoriteRouteStore? favorites,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: NtouTheme.of(Brightness.light),
    home: TransitPage(
      repository: repo,
      favorites: favorites,
      isActive: isActive,
      autoRefresh: autoRefresh,
    ),
  ));
}

/// 把頁面拆掉，讓計時器被 cancel。
///
/// 不做的話測試會以「A Timer is still pending」失敗，而那個訊息完全看不出
/// 跟交通頁有關。
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// 回預先準備好的看板，順便數被問了幾次。
class _FakeRepo extends TransitRepository {
  _FakeRepo(this.boards, {this.configured = true})
      : super(config: _config, client: _client(configured));

  final List<StopBoard> boards;
  final bool configured;
  int calls = 0;

  @override
  bool get isConfigured => configured;

  @override
  Future<StopBoard> board(TransitStop stop) async {
    calls++;
    return boards.firstWhere(
      (b) => b.stop.id == stop.id,
      orElse: () => StopBoard(stop: stop),
    );
  }

  static TdxClient _client(bool configured) => TdxClient(
        config: _config,
        clientId: configured ? 'id' : '',
        clientSecret: configured ? 'secret' : '',
        dio: Dio(),
      );
}

/// `stops` 決定畫面上會問哪幾站 —— 這裡放兩站就夠測排版了。
final TransitConfig _config = TransitConfig.fromJson({
  'api': {'min_interval_seconds': 0, 'timeout_seconds': 0},
  'stop_status': {'0': '正常', '1': '尚未發車'},
  'stops': [
    {'id': 'tra-keelung', 'name': '台鐵基隆站', 'kind': 'train'},
    {'id': 'ntou-gym', 'name': '海大體育館', 'kind': 'city_bus'},
  ],
});

/// 永遠讀不到的最愛儲存。真機上這會是 SharedPreferences 出問題，
/// 而那不該讓交通頁看不到公車。
class _BrokenFavorites implements FavoriteRouteStore {
  @override
  Future<Set<String>> read() async => throw StateError('讀不到');

  @override
  Future<Set<String>> toggle(String route) async => throw StateError('存不進去');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

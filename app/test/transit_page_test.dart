import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/tdx_client.dart';
import 'package:ntou_app/src/transit/transit_config.dart';
import 'package:ntou_app/src/transit/transit_models.dart';
import 'package:ntou_app/src/transit/transit_repository.dart';
import 'package:ntou_app/src/ui/theme.dart';
import 'package:ntou_app/src/ui/transit_page.dart';

void main() {
  group('交通分頁', () {
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
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: NtouTheme.of(Brightness.light),
    home: TransitPage(
      repository: repo,
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

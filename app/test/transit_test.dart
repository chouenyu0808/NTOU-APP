import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/tdx_client.dart';
import 'package:ntou_app/src/transit/transit_config.dart';
import 'package:ntou_app/src/transit/transit_models.dart';
import 'package:ntou_app/src/transit/transit_repository.dart';
import 'package:ntou_app/src/ui/route_page.dart';

/// 交通分頁的資料層。
///
/// 這裡守的東西跟 AIS 那邊不太一樣。TDX 的公開 swagger 在 schema 那段是
/// 截斷的，沒有金鑰打不到真實回應 —— 所以 `transit_repository.dart` 裡的
/// 欄位名一開始是**候選清單**而不是單一答案。
///
/// **2026-09-03 公車那半邊對完了**（`spike/tdx.py --save`，fixture 在
/// `spike/fixtures/tdx/`），所以公車的欄位已經收斂成確定的名字，
/// 改由下面「對著真實回應解析」那一組釘死。台鐵那半邊那次被 TDX 擋掉了
/// （HTTP 429），**還是候選清單，一個都沒驗證過** —— 有人把它收斂成單一
/// 名字（看起來很像在清理程式碼）的時候，那半邊的測試會紅。
///
/// v2 的巢狀多語系物件和 v3 的扁平字串兩種都要吃得下去，這件事不變。
void main() {
  group('到站時間怎麼說', () {
    // 對照表是 transit.json 裡那一份，測試自己給一份等價的。
    const status = {'0': '正常', '1': '尚未發車', '3': '末班已過'};

    ArrivalLabel label(int? seconds, [int st = 0]) =>
        ArrivalLabel.of(seconds, st, status);

    test('30 秒內是進站中', () {
      expect(label(0).text, '進站中');
      expect(label(29).text, '進站中');
      expect(label(0).tone, ArrivalTone.now);
    });

    test('兩分鐘內是將到站', () {
      expect(label(30).text, '將到站');
      expect(label(119).text, '將到站');
      expect(label(60).tone, ArrivalTone.soon);
    });

    test('再遠就報分鐘，而且無條件捨去', () {
      expect(label(120).text, '2 分');
      // 179 秒是 2 分 59 秒。報「3 分」的話使用者會晚一分鐘出門。
      expect(label(179).text, '2 分');
      expect(label(180).text, '3 分');
    });

    test('不做「N 分 M 秒」', () {
      // 公車的預估本來就有一兩分鐘誤差，寫出秒數是假的精確。
      expect(label(155).text, isNot(contains('秒')));
    });

    /// **這是這一組裡最重要的一條。**
    ///
    /// TDX 沒有預估值的時候 `EstimateTime` 是 null，不是 0。把 null 當 0
    /// 處理的話畫面會顯示「進站中」—— 使用者會為了一班根本不存在的車
    /// 跑去站牌等。
    test('沒有預估值不能變成「進站中」', () {
      expect(label(null).text, isNot('進站中'));
      expect(label(null).text, '--');
      expect(label(null).tone, ArrivalTone.idle);
      // 負數同理，那也是「沒有」的一種寫法。
      expect(label(-1).text, isNot('進站中'));
    });

    test('沒有預估值時用狀態碼解釋為什麼', () {
      expect(label(null, 1).text, '尚未發車');
      expect(label(null, 3).text, '末班已過');
    });

    test('認不得的狀態碼原樣顯示，不猜', () {
      // 對照表裡只有 0/1/3。9 是沒見過的 —— 顯示「狀態 9」讓人知道要去查，
      // 比挑一個看起來合理的說法好。
      expect(label(null, 9).text, '狀態 9');
    });
  });

  group('TDX 的回應形狀', () {
    test('v2 的裸陣列', () {
      expect(TdxClient.unwrap([
        {'RouteName': '103'},
      ]).length, 1);
    });

    test('v3 包在物件裡，而且那個 key 每個端點都不一樣', () {
      // 不能寫死 'Stations' 或 'TrainLiveBoards' —— 找出第一個陣列就好。
      expect(TdxClient.unwrap({
        'UpdateTime': '2026-09-03T08:00:00',
        'TrainLiveBoards': [
          {'TrainNo': '123'},
        ],
      }).length, 1);
      expect(TdxClient.unwrap({
        'Stations': [
          {'StationID': '0900'},
        ],
      }).first['StationID'], '0900');
    });

    test('形狀不認得就當作沒資料，不要爆掉', () {
      expect(TdxClient.unwrap(null), isEmpty);
      expect(TdxClient.unwrap('壞掉的東西'), isEmpty);
      expect(TdxClient.unwrap({'UpdateTime': '2026-09-03'}), isEmpty);
    });

    test('陣列裡不是物件的元素濾掉', () {
      expect(TdxClient.unwrap([
        {'RouteName': '103'},
        'x',
        null,
      ]).length, 1);
    });
  });

  group('transit.json', () {
    late TransitConfig config;

    setUpAll(() {
      final raw = File('assets/transit.json').readAsStringSync();
      config = TransitConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    });

    test('使用者點名的五個站都在', () {
      final names = config.stops.map((s) => s.name).toList();
      expect(names, containsAll([
        '台鐵基隆站',
        '基隆轉運站',
        '海大體育館',
        '海大濱海校門',
        '海大祥豐校門',
      ]));
      expect(config.stops, hasLength(5));
    });

    test('海大那三個是基隆市公車，轉運站是國道客運，基隆站是台鐵', () {
      TransitStop stop(String name) =>
          config.stops.firstWhere((s) => s.name == name);

      // 台北市政府的公車資料涵蓋不到這三站 —— 它們是基隆市的。
      for (final n in ['海大體育館', '海大濱海校門', '海大祥豐校門']) {
        expect(stop(n).kind, TransitStopKind.cityBus, reason: n);
        expect(stop(n).city, 'Keelung', reason: n);
      }
      expect(stop('基隆轉運站').kind, TransitStopKind.interCityBus);
      expect(stop('台鐵基隆站').kind, TransitStopKind.train);
    });

    /// 台鐵車站代碼**查證過了**：2026-09-03 對 TDX 的 `v3/Rail/TRA/Station`
    /// 查出基隆 = `0900`。
    ///
    /// 這個測試原本守的是「必須留空，不准猜一個填進去」。查證之後意思換了，
    /// 但要防的還是同一件事：**錯的代碼會安靜地查出別站的車**，畫面上一切
    /// 正常，只是列車全是別的地方的。所以現在改成把查證過的那個值釘死 ——
    /// 有人改動它（或退回空字串）這裡就會紅，逼他重跑一次 spike/tdx.py。
    test('台鐵站代碼是查證過的 0900，不是猜的也不是空的', () {
      final keelung = config.stops.firstWhere((s) => s.name == '台鐵基隆站');
      expect(keelung.stationId, '0900');
      expect(keelung.stationName, '基隆');
    });

    /// 站名對過真實回應了，所以 `match_names` 現在是空的 —— 本來備援的
    /// 「海洋大學濱海校門」「濱海校門」那些寫法 TDX 裡根本不存在。
    ///
    /// 但 `allNames` **永遠不能是空的**，這比候選有幾個重要得多：
    /// 空的話 `_nameFilter` 產出空字串，`$filter` 整個不會送出去，
    /// 而沒有 filter 的查詢會把**整個基隆市的公車**通通撈回來 ——
    /// 畫面上照樣是一張正常的卡片，只是那 60 班車跟這個站牌毫無關係。
    test('每個站都問得出一個名字，allNames 不會是空的', () {
      for (final stop in config.stops) {
        expect(stop.allNames, isNotEmpty, reason: '${stop.name} 沒有可查的名字');
        expect(stop.allNames, contains(stop.name));
      }
    });

    test('寫給人看的 _comment 沒有被當成端點或狀態碼', () {
      expect(config.endpoints.keys.any((k) => k.startsWith('_')), isFalse);
      expect(config.stopStatus.keys.any((k) => k.startsWith('_')), isFalse);
      expect(config.endpoints['city_bus_arrivals'], isNotEmpty);
    });

    test('端點的洞填得起來', () {
      expect(
        config.endpoint('city_bus_arrivals', city: 'Keelung'),
        contains('Keelung'),
      );
      expect(
        config.endpoint('city_bus_arrivals', city: 'Keelung'),
        isNot(contains('{city}')),
      );
    });

    test('沒有的端點回空字串，不要丟例外', () {
      // JSON 少一行不該讓整個分頁開不起來。
      expect(config.endpoint('不存在的端點'), isEmpty);
    });
  });

  group('解析 TDX 回來的資料', () {
    /// v2 的巢狀多語系寫法。
    test('公車：{Zh_tw: ...} 的欄位取得到中文', () async {
      final repo = _repoReturning([
        {
          'RouteName': {'Zh_tw': '103', 'En': '103'},
          'EstimateTime': 300,
          'StopStatus': 0,
        },
      ]);
      final board = await repo.board(_cityBusStop);
      expect(board.buses.single.routeName, '103');
      expect(board.buses.single.estimateSeconds, 300);
    });

    /// v3 有的地方把多語系物件扁平成字串。兩種都要吃。
    test('公車：扁平成字串的欄位也吃得下', () async {
      final repo = _repoReturning([
        {'RouteName': '104', 'EstimateTime': 60},
      ]);
      final board = await repo.board(_cityBusStop);
      expect(board.buses.single.routeName, '104');
    });

    test('公車：沒有預估值的排到後面，不是排到最前面', () async {
      final repo = _repoReturning([
        {'RouteName': '沒班次', 'EstimateTime': null, 'StopStatus': 1},
        {'RouteName': '慢的', 'EstimateTime': 600},
        {'RouteName': '快的', 'EstimateTime': 60},
      ]);
      final board = await repo.board(_cityBusStop);
      expect(
        board.buses.map((b) => b.routeName).toList(),
        ['快的', '慢的', '沒班次'],
      );
      expect(board.buses.last.estimateSeconds, isNull);
    });

    /// 欄位名是 `ScheduleDepartureTime`，**不是 `Scheduled...`**。
    ///
    /// 這個測試原本寫的是多一個 d 的那個名字，而程式碼也用同一個 ——
    /// 兩邊講好了一個不存在的欄位，所以測試一直是綠的，直到拿真實回應
    /// 對過才發現整欄表定時間根本解析不出來。
    test('火車：時間切掉秒數', () async {
      final repo = _repoReturning([
        {
          'TrainNo': '1234',
          'TrainTypeName': {'Zh_tw': '區間'},
          'EndingStationName': {'Zh_tw': '樹林'},
          'ScheduleDepartureTime': '07:32:00',
          'DelayTime': 5,
        },
      ], stationId: '0900');
      final board = await repo.board(_trainStop);
      final t = board.trains.single;
      expect(t.scheduledTime, '07:32');
      expect(t.trainType, '區間');
      expect(t.destination, '樹林');
      expect(t.delayMinutes, 5);
    });

    test('火車：認不得的時間格式原樣留著，不要變成空白', () async {
      final repo = _repoReturning([
        {'TrainNo': '1', 'ScheduleDepartureTime': '待發'},
      ], stationId: '0900');
      expect((await repo.board(_trainStop)).trains.single.scheduledTime, '待發');
    });

    test('一站失敗不會拖垮整批 —— 錯誤包在那一站身上', () async {
      final repo = _repoFailing();
      final board = await repo.board(_cityBusStop);
      expect(board.error, isNotNull);
      expect(board.buses, isEmpty);
    });
  });

  group('查詢一定要帶著站名 filter', () {
    /// 這一組守的是一個**看不出來的**錯：`$filter` 沒送出去。
    ///
    /// 到站端點是「整個基隆市」的，站名 filter 是唯一把它縮到這個站牌的
    /// 東西。filter 掉了的話 TDX 會很乾脆地回 60 班車，畫面上是一張長得
    /// 完全正常的卡片 —— 只是那些車跟這個站牌一點關係都沒有。
    /// 沒有錯誤、沒有紅字、沒有人會發現。
    test(r'市區公車：站名進得了 $filter', () async {
      final spy = _RecordingAdapter();
      final repo = _repoWith(spy);
      await repo.board(_cityBusStop);

      final query = spy.lastDataRequest!.queryParameters;
      expect(query[r'$filter'], isNotNull);
      expect(query[r'$filter'], contains('海大體育館'));
      expect(query[r'$format'], 'JSON');
    });

    test('站名裡的單引號會被跳脫，不會把 OData 查詢拆掉', () async {
      final spy = _RecordingAdapter();
      final repo = _repoWith(spy);
      await repo.board(const TransitStop(
        id: 'x',
        name: "海大'體育館",
        kind: TransitStopKind.cityBus,
      ));

      // OData 的字串用單引號包，值裡的單引號要疊成兩個。
      expect(spy.lastDataRequest!.queryParameters[r'$filter'],
          contains("海大''體育館"));
    });
  });

  group('對著真實回應解析（spike/fixtures/tdx/）', () {
    /// 這一組跟上面手寫 payload 的測試不一樣：吃的是**真的從 TDX 抓下來的
    /// 回應**（2026-09-03 深夜，`spike/tdx.py --save`）。
    ///
    /// TDX 的公車資料沒有任何個資，所以這些 fixture 跟 AIS 那些不同，
    /// 是進版控的 —— 可以拿來把解析釘死。
    final dir = Directory('../spike/fixtures/tdx');
    final skip = dir.existsSync()
        ? null
        : '沒有 TDX fixture（跑 spike/tdx.py --save 產生）';

    List<Map<String, dynamic>> rowsOf(String name) => [
          for (final e in jsonDecode(
                  File('${dir.path}/$name').readAsStringSync()) as List)
            e as Map<String, dynamic>,
        ];

    test('海大體育館：去重之後 8 筆，只有一班真的有車', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      // 原始回應是 15 筆，但那是 TDX 按子路線拆出來的 —— 去重之後
      // 是 4 條路線 × 馬路兩邊 2 個站牌 = 8 筆。
      expect(board.buses, hasLength(8));
      final running = board.buses.where((b) => b.estimateSeconds != null);
      expect(running, hasLength(1));
      expect(running.single.routeName, '104');
      expect(running.single.estimateSeconds, 725);
      // 有預估值的排最前面，其餘 14 班沉到後面去。
      expect(board.buses.first.estimateSeconds, 725);
    }, skip: skip);

    /// **這個測試是整組裡最重要的一個。**
    ///
    /// 同一筆資料裡 `EstimateTime: 725`（秒）配 `StopCountDown: 19`（站）。
    /// 有人哪天覺得「EstimateTime 常常是 null，拿 StopCountDown 當備援吧」，
    /// 那班車就會從「12 分鐘」變成「19 秒 → 進站中」—— 畫面上完全正常，
    /// 使用者跑去站牌等一班十二分鐘後才來的車。
    test('StopCountDown 是站數不是秒數，絕不能被當成到站時間', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      final seconds = board.buses.map((b) => b.estimateSeconds).toSet();
      expect(seconds, containsAll(<int?>[725, null]));
      // 19 是那筆的 StopCountDown。它不該以任何形式變成秒數。
      expect(seconds, isNot(contains(19)));
    }, skip: skip);

    test('沒車的那幾筆沒有 EstimateTime，但不能因此變成「進站中」', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      const status = {'0': '正常', '3': '末班已過'};
      for (final b in board.buses.where((b) => b.estimateSeconds == null)) {
        final label = ArrivalLabel.of(b.estimateSeconds, b.stopStatus, status);
        expect(label.text, isNot('進站中'));
      }
    }, skip: skip);

    /// 「還有幾站」和「末班車」都是從同一批到站資料裡拿的，不用多打請求。
    test('海大體育館：解得出「還有 19 站」和「末班車」', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      final running = board.buses.where((b) => b.isRunning).single;
      expect(running.routeName, '104');
      expect(running.stopsAway, 19);
      expect(running.isLastBus, isTrue);
    }, skip: skip);

    /// 沒車的那幾筆 StopCountDown 一律是 0 —— 那不是「已經到站」，
    /// 是「這個欄位沒有意義」。畫面靠 isRunning 把它們濾掉。
    test('沒車的那幾筆不會被當成「還有 0 站就到了」', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      final idle = board.buses.where((b) => !b.isRunning);
      expect(idle, hasLength(7));
      for (final b in idle) {
        expect(b.stopsAway, 0);
      }
    }, skip: skip);

    /// **`IsLastBus` 不是「還會來的末班車」。**
    ///
    /// 它標的是「這個班次是今天最後一班」，跟車還在不在路上無關 ——
    /// 這份深夜的 fixture 去重後 8 筆裡有 6 筆帶著 true，其中 5 筆是已經
    /// 開走的（末班已過）。畫面上沒有用 isRunning 擋的話，那張卡片會有
    /// 六行同時喊「末班車」。
    ///
    /// 這個測試存在的理由是：那個數字看起來太像 bug，很容易有人「順手
    /// 修好它」，把顯示條件放寬。
    test('IsLastBus 在沒車的那幾筆上也會是 true，所以顯示要靠 isRunning 擋', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      expect(board.buses.where((b) => b.isLastBus), hasLength(6));
      // 真正該讓使用者看到的只有這一筆：最後一班，而且還沒走。
      final worthShowing =
          board.buses.where((b) => b.isLastBus && b.isRunning);
      expect(worthShowing, hasLength(1));
      expect(worthShowing.single.routeName, '104');
    }, skip: skip);

    test('車牌的 -1 是哨兵值，不是車牌，不能顯示出去', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      expect(board.buses.map((b) => b.plateNumber), isNot(contains('-1')));
      expect(
        board.buses.map((b) => b.plateNumber).where((p) => p.isNotEmpty),
        ['FAC-211'],
      );
    }, skip: skip);

    /// 國道客運走的是另一個端點，但回來的形狀跟市區公車一樣。
    test('基隆轉運站：國道客運同一套解析吃得下', () async {
      final repo = _repoReturning(rowsOf('keelung-bus-terminal.json'));
      final board = await repo.board(const TransitStop(
        id: 'keelung-bus-terminal',
        name: '基隆轉運站',
        kind: TransitStopKind.interCityBus,
      ));

      // 53 筆是按子路線拆的，去重之後 21 筆。
      expect(board.buses, hasLength(21));
      expect(board.buses.first.estimateSeconds, 1979);
      expect(board.buses.first.routeName, '1813');
    }, skip: skip);

    /// 台鐵的 fixture 是 v3 的形狀（包在 `StationLiveBoards` 底下），
    /// 所以這裡要先剝一層再餵給假 HTTP 層。
    List<Map<String, dynamic>> trainRows() {
      final raw = jsonDecode(
        File('${dir.path}/tra-keelung.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      return [
        for (final e in raw['StationLiveBoards'] as List)
          e as Map<String, dynamic>,
      ];
    }

    /// 表定時間**一定要有值**。
    ///
    /// 欄位名是 `ScheduleDepartureTime` 不是 `ScheduledDepartureTime`
    /// —— 少一個 d，整欄變空白，而畫面上那是列車那一列的主角。
    test('台鐵：表定時間解析得出來，不是一片空白', () async {
      final repo = _repoReturning(trainRows(), stationId: '0900');
      final board = await repo.board(_trainStop);

      expect(board.trains, hasLength(3));
      for (final t in board.trains) {
        expect(t.scheduledTime, isNotEmpty, reason: '車次 ${t.trainNo} 沒有時間');
        expect(t.scheduledTime, matches(r'^\d{2}:\d{2}$'));
      }
      expect(board.trains.map((t) => t.scheduledTime),
          containsAll(['23:18', '22:23', '22:08']));
    }, skip: skip);

    test('台鐵：誤點分鐘數讀得到', () async {
      final repo = _repoReturning(trainRows(), stationId: '0900');
      final board = await repo.board(_trainStop);
      expect(board.trains.map((t) => t.delayMinutes), containsAll([0, 7, 5]));
    }, skip: skip);

    /// 基隆是端點站，這三班車的 `EndingStationID` 全都是 `0900`（基隆自己）。
    /// 照著印會變成站在基隆站看到「往 基隆」—— 那句話沒有告訴使用者任何事。
    test('台鐵：終點就是本站的時候不說「往 基隆」', () async {
      final repo = _repoReturning(trainRows(), stationId: '0900');
      final board = await repo.board(_trainStop);

      for (final t in board.trains) {
        expect(t.destination, '本站為終點');
        expect(t.destination, isNot('基隆'));
      }
    }, skip: skip);

    test('台鐵：終點是別站的時候照常顯示站名', () async {
      final repo = _repoReturning([
        {
          'TrainNo': '1234',
          'EndingStationID': '1040',
          'EndingStationName': {'Zh_tw': '樹林'},
          'ScheduleDepartureTime': '07:32:00',
        },
      ], stationId: '0900');
      final board = await repo.board(_trainStop);
      expect(board.trains.single.destination, '樹林');
    });

    /// **使用者實際回報的問題：「一站海大體育館出現了好多 103」。**
    ///
    /// TDX 是按子路線拆的：103 是環狀線，有 KEE035501 和 KEE035601 兩條，
    /// 兩條都經過海大體育館 —— 而「海大體育館」這個站名又對到馬路兩邊
    /// 兩個實體站牌（KEE306429、KEE306430）。2 × 2 = 同一條路線四筆。
    test('同一條路線不會在同一個站牌上重複出現', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      final seen = <String>{};
      for (final b in board.buses) {
        // 同一條路線最多出現兩次（馬路兩邊各一次），但不會四次。
        seen.add(b.routeName);
      }
      expect(seen, {'103', '104', '108', '8021'});
      final counts = <String, int>{};
      for (final b in board.buses) {
        counts[b.routeName] = (counts[b.routeName] ?? 0) + 1;
      }
      expect(counts.values, everyElement(lessThanOrEqualTo(2)));
      expect(counts['103'], 2);
    }, skip: skip);

    /// **馬路兩邊那兩個站牌不能併掉。**
    ///
    /// KEE306429 的下一站是海大濱海校門（往市區），KEE306430 的下一站是
    /// 北寧路（往八斗子）—— 那是真的不同方向的兩班車。併成一筆就等於
    /// 叫使用者站錯邊，而畫面上完全看不出來。
    test('去重的鍵含站牌，不會把馬路兩邊併成一筆', () async {
      final repo = _repoReturning([
        {
          'RouteName': '103',
          'StopUID': 'KEE306429',
          'StopName': {'Zh_tw': '海大體育館'},
          'EstimateTime': 300,
        },
        {
          'RouteName': '103',
          'StopUID': 'KEE306430',
          'StopName': {'Zh_tw': '海大體育館'},
          'EstimateTime': 900,
        },
      ]);
      final board = await repo.board(_cityBusStop);

      expect(board.buses, hasLength(2));
      expect(board.buses.map((b) => b.estimateSeconds), [300, 900]);
    });

    /// 同一個站牌同一條路線有好幾筆時，留最快到的那一筆 ——
    /// 使用者問的是「下一班什麼時候」。
    test('同站牌同路線留最快到的那一筆', () async {
      final repo = _repoReturning([
        {
          'RouteName': '104',
          'StopUID': 'KEE306430',
          'StopName': {'Zh_tw': '海大體育館'},
          'SubRouteUID': '慢的',
          'EstimateTime': 900,
        },
        {
          'RouteName': '104',
          'StopUID': 'KEE306430',
          'StopName': {'Zh_tw': '海大體育館'},
          'SubRouteUID': '快的',
          'EstimateTime': 120,
        },
        {
          'RouteName': '104',
          'StopUID': 'KEE306430',
          'StopName': {'Zh_tw': '海大體育館'},
          'SubRouteUID': '沒車的',
          'StopStatus': 3,
        },
      ]);
      final board = await repo.board(_cityBusStop);

      expect(board.buses, hasLength(1));
      expect(board.buses.single.estimateSeconds, 120);
    });

    /// 三個海大站牌打的是同一個端點，只有站名不同 ——
    /// 分成三次問就是白白多打兩個請求，而那正是畫面上一直冒
    /// 「服務忙碌中」的原因（TDX 回 429）。
    test('同一個城市的市區公車合併成一個請求', () async {
      final spy = _RecordingAdapter();
      final repo = _repoWith(spy);

      await repo.boards(const [
        TransitStop(id: 'a', name: '海大體育館', kind: TransitStopKind.cityBus),
        TransitStop(id: 'b', name: '海大濱海校門', kind: TransitStopKind.cityBus),
        TransitStop(id: 'c', name: '海大祥豐校門', kind: TransitStopKind.cityBus),
      ]);

      expect(spy.dataRequests, 1);
      final filter = spy.lastDataRequest!.queryParameters[r'$filter'] as String;
      expect(filter, contains('海大體育館'));
      expect(filter, contains('海大濱海校門'));
      expect(filter, contains('海大祥豐校門'));
    });

    /// 合併回來的資料要照站名分回各自的看板，不能三張卡片都放全部。
    test('合併的回應會照站名拆回各自的看板', () async {
      final repo = _repoReturning([
        {
          'RouteName': '103',
          'StopUID': 'A',
          'StopName': {'Zh_tw': '海大體育館'},
          'EstimateTime': 60,
        },
        {
          'RouteName': '104',
          'StopUID': 'B',
          'StopName': {'Zh_tw': '海大濱海校門'},
          'EstimateTime': 120,
        },
      ]);

      final boards = await repo.boards(const [
        TransitStop(id: 'a', name: '海大體育館', kind: TransitStopKind.cityBus),
        TransitStop(id: 'b', name: '海大濱海校門', kind: TransitStopKind.cityBus),
      ]);

      expect(boards[0].buses.single.routeName, '103');
      expect(boards[1].buses.single.routeName, '104');
    });

    /// **這是使用者那個問題的完整解法。**
    ///
    /// 「海大體育館」對到馬路兩邊兩個站牌，103 在兩邊都停。去重之後還是
    /// 兩列，而且**終點站都是八斗子車站**（環狀線），所以光看終點分不出
    /// 誰往哪。分得出來的是下一站：
    ///
    ///   KEE306429 → 海大濱海校門（往市區）
    ///   KEE306430 → 北寧路(九八八餐廳)（往八斗子）
    ///
    /// 這兩個名字是拿真實的站序資料（route-103-stops.json）算出來的，
    /// 不是寫死的。
    test('馬路兩邊的 103 靠下一站分得出方向', () async {
      final dio = Dio()
        ..httpClientAdapter = _CannedAdapter(
          rows: rowsOf('ntou-gym.json'),
          stopsOfRoute: rowsOf('route-103-stops.json'),
        );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: dio,
        ),
      );
      final board = await repo.board(_cityBusStop);

      final r103 = board.buses.where((b) => b.routeName == '103').toList();
      expect(r103, hasLength(2));
      expect(
        r103.map((b) => b.nextStop).toSet(),
        {'海大濱海校門', '北寧路(九八八餐廳)'},
      );
    }, skip: skip);

    /// 站序的回應很大（103 兩條子路線就 132 個站牌），所以**只有需要分辨
    /// 方向的路線才去查**，而且查過就快取。
    test('站序只查需要分辨方向的路線，而且只查一次', () async {
      final spy = _CannedAdapter(
        rows: rowsOf('ntou-gym.json'),
        stopsOfRoute: rowsOf('route-103-stops.json'),
      );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);

      // 四條路線都需要分辨方向，但它們是**一個請求**問完的，而且只問一次。
      expect(spy.stopsOfRouteCalls, 1);
    }, skip: skip);

    /// 站序抓不到就只是少了方向標記 —— 到站時間還在。
    /// 而且**不能每次重整都再問一遍**，一次 429 會變成每半分鐘再撞一次。
    test('站序抓不到時，到站時間照常，而且不會一直重問', () async {
      final spy = _CannedAdapter(
        rows: rowsOf('ntou-gym.json'),
        stopsOfRoute: const [],
      );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      final board = await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);

      expect(board.error, isNull);
      expect(board.buses.where((b) => b.isRunning).single.estimateSeconds, 725);
      expect(board.buses.every((b) => b.nextStop.isEmpty), isTrue);
      expect(spy.stopsOfRouteCalls, 1);
    }, skip: skip);

    /// 查不到路線資料時終點留白，**絕不把 StopID 當站名顯示**。
    ///
    /// 到站資料裡只有 `DestinationStop`，而它是 StopID（`"306195"`）。
    /// 畫面上冒出「往 306195」比空白難看得多，而且那串數字對使用者
    /// 沒有任何意義。
    test('查不到路線時終點留白，不是把 StopID 當站名', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      for (final b in board.buses) {
        expect(b.destination, isEmpty);
        expect(b.destination, isNot(matches(r'^\d+$')));
      }
    }, skip: skip);

    /// 真實資料 + 真實路線：103（KEE0355）Direction 0 應該是往八斗子車站。
    ///
    /// 起訖站的名字是 2026-09-04 從 TDX 的路線資料查來的。
    test('海大體育館：103 補得出「往 八斗子車站」', () async {
      final repo = _repoReturning(
        rowsOf('ntou-gym.json'),
        routes: const [
          {
            'RouteUID': 'KEE0355',
            'DepartureStopNameZh': '八斗子分站',
            'DestinationStopNameZh': '八斗子車站',
          },
        ],
      );
      final board = await repo.board(_cityBusStop);

      final route103 = board.buses.where((b) => b.routeName == '103');
      expect(route103, isNotEmpty);
      expect(route103.first.destination, '八斗子車站');
    }, skip: skip);
  });

  group('往哪裡（Direction 對到路線的哪一頭）', () {
    /// **這一組守的是一個會讓人搭反方向的錯。**
    ///
    /// 到站資料沒有終點站名，只有 `DestinationStop`（StopID）。站名是拿
    /// `RouteUID` 去路線資料查兩頭，再靠 `Direction` 挑一邊補上的。
    /// 挑反了畫面上不會有任何異狀 —— 是一個看起來完全合理的站名，
    /// 只是方向相反。
    ///
    /// 對應關係對過真實資料：基隆市公車七筆 Direction 0 全部對上終點欄位；
    /// 國道客運那邊基隆轉運站在「基隆是終點」的路線出現在 Direction 0、
    /// 在「基隆是起點」的路線出現在 Direction 1，八條路線一致。
    const routes = [
      {
        'RouteUID': 'KEE0355',
        'DepartureStopNameZh': '基隆火車站',
        'DestinationStopNameZh': '八斗子車站',
      },
    ];

    Future<BusArrival> busWith(int? direction) async {
      final repo = _repoReturning([
        {
          'RouteName': '103',
          'RouteUID': 'KEE0355',
          'StopName': {'Zh_tw': '海大體育館'},
          'EstimateTime': 300,
          'Direction': ?direction,
        },
      ], routes: routes);
      return (await repo.board(_cityBusStop)).buses.single;
    }

    test('Direction 0 是去程，往終點欄位', () async {
      expect((await busWith(0)).destination, '八斗子車站');
    });

    test('Direction 1 是返程，往起點欄位', () async {
      expect((await busWith(1)).destination, '基隆火車站');
    });

    /// 認不得的值寧可留白。**猜一邊就是二選一猜方向**，猜錯的畫面
    /// 跟猜對的長得一模一樣。
    test('認不得的 Direction 留白，不要二選一猜一個', () async {
      expect((await busWith(9)).destination, isEmpty);
      expect((await busWith(null)).destination, isEmpty);
    });

    test('終點就是本站的時候不說「往 海大體育館」', () async {
      final repo = _repoReturning([
        {
          'RouteName': '103',
          'RouteUID': 'KEE0355',
          'StopName': {'Zh_tw': '八斗子車站'},
          'Direction': 0,
          'EstimateTime': 60,
        },
      ], routes: routes);
      final board = await repo.board(_cityBusStop);
      expect(board.buses.single.destination, '本站為終點');
    });

    /// 路線的起訖站不會在一天之內改變，而這一頁每 30 秒重整一次 ——
    /// 每次都重問一輪就是拿 429 換一份不會變的資料。
    test('路線只查一次，之後都吃快取', () async {
      final spy = _CannedAdapter(
        rows: const [
          {'RouteName': '103', 'RouteUID': 'KEE0355', 'Direction': 0},
        ],
        routes: routes,
      );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);

      expect(spy.routeCalls, 1);
    });

    /// 查不到的路線也要記起來，否則它每 30 秒就會被重問一次。
    test('查不到的路線不會每次重整都再問一遍', () async {
      final spy = _CannedAdapter(
        rows: const [
          {'RouteName': '999', 'RouteUID': 'KEE9999', 'Direction': 0},
        ],
        routes: const [],
      );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);

      expect(spy.routeCalls, 1);
      expect((await repo.board(_cityBusStop)).buses.single.destination, isEmpty);
    });

    /// 路線查不到不該把到站時間一起弄不見 —— 那才是使用者真正要看的東西。
    test('路線查詢失敗，到站時間照樣顯示', () async {
      final repo = _repoReturning([
        {'RouteName': '103', 'RouteUID': 'KEE0355', 'EstimateTime': 300},
      ]);
      final board = await repo.board(_cityBusStop);

      expect(board.error, isNull);
      expect(board.buses.single.estimateSeconds, 300);
      expect(board.buses.single.destination, isEmpty);
    });
  });

  group('點進一條路線：站序與車在哪', () {
    /// 站序照抄 103 的真實形狀（`spike/tdx.py --probe-route-detail 103`）：
    /// 巢狀的 StopName、StopSequence 從 1 開始、Stops 包在每一筆裡面。
    Map<String, dynamic> variant(
      String uid,
      List<String> names, {
      int direction = 0,
      String name = '103',
    }) =>
        {
          'RouteName': {'Zh_tw': '103'},
          'SubRouteUID': uid,
          'SubRouteName': {'Zh_tw': name},
          'Direction': direction,
          'Stops': [
            for (var i = 0; i < names.length; i++)
              {
                'StopUID': '$uid-$i',
                'StopName': {'Zh_tw': names[i]},
                'StopSequence': i + 1,
              },
          ],
        };

    TransitRepository repoWith({
      required List<Map<String, dynamic>> variants,
      List<Map<String, dynamic>> buses = const [],
    }) {
      final dio = Dio()
        ..httpClientAdapter = _CannedAdapter(
          rows: const [],
          stopsOfRoute: variants,
          realtime: buses,
        );
      return TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: dio,
        ),
      );
    }

    test('站序解得出來，而且照 StopSequence 排好', () async {
      final repo = repoWith(variants: [
        variant('KEE035501', ['八斗子分站', '基隆漁會', '海大體育館']),
      ]);
      final detail =
          await repo.routeDetail('103', city: 'Keelung', intercity: false);

      expect(detail.error, isNull);
      expect(detail.variants, hasLength(1));
      expect(
        detail.variants.single.stops.map((s) => s.name),
        ['八斗子分站', '基隆漁會', '海大體育館'],
      );
      expect(detail.variants.single.destination, '海大體育館');
    });

    /// TDX 回來的順序通常是對的，但站序是這一頁的骨架 ——
    /// 順序錯掉的話畫面會變成一條走不通的路線，而且看起來很像真的。
    test('回來的順序亂掉也要排回正確站序', () async {
      final repo = repoWith(variants: [
        {
          'SubRouteUID': 'A',
          'SubRouteName': {'Zh_tw': '103'},
          'Direction': 0,
          'Stops': [
            {
              'StopUID': 'c',
              'StopName': {'Zh_tw': '第三站'},
              'StopSequence': 3,
            },
            {
              'StopUID': 'a',
              'StopName': {'Zh_tw': '第一站'},
              'StopSequence': 1,
            },
            {
              'StopUID': 'b',
              'StopName': {'Zh_tw': '第二站'},
              'StopSequence': 2,
            },
          ],
        },
      ]);
      final detail =
          await repo.routeDetail('103', city: 'Keelung', intercity: false);

      expect(
        detail.variants.single.stops.map((s) => s.name),
        ['第一站', '第二站', '第三站'],
      );
    });

    /// **這是整組裡最重要的一個測試。**
    ///
    /// 103 是環狀線：`--probe-route-detail 103` 查出來兩條站序（68 站和
    /// 64 站），而**兩條的 Direction 都是 0**。只用方向配對即時位置的話，
    /// 車會被畫到錯的那一條上 —— 畫面上是一台在合理位置的公車，只是它
    /// 其實跑在另一條路線上。沒有錯誤訊息，看不出來。
    ///
    /// 分得出來的是 SubRouteUID。
    test('環狀線兩條子路線同方向，車要靠 SubRouteUID 配到對的那條', () async {
      final repo = repoWith(
        variants: [
          variant('KEE035501', ['甲一', '甲二', '甲三']),
          variant('KEE035502', ['乙一', '乙二', '乙三']),
        ],
        buses: [
          {
            'PlateNumb': '往甲的車',
            'SubRouteUID': 'KEE035501',
            'Direction': 0,
            'StopSequence': 2,
            'StopName': {'Zh_tw': '甲二'},
            'A2EventType': 1,
          },
          {
            'PlateNumb': '往乙的車',
            'SubRouteUID': 'KEE035502',
            'Direction': 0,
            'StopSequence': 3,
            'StopName': {'Zh_tw': '乙三'},
            'A2EventType': 0,
          },
        ],
      );
      final detail =
          await repo.routeDetail('103', city: 'Keelung', intercity: false);

      expect(detail.variants[0].buses.single.plate, '往甲的車');
      expect(detail.variants[0].buses.single.stopSequence, 2);
      expect(detail.variants[1].buses.single.plate, '往乙的車');
      expect(detail.variants[1].buses.single.stopSequence, 3);
    });

    /// A2EventType：0 進站、1 離站。離站的車正往下一站移動，
    /// 講「在這一站」會讓使用者以為還追得上。
    test('離站和進站要分得出來', () async {
      final repo = repoWith(
        variants: [
          variant('A', ['一', '二'])
        ],
        buses: [
          {
            'PlateNumb': '離站的',
            'SubRouteUID': 'A',
            'StopSequence': 1,
            'A2EventType': 1,
          },
          {
            'PlateNumb': '在站上的',
            'SubRouteUID': 'A',
            'StopSequence': 2,
            'A2EventType': 0,
          },
        ],
      );
      final detail =
          await repo.routeDetail('103', city: 'Keelung', intercity: false);

      final buses = {
        for (final b in detail.variants.single.buses) b.plate: b.leaving,
      };
      expect(buses, {'離站的': true, '在站上的': false});
    });

    /// 深夜本來就沒車。站序還是要看得到 —— 那是這一頁的骨架。
    test('現在沒有車在跑，站序照樣顯示', () async {
      final repo = repoWith(variants: [
        variant('A', ['一', '二'])
      ]);
      final detail =
          await repo.routeDetail('103', city: 'Keelung', intercity: false);

      expect(detail.error, isNull);
      expect(detail.variants.single.stops, hasLength(2));
      expect(detail.variants.single.buses, isEmpty);
    });

    test('查不到站序時給一句話，不是丟例外', () async {
      final repo = repoWith(variants: const []);
      final detail =
          await repo.routeDetail('不存在', city: 'Keelung', intercity: false);

      expect(detail.error, isNotNull);
      expect(detail.isEmpty, isTrue);
    });

    /// 站序一天之內不會變，重整只該重抓車的位置。
    test('站序查一次就快取，重整不會再問一遍', () async {
      final spy = _CannedAdapter(
        rows: const [],
        stopsOfRoute: [
          variant('A', ['一', '二'])
        ],
      );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      await repo.routeDetail('103', city: 'Keelung', intercity: false);
      await repo.routeDetail('103', city: 'Keelung', intercity: false);
      await repo.routeDetail('103', city: 'Keelung', intercity: false);

      expect(spy.stopsOfRouteCalls, 1);
      // 車的位置每次都要重抓 —— 那就是「現在開到哪」本身。
      expect(spy.realtimeCalls, 3);
    });
  });

  group('對著真實的 103 解析路線詳情', () {
    /// 這一組吃的是真的從 TDX 抓下來的 103（`spike/tdx.py
    /// --probe-route-detail 103 --save`，2026-09-04 深夜）。
    ///
    /// **103 是這個功能最難的案例**，所以它值得單獨一組：兩條子路線同名、
    /// 同方向、連終點站都一樣。任何一個環節偷懶（用方向配對、用子路線名
    /// 當分頁標題）在這條路線上都會安靜地做錯。
    final dir = Directory('../spike/fixtures/tdx');
    final skip = File('${dir.path}/route-103-stops.json').existsSync()
        ? null
        : '沒有 103 的 fixture（跑 spike/tdx.py --probe-route-detail 103 --save）';

    List<Map<String, dynamic>> rowsOf(String name) => [
          for (final e
              in jsonDecode(File('${dir.path}/$name').readAsStringSync())
                  as List)
            e as Map<String, dynamic>,
        ];

    Future<RouteDetail> detail() {
      final dio = Dio()
        ..httpClientAdapter = _CannedAdapter(
          rows: const [],
          stopsOfRoute: rowsOf('route-103-stops.json'),
          realtime: rowsOf('route-103-realtime.json'),
        );
      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: dio,
        ),
      );
      return repo.routeDetail('103', city: 'Keelung', intercity: false);
    }

    test('兩條子路線：68 站和 64 站，而且方向都是 0', () async {
      final d = await detail();

      expect(d.variants, hasLength(2));
      expect(d.variants.map((v) => v.stops.length), [68, 64]);
      // **兩條都是 Direction 0。** 這就是不能用方向配對的原因。
      expect(d.variants.map((v) => v.direction), [0, 0]);
      expect(d.variants.map((v) => v.subRouteUid), ['KEE035501', 'KEE035601']);
    }, skip: skip);

    test('站序是真的一路排到底，中間沒有斷號', () async {
      final d = await detail();

      for (final v in d.variants) {
        final seqs = v.stops.map((s) => s.sequence).toList();
        expect(seqs.first, 1);
        expect(seqs.last, v.stops.length);
        expect(seqs, List.generate(v.stops.length, (i) => i + 1));
      }
      // 海大那三個站牌真的在 103 的路線上（去程 16、17、18 站）。
      final outbound = d.variants.first.stops.map((s) => s.name).toList();
      expect(outbound[15], '海大體育館');
      expect(outbound[16], '海大濱海校門');
      expect(outbound[17], '海大祥豐校門');
    }, skip: skip);

    /// 四台車照 SubRouteUID 分成 2 + 2。
    ///
    /// **只用方向配對的話這四台會全部塞進第一條**，而畫面上完全看不出異狀 ——
    /// 第 64 站在 68 站那條路線上也是個合理的位置。
    test('四台車照子路線分開，不是全部塞進第一條', () async {
      final d = await detail();

      expect(d.variants[0].buses.map((b) => b.plate), ['620-FZ', 'FAC-157']);
      expect(d.variants[1].buses.map((b) => b.plate), ['KKA-1761', 'KKA-1767']);
    }, skip: skip);

    /// 每台車都停在自己那條子路線的**最後一站**（八斗子車站），而且都是離站。
    ///
    /// 這是深夜跑完收班停在場站的樣子。我們不去猜「這台車還在不在營運」——
    /// 沒有可靠的欄位可以分辨，猜錯會把停著的車講成正在來的車。
    /// 就照實顯示它在哪，跟 Bus+ 一樣。
    test('深夜的車都停在各自路線的最後一站', () async {
      final d = await detail();

      for (final v in d.variants) {
        for (final b in v.buses) {
          expect(b.stopSequence, v.stops.length);
          expect(b.stopName, '八斗子車站');
          expect(b.leaving, isTrue);
        }
      }
    }, skip: skip);

    /// **這個測試是分頁標題那三層 fallback 的存在理由。**
    ///
    /// 103 的兩條子路線 SubRouteName 都是「103」，終點站都是「八斗子車站」——
    /// 前兩層都分不開，只有補上站數才行。分不開的分頁比沒有分頁更糟：
    /// 使用者切過去看到兩個一樣的標題，會以為自己點錯了。
    test('兩個分頁的標題一定要分得開', () async {
      final d = await detail();

      expect(d.variants.map((v) => v.subRouteName).toSet(), hasLength(1));
      expect(d.variants.map((v) => v.destination).toSet(), hasLength(1));

      final labels = RoutePage.labelsFor(d.variants);
      expect(labels.toSet(), hasLength(2), reason: '兩個分頁標題一樣，使用者分不出來');
      expect(labels, ['往 八斗子車站（68 站）', '往 八斗子車站（64 站）']);
    }, skip: skip);
  });

  group('節流：併發也要排隊', () {
    /// **這一組守的是一個已經在真機上爆過的 bug。**
    ///
    /// 交通頁一開就用 `Future.wait` 同時抓五個站。原本的節流是「每個請求
    /// 各自去看上一次是什麼時候」—— 五個呼叫讀到同一個舊時間、對同一個值
    /// 算間隔、同時通過檢查，然後同時把時間寫回去。看起來有節流，實際上
    /// 五個請求一起打出去，TDX 回 429，畫面上五張卡片全變「服務忙碌中」。
    ///
    /// 所以節流必須是**佇列**，不是各自檢查。
    test('同時丟四個請求，它們會排成一列依序送出', () async {
      final sent = <DateTime>[];
      final dio = Dio()..httpClientAdapter = _TimingAdapter(sent);
      final client = TdxClient(
        config: _throttled,
        clientId: 'id',
        clientSecret: 'secret',
        dio: dio,
      );

      await Future.wait([
        for (var i = 0; i < 4; i++)
          client.get(_throttled.endpoint('city_bus_arrivals', city: 'Keelung')),
      ]);

      expect(sent, hasLength(4));
      for (var i = 1; i < sent.length; i++) {
        final gap = sent[i].difference(sent[i - 1]);
        // 設定的間隔是 40ms。時鐘精度和排程抖動留一點餘裕，
        // 但**絕不能是 0** —— 0 就代表又變回同時打出去了。
        expect(
          gap.inMilliseconds,
          greaterThanOrEqualTo(25),
          reason: '第 $i 個請求只隔了 ${gap.inMilliseconds}ms，沒有排隊',
        );
      }
    });

    /// 一個請求失敗不該讓後面的永遠卡住。
    ///
    /// 佇列是一條 future 鏈，前面那一環如果帶著錯誤，後面接上去的都會
    /// 跟著爆 —— 一次 429 就會讓這個 client 之後再也送不出任何請求，
    /// 而畫面上只會看到「重新整理沒反應」。
    test('前一個請求爆掉，後面的照樣送得出去', () async {
      final sent = <DateTime>[];
      final dio = Dio()..httpClientAdapter = _TimingAdapter(sent, failFirst: true);
      final client = TdxClient(
        config: _throttled,
        clientId: 'id',
        clientSecret: 'secret',
        dio: dio,
      );
      final path = _throttled.endpoint('city_bus_arrivals', city: 'Keelung');

      await expectLater(client.get(path), throwsA(isA<TransitUnavailable>()));
      // 第二次要正常回來，不是卡死也不是繼承前一次的錯誤。
      expect(await client.get(path), isEmpty);
    });
  });

  group('走中繼服務', () {
    /// 公開發布的版本走中繼：金鑰只在中繼那一端，App 裡沒有也不該有。
    ///
    /// 中繼會快取 —— 那五個站的資料對所有使用者都是同一份，所以打到 TDX 的
    /// 請求量跟使用者數量無關。這是它存在的理由，不是順便的最佳化。
    final relay = TransitConfig.fromJson({
      'auth': {'token_url': 'https://example.invalid/token'},
      'api': {
        'base_url': 'https://tdx.transportdata.tw/api/basic/',
        'relay_base_url': 'https://relay.example.invalid/',
        'min_interval_seconds': 0,
        'timeout_seconds': 0,
        'city_bus_arrivals': 'v2/Bus/EstimatedTimeOfArrival/City/{city}',
        'city_bus_filter': "StopName/Zh_tw eq '{name}'",
      },
      'stops': const [],
    });

    TdxClient clientWith(HttpClientAdapter adapter, {TransitConfig? config}) =>
        TdxClient(
          config: config ?? relay,
          // **故意不給金鑰。** 這就是公開版本的樣子。
          clientId: '',
          clientSecret: '',
          dio: Dio()..httpClientAdapter = adapter,
        );

    test('設定了中繼就算「已開通」，不需要金鑰', () {
      expect(clientWith(_RecordingAdapter()).isConfigured, isTrue);
      // 沒有中繼又沒有金鑰才是真的沒開通。
      expect(clientWith(_RecordingAdapter(), config: _config).isConfigured,
          isFalse);
    });

    test('請求打到中繼，不是直接打 TDX', () async {
      final spy = _RecordingAdapter();
      await clientWith(spy).get(
        relay.endpoint('city_bus_arrivals', city: 'Keelung'),
      );

      final uri = spy.lastDataRequest!.uri;
      expect(uri.host, 'relay.example.invalid');
      expect(uri.path, contains('v2/Bus/EstimatedTimeOfArrival/City/Keelung'));
    });

    /// **走中繼時完全不碰 token 端點。** App 裡沒有金鑰，換不到也不該換 ——
    /// 真的去打的話只會拿到 400，而畫面上會變成「金鑰被拒絕」，
    /// 把一個設定正確的 App 講成壞掉的。
    test('不去換 token，也不帶 authorization', () async {
      final spy = _RecordingAdapter();
      await clientWith(spy).get(
        relay.endpoint('city_bus_arrivals', city: 'Keelung'),
      );

      expect(spy.tokenRequests, 0);
      expect(spy.lastDataRequest!.headers.containsKey('authorization'), isFalse);
    });

    test('OData 參數照樣送出去，中繼是透明的', () async {
      final spy = _RecordingAdapter();
      await clientWith(spy).get(
        relay.endpoint('city_bus_arrivals', city: 'Keelung'),
        query: {r'$filter': "StopName/Zh_tw eq '海大體育館'", r'$top': '80'},
      );

      final q = spy.lastDataRequest!.queryParameters;
      expect(q[r'$filter'], contains('海大體育館'));
      expect(q[r'$top'], '80');
      expect(q[r'$format'], 'JSON');
    });

    /// 設定檔是人寫的，少一條斜線的話網址會黏成
    /// `https://relay.example.invalidv2/Bus/...` —— 畫面上是
    /// 「連不上交通資料服務」，完全看不出是少了一個字元。
    test('中繼網址少了結尾斜線也接得對', () {
      final c = TransitConfig.fromJson({
        'api': {'relay_base_url': 'https://relay.example.invalid'},
      });
      expect(c.relayBaseUrl, 'https://relay.example.invalid/');
      expect(c.usesRelay, isTrue);
    });

    test('沒填中繼就是直接打 TDX，行為跟以前一樣', () {
      expect(_config.usesRelay, isFalse);
      expect(_config.relayBaseUrl, isEmpty);
    });

    /// 中繼回 503 代表那一端忘了設金鑰。這不是使用者能處理的事，
    /// 但重新整理是對的第一步，而且訊息裡不能出現任何內部細節。
    test('中繼沒設金鑰時給的話裡沒有網址也沒有內部訊息', () async {
      final spy = _RecordingAdapter(status: 503);
      Object? caught;
      try {
        await clientWith(spy)
            .get(relay.endpoint('city_bus_arrivals', city: 'Keelung'));
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<TransitUnavailable>());
      expect(caught.toString(), isNot(contains('relay.example.invalid')));
    });
  });

  group('一個站問兩個來源', () {
    /// **使用者回報 1579 沒出現在海大體育館。**
    ///
    /// 那不是 bug 是設定：1579 是首都客運的國道客運，資料在
    /// `EstimatedTimeOfArrival/InterCity`，而海大體育館原本只被設定成
    /// 「基隆市公車」—— 只問前者的話 1579 永遠查不到，而畫面上看起來
    /// 只是「這站沒有這條路線」，看不出是設定漏了。
    const gym = TransitStop(
      id: 'ntou-gym',
      name: '海大體育館',
      kind: TransitStopKind.cityBus,
      extraKinds: [TransitStopKind.interCityBus],
    );

    TransitRepository repoWith(_CannedAdapter adapter) => TransitRepository(
          config: _config,
          client: TdxClient(
            config: _config,
            clientId: 'id',
            clientSecret: 'secret',
            dio: Dio()..httpClientAdapter = adapter,
          ),
        );

    test('市區公車和國道客運的車會合在同一張看板上', () async {
      final spy = _CannedAdapter(
        rows: const [
          {
            'RouteName': '103',
            'StopUID': 'A',
            'StopName': {'Zh_tw': '海大體育館'},
            'EstimateTime': 600,
          },
        ],
      )..intercityRows = const [
          {
            'RouteName': '1579',
            'StopUID': 'B',
            'StopName': {'Zh_tw': '海大體育館'},
            'EstimateTime': 120,
          },
        ];

      final boards = await repoWith(spy).boards(const [gym]);

      expect(boards.single.buses.map((b) => b.routeName), ['1579', '103']);
      // 兩個來源各一個請求，而且都真的打了。
      expect(spy.intercityCalls, 1);
    });

    test('只有一個來源有車也照樣顯示，不會變成錯誤卡片', () async {
      final spy = _CannedAdapter(rows: const [])
        ..intercityRows = const [
          {
            'RouteName': '1579',
            'StopUID': 'B',
            'StopName': {'Zh_tw': '海大體育館'},
            'EstimateTime': 120,
          },
        ];

      final boards = await repoWith(spy).boards(const [gym]);

      expect(boards.single.error, isNull);
      expect(boards.single.buses.single.routeName, '1579');
    });

    /// 三個海大站牌的國道客運查詢會跟基隆轉運站那次合併 ——
    /// **多問一種來源不該多打請求**，那是這個設計成立的前提。
    test('多個站的國道客運查詢合併成一個請求', () async {
      final spy = _CannedAdapter(rows: const []);
      await repoWith(spy).boards(const [
        gym,
        TransitStop(
          id: 'b',
          name: '海大濱海校門',
          kind: TransitStopKind.cityBus,
          extraKinds: [TransitStopKind.interCityBus],
        ),
        TransitStop(
          id: 'c',
          name: '基隆轉運站',
          kind: TransitStopKind.interCityBus,
        ),
      ]);

      // 市區公車一個、國道客運一個，總共兩個 —— 不是三個站各一個。
      expect(spy.intercityCalls, 1);
      expect(spy.dataCalls, 2);
    });
  });

  group('補充資料失敗要退避', () {
    /// **這是把一次 429 拖成永久 429 的那個洞。**
    ///
    /// 「往哪裡」和方向標記都是額外查來的。原本失敗就直接放棄、不留記錄，
    /// 所以下一次重整又整輪重問 —— 每 30 秒、每個公車站各一次。TDX 一旦
    /// 開始擋，重試本身就把請求量撐在高點，讓它停不下來，畫面上五張卡片
    /// 就一直是「服務忙碌中」。
    ///
    /// 這兩份資料純粹是錦上添花，到站時間不靠它們，所以失敗就退開幾分鐘。
    test('路線查詢失敗之後不會每次重整都再撞一次', () async {
      final spy = _CannedAdapter(
        rows: const [
          {
            'RouteName': '103',
            'RouteUID': 'KEE0355',
            'StopUID': 'A',
            'StopName': {'Zh_tw': '海大體育館'},
            'EstimateTime': 600,
          },
        ],
      )..routeStatus = 429;

      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);
      await repo.board(_cityBusStop);

      expect(spy.routeCalls, 1, reason: '失敗之後還在重問，429 會停不下來');
    });

    /// 到站時間才是使用者要看的東西 —— 補充資料掛掉不能連累它。
    test('補充資料失敗時，到站時間照常顯示', () async {
      final spy = _CannedAdapter(
        rows: const [
          {
            'RouteName': '103',
            'RouteUID': 'KEE0355',
            'StopUID': 'A',
            'StopName': {'Zh_tw': '海大體育館'},
            'EstimateTime': 600,
          },
        ],
      )..routeStatus = 429;

      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );
      final board = await repo.board(_cityBusStop);

      expect(board.error, isNull);
      expect(board.buses.single.estimateSeconds, 600);
      expect(board.buses.single.destination, isEmpty);
    });

    /// 使用者自己下拉重整是明確在說「現在再試一次」，那就該解除退避。
    test('手動重整會解除退避', () async {
      final spy = _CannedAdapter(
        rows: const [
          {
            'RouteName': '103',
            'RouteUID': 'KEE0355',
            'StopUID': 'A',
            'StopName': {'Zh_tw': '海大體育館'},
            'EstimateTime': 600,
          },
        ],
      )..routeStatus = 429;

      final repo = TransitRepository(
        config: _config,
        client: TdxClient(
          config: _config,
          clientId: 'id',
          clientSecret: 'secret',
          dio: Dio()..httpClientAdapter = spy,
        ),
      );

      await repo.board(_cityBusStop);
      repo.retryExtrasNow();
      await repo.board(_cityBusStop);

      expect(spy.routeCalls, 2);
    });
  });

  group('金鑰不外洩', () {
    test('沒設定金鑰時是 TdxNotConfigured，畫面才分得出要顯示引導', () async {
      final client = TdxClient(
        config: _config,
        clientId: '',
        clientSecret: '',
        dio: Dio(),
      );
      expect(client.isConfigured, isFalse);
      expect(
        () => client.get('whatever'),
        throwsA(isA<TdxNotConfigured>()),
      );
    });

    /// CLAUDE.md 的紅線：不要把 `e.toString()` 丟給使用者。
    /// dio 的訊息裡有完整 URL，而換 token 那個請求的 body 就是 secret 本人。
    test('連線失敗的訊息裡沒有 secret，也沒有網址', () async {
      const secret = 'super-secret-value';
      final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
      final client = TdxClient(
        config: _config,
        clientId: 'id',
        clientSecret: secret,
        dio: dio,
      );

      Object? caught;
      try {
        await client.get(_config.endpoint('city_bus_arrivals', city: 'Keelung'));
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<TransitUnavailable>());
      final text = caught.toString();
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('tdx.transportdata.tw')));
      expect(text, isNot(contains('client_secret')));
    });
  });
}

// --------------------------------------------------------------- 測試用具

/// 測試用的設定。
///
/// `timeout` 和 `min_interval` 都是 0 —— 兩者都會排計時器，而測試會以
/// 「Pending timers」失敗，訊息完全看不出跟這裡有關。
final TransitConfig _config = TransitConfig.fromJson({
  'auth': {'token_url': 'https://example.invalid/token'},
  'api': {
    'base_url': 'https://example.invalid/api/',
    'min_interval_seconds': 0,
    'timeout_seconds': 0,
    'city_bus_arrivals': 'v2/Bus/EstimatedTimeOfArrival/City/{city}',
    'intercity_arrivals': 'v2/Bus/EstimatedTimeOfArrival/InterCity',
    'city_bus_routes': 'v2/Bus/Route/City/{city}',
    'intercity_routes': 'v2/Bus/Route/InterCity',
    'city_bus_stops_of_route': 'v2/Bus/StopOfRoute/City/{city}',
    'city_bus_realtime': 'v2/Bus/RealTimeNearStop/City/{city}',
    'train_liveboard': 'v3/Rail/TRA/StationLiveBoard',
    'train_stations': 'v3/Rail/TRA/Station',
    'city_bus_filter': "StopName/Zh_tw eq '{name}'",
    'intercity_filter': "StopName/Zh_tw eq '{name}'",
    'train_liveboard_filter': "StationID eq '{station}'",
    'train_station_filter': "StationName/Zh_tw eq '{name}'",
    'route_filter': "RouteUID eq '{name}'",
    'route_name_filter': "RouteName/Zh_tw eq '{name}'",
  },
  'stop_status': {'0': '正常', '1': '尚未發車'},
  'stops': const [],
});

const _cityBusStop = TransitStop(
  id: 'ntou-gym',
  name: '海大體育館',
  kind: TransitStopKind.cityBus,
);

const _trainStop = TransitStop(
  id: 'tra-keelung',
  name: '台鐵基隆站',
  kind: TransitStopKind.train,
  stationName: '基隆',
);

/// 一個永遠回同一批資料的 repository。
///
/// [stationId] 有值時，車站清單那次查詢會回這個代碼 —— 火車的測試要先
/// 走過「用站名查代碼」那一步。
TransitRepository _repoReturning(
  List<Map<String, dynamic>> rows, {
  String? stationId,
  List<Map<String, dynamic>> routes = const [],
}) {
  final dio = Dio()
    ..httpClientAdapter =
        _CannedAdapter(rows: rows, stationId: stationId, routes: routes);
  return TransitRepository(
    config: _config,
    client: TdxClient(
      config: _config,
      clientId: 'id',
      clientSecret: 'secret',
      dio: dio,
    ),
  );
}

TransitRepository _repoFailing() {
  final dio = Dio()..httpClientAdapter = _ThrowingAdapter();
  return TransitRepository(
    config: _config,
    client: TdxClient(
      config: _config,
      clientId: 'id',
      clientSecret: 'secret',
      dio: dio,
    ),
  );
}

/// 立刻回應的假 HTTP 層：token 一律發得出來，資料端點回預先準備好的東西。
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter({
    required this.rows,
    this.stationId,
    this.routes = const [],
    this.stopsOfRoute = const [],
    this.realtime = const [],
  });

  final List<Map<String, dynamic>> rows;
  final String? stationId;

  /// 路線站序（`StopOfRoute`）與公車即時位置（`RealTimeNearStop`）。
  final List<Map<String, dynamic>> stopsOfRoute;
  final List<Map<String, dynamic>> realtime;

  /// 國道客運的到站資料。
  ///
  /// **沒設定的話退回用 [rows]** —— 大部分測試只關心「到站端點回什麼」，
  /// 不在乎是市區還是國道。要驗「一個站同時問兩個來源、兩邊的車有沒有
  /// 合起來」的時候才需要把兩邊分開。
  List<Map<String, dynamic>>? intercityRows;

  /// 路線端點要回的狀態碼。用 429 來驗退避。
  int routeStatus = 200;

  int intercityCalls = 0;

  /// 這兩個端點各被打了幾次。站序有快取、車的位置沒有，看這個分辨。
  int stopsOfRouteCalls = 0;
  int realtimeCalls = 0;

  /// 資料端點總共被打了幾次（token 不算）。合併有沒有生效看這個。
  int dataCalls = 0;

  /// 路線資料（起訖站）。「往哪裡」是從這裡補上的。
  final List<Map<String, dynamic>> routes;

  /// 路線端點被打了幾次。快取有沒有生效看這個。
  int routeCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String body;
    if (!options.path.contains('token')) dataCalls++;
    if (options.path.contains('token')) {
      body = jsonEncode({
        'access_token': 'fake-token',
        'expires_in': 86400,
        'token_type': 'Bearer',
      });
    } else if (options.path.contains('StopOfRoute')) {
      stopsOfRouteCalls++;
      body = jsonEncode(stopsOfRoute);
    } else if (options.path.contains('RealTimeNearStop')) {
      realtimeCalls++;
      body = jsonEncode(realtime);
    } else if (options.path.contains('EstimatedTimeOfArrival/InterCity')) {
      intercityCalls++;
      body = jsonEncode(intercityRows ?? rows);
    } else if (options.path.contains('Bus/Route')) {
      routeCalls++;
      if (routeStatus != 200) {
        return ResponseBody.fromString(
          jsonEncode(const []),
          routeStatus,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      body = jsonEncode(routes);
    } else if (options.path.contains('TRA/Station') &&
        !options.path.contains('LiveBoard')) {
      // 用站名查代碼那一次。故意包成 v3 的形狀，順便測 unwrap。
      body = jsonEncode({
        'Stations': [
          {'StationID': stationId ?? '0900', 'StationName': {'Zh_tw': '基隆'}},
        ],
      });
    } else {
      body = jsonEncode(rows);
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 跟 [_config] 一樣，但**間隔是真的 40ms** —— 節流那組測試要量得到時間差。
final TransitConfig _throttled = TransitConfig.fromJson({
  'auth': {'token_url': 'https://example.invalid/token'},
  'api': {
    'base_url': 'https://example.invalid/api/',
    'min_interval_seconds': 0.04,
    'timeout_seconds': 0,
    'city_bus_arrivals': 'v2/Bus/EstimatedTimeOfArrival/City/{city}',
  },
  'stops': const [],
});

/// 記下每個資料請求「什麼時候被送出去」的假 HTTP 層。
class _TimingAdapter implements HttpClientAdapter {
  _TimingAdapter(this.sent, {this.failFirst = false});

  final List<DateTime> sent;

  /// 第一個資料請求回 429。用來確認佇列不會被一次失敗卡死。
  final bool failFirst;
  int _dataCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('token')) {
      return ResponseBody.fromString(
        jsonEncode({'access_token': 'fake-token', 'expires_in': 86400}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    sent.add(DateTime.now());
    final status = (failFirst && _dataCalls++ == 0) ? 429 : 200;
    return ResponseBody.fromString(
      jsonEncode(const []),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 把送出去的請求錄下來的假 HTTP 層。
///
/// token 那次不算 —— 我們要看的是資料端點帶了什麼查詢參數。
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.status = 200});

  /// 資料端點要回什麼狀態碼。
  final int status;

  RequestOptions? lastDataRequest;

  /// 資料端點被打了幾次（token 那次不算）。合併有沒有生效看這個。
  int dataRequests = 0;

  /// token 端點被打了幾次。走中繼的時候這個必須是 0。
  int tokenRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isToken = options.path.contains('token');
    if (isToken) {
      tokenRequests++;
    } else {
      dataRequests++;
      lastDataRequest = options;
    }
    return ResponseBody.fromString(
      isToken
          ? jsonEncode({'access_token': 'fake-token', 'expires_in': 86400})
          : jsonEncode(const []),
      isToken ? 200 : status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

TransitRepository _repoWith(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return TransitRepository(
    config: _config,
    client: TdxClient(
      config: _config,
      clientId: 'id',
      clientSecret: 'secret',
      dio: dio,
    ),
  );
}

/// 連不上的假 HTTP 層。**訊息裡故意塞滿不該外流的東西** ——
/// 上面那個測試檢查它們沒有跟著跑到使用者面前。
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      message: '連線失敗 ${options.uri} client_secret=super-secret-value',
    );
  }

  @override
  void close({bool force = false}) {}
}

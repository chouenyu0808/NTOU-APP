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

    test('海大體育館：15 筆裡只有一班真的有車', () async {
      final repo = _repoReturning(rowsOf('ntou-gym.json'));
      final board = await repo.board(_cityBusStop);

      expect(board.buses, hasLength(15));
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

      expect(board.buses, hasLength(53));
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
    'train_liveboard': 'v3/Rail/TRA/StationLiveBoard',
    'train_stations': 'v3/Rail/TRA/Station',
    'city_bus_filter': "StopName/Zh_tw eq '{name}'",
    'intercity_filter': "StopName/Zh_tw eq '{name}'",
    'train_liveboard_filter': "StationID eq '{station}'",
    'train_station_filter': "StationName/Zh_tw eq '{name}'",
    'route_filter': "RouteUID eq '{name}'",
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
  _CannedAdapter({required this.rows, this.stationId, this.routes = const []});

  final List<Map<String, dynamic>> rows;
  final String? stationId;

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
    if (options.path.contains('token')) {
      body = jsonEncode({
        'access_token': 'fake-token',
        'expires_in': 86400,
        'token_type': 'Bearer',
      });
    } else if (options.path.contains('Bus/Route')) {
      routeCalls++;
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
  RequestOptions? lastDataRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isToken = options.path.contains('token');
    if (!isToken) lastDataRequest = options;
    return ResponseBody.fromString(
      isToken
          ? jsonEncode({'access_token': 'fake-token', 'expires_in': 86400})
          : jsonEncode(const []),
      200,
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

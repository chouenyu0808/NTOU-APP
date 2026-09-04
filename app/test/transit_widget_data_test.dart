import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/transit_config.dart';
import 'package:ntou_app/src/transit/transit_models.dart';
import 'package:ntou_app/src/widget/transit_widget_data.dart';
import 'package:ntou_app/src/widget/widget_updater.dart';

/// 桌面小組件的交通 payload。
///
/// 重點是**它跟 App 裡那一頁說的話要一模一樣** —— 同一班車在 App 裡是
/// 「往 八斗子車站（經 海大濱海校門）」、在桌面上變成「往 八斗子車站」，
/// 使用者會以為其中一邊壞了，而且不會有任何測試紅。
void main() {
  final config = TransitConfig.fromJson({
    'version': 1,
    'stop_status': {'1': '尚未發車', '3': '末班已過'},
  });

  const gym = TransitStop(
    id: 'ntou-gym',
    name: '海大體育館',
    kind: TransitStopKind.cityBus,
  );
  const keelung = TransitStop(
    id: 'tra-keelung',
    name: '台鐵基隆站',
    kind: TransitStopKind.train,
  );

  final now = DateTime(2026, 9, 3, 10, 32);

  TransitWidgetPayload build(
    List<StopBoard> boards, {
    Set<String> favorites = const {},
  }) =>
      buildTransitWidgetPayload(
        boards: boards,
        config: config,
        favorites: favorites,
        now: now,
      );

  group('公車', () {
    test('秒數換算成畫面上那句話', () {
      final p = build([
        StopBoard(
          stop: gym,
          buses: const [
            BusArrival(
                routeName: '103', destination: '八斗子車站', estimateSeconds: 725),
            BusArrival(
                routeName: '104', destination: '基隆火車站', estimateSeconds: 20),
            BusArrival(
                routeName: '108', destination: '深澳坑', estimateSeconds: 90),
          ],
        ),
      ]);

      final rows = p.stops.single.rows;
      expect(rows[0].eta, '12 分');
      expect(rows[0].tone, ArrivalTone.normal);
      expect(rows[1].eta, '進站中');
      expect(rows[1].tone, ArrivalTone.now);
      expect(rows[2].eta, '將到站');
      expect(rows[2].tone, ArrivalTone.soon);
    });

    test('沒有預估值時用狀態碼解釋，認不得的不猜', () {
      final p = build([
        StopBoard(
          stop: gym,
          buses: const [
            BusArrival(routeName: '103', stopStatus: 3),
            BusArrival(routeName: '104', stopStatus: 9),
          ],
        ),
      ]);

      expect(p.stops.single.rows[0].eta, '末班已過');
      expect(p.stops.single.rows[1].eta, '狀態 9');
    });

    test('同一條路線出現兩次才補「經 X」', () {
      // 103 是環狀線，馬路兩邊的車終點都是八斗子車站 —— 光看終點分不出
      // 該站哪一邊，那正是使用者會搭反的地方。
      final p = build([
        StopBoard(
          stop: gym,
          buses: const [
            BusArrival(
              routeName: '103',
              destination: '八斗子車站',
              nextStop: '海大濱海校門',
              estimateSeconds: 300,
            ),
            BusArrival(
              routeName: '103',
              destination: '八斗子車站',
              nextStop: '北寧路',
              estimateSeconds: 600,
            ),
            BusArrival(
              routeName: '104',
              destination: '基隆火車站',
              nextStop: '和平橋',
              estimateSeconds: 400,
            ),
          ],
        ),
      ]);

      final rows = p.stops.single.rows;
      expect(rows[0].towards, '往 八斗子車站（經 海大濱海校門）');
      expect(rows[1].towards, '往 八斗子車站（經 北寧路）');
      // 只出現一次的不加 —— 加了只是把每一列變長。
      expect(rows[2].towards, '往 基隆火車站');
    });

    test('釘起來的路線排前面，兩組各自照到站時間', () {
      final p = build(
        [
          StopBoard(
            stop: gym,
            buses: const [
              BusArrival(routeName: '104', estimateSeconds: 100),
              BusArrival(routeName: '103', estimateSeconds: 300),
              BusArrival(routeName: '108', estimateSeconds: 500),
              BusArrival(routeName: '103', estimateSeconds: 700),
            ],
          ),
        ],
        favorites: {'103'},
      );

      final rows = p.stops.single.rows;
      expect(rows.map((r) => r.route), ['103', '103', '104', '108']);
      // 釘起來那組自己還是照時間排，不是打散重排。
      expect(rows[0].eta, '5 分');
      expect(rows[1].eta, '11 分');
      expect(rows[0].favorite, isTrue);
      expect(rows[2].favorite, isFalse);
    });
  });

  group('以本站為終點的車', () {
    test('不列出來，但要說清楚有幾班', () {
      final p = build([
        StopBoard(
          stop: gym,
          buses: const [
            BusArrival(routeName: '1813', estimateSeconds: 200, endsHere: true),
            BusArrival(routeName: '1579', estimateSeconds: 300, endsHere: true),
          ],
        ),
      ]);

      final stop = p.stops.single;
      expect(stop.rows, isEmpty);
      // **不能說成「沒有班次」** —— 明明有車，只是到站就收班。
      // 那兩件事對使用者的意義完全不同。
      expect(stop.note, '只有 2 班到站後收班的車，沒有可搭乘的班次');
    });

    test('真的沒有班次的時候，公車和列車說不一樣的話', () {
      final bus = build([StopBoard(stop: gym)]).stops.single;
      final train = build([StopBoard(stop: keelung)]).stops.single;

      expect(bus.note, '目前沒有班次資訊');
      expect(train.note, '目前沒有即將進站的列車');
    });
  });

  group('列車', () {
    test('表定時間直接顯示，誤點另外標', () {
      final p = build([
        StopBoard(
          stop: keelung,
          trains: const [
            TrainDeparture(
              trainNo: '1234',
              trainType: '區間',
              destination: '樹林',
              scheduledTime: '10:45',
            ),
            TrainDeparture(
              trainNo: '5678',
              trainType: '自強',
              destination: '潮州',
              scheduledTime: '11:02',
              delayMinutes: 7,
            ),
          ],
        ),
      ]);

      final rows = p.stops.single.rows;
      expect(rows[0].eta, '10:45');
      expect(rows[0].towards, '往 樹林');
      // 誤點是使用者最需要看到的東西，換算成「還有 N 分」會把它吃掉。
      expect(rows[1].eta, '11:02 誤點 7 分');
    });

    test('以本站為終點的列車不顯示', () {
      // 基隆是端點站，深夜可能整批都是這種。
      final p = build([
        StopBoard(
          stop: keelung,
          trains: const [
            TrainDeparture(trainNo: '1', scheduledTime: '23:50', endsHere: true),
          ],
        ),
      ]);

      expect(p.stops.single.rows, isEmpty);
      expect(p.stops.single.note, contains('收班'));
    });
  });

  group('錯誤', () {
    test('這一站抓失敗時，錯誤蓋過「沒有班次」', () {
      final p = build([
        const StopBoard(stop: gym, error: '服務忙碌中'),
      ]);

      // 說「目前沒有班次資訊」是錯的 —— 我們根本沒問到。
      expect(p.stops.single.note, '服務忙碌中');
    });

    test('一站失敗不影響其他站', () {
      final p = build([
        const StopBoard(stop: gym, error: '服務忙碌中'),
        StopBoard(
          stop: keelung,
          trains: const [TrainDeparture(trainNo: '1', scheduledTime: '10:45')],
        ),
      ]);

      expect(p.stops[0].note, '服務忙碌中');
      expect(p.stops[1].rows, hasLength(1));
    });
  });

  group('存起來再讀回來', () {
    test('一整份 payload 撐得住 JSON 來回', () {
      // 抓失敗時要能拿上一次的資料重畫，所以這份會落地。
      final original = build(
        [
          StopBoard(
            stop: gym,
            buses: const [
              BusArrival(
                routeName: '103',
                destination: '八斗子車站',
                nextStop: '北寧路',
                estimateSeconds: 20,
              ),
            ],
          ),
          const StopBoard(stop: keelung, error: '服務忙碌中'),
        ],
        favorites: {'103'},
      );

      final back = TransitWidgetPayload.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(back.updatedAt, original.updatedAt);
      expect(back.stops, hasLength(2));
      expect(back.stops[0].name, '海大體育館');
      expect(back.stops[0].rows.single.route, '103');
      expect(back.stops[0].rows.single.eta, '進站中');
      expect(back.stops[0].rows.single.tone, ArrivalTone.now);
      expect(back.stops[0].rows.single.favorite, isTrue);
      expect(back.stops[1].note, '服務忙碌中');
    });

    test('標成更新失敗時不動資料時間', () {
      // 那個時間講的是「畫面上的資料有多舊」，拿失敗的時刻蓋上去
      // 等於謊報新鮮度。
      final original = build([StopBoard(stop: gym)]);
      final failed = original.copyWith(refreshFailed: true);

      expect(failed.refreshFailed, isTrue);
      expect(failed.updatedAt, original.updatedAt);
      expect(failed.stops, original.stops);
    });
  });

  group('小組件的尺寸', () {
    test('存下去再讀回來是同一個', () {
      const surface = WidgetSurface(size: Size(320, 180), pixelRatio: 2.75);
      final back = WidgetSurface.decode(surface.encode())!;

      expect(back.size, surface.size);
      expect(back.pixelRatio, surface.pixelRatio);
    });

    test('從原生傳來的 URI 參數建得起來', () {
      final s = WidgetSurface.fromQuery(
        const {'w': '320.0', 'h': '180.0', 'dpr': '2.75'},
      )!;

      expect(s.size, const Size(320, 180));
      expect(s.pixelRatio, 2.75);
    });

    test('看不懂的就回 null，不要湊一個出來', () {
      // 湊一個出來的話會照著錯的尺寸畫圖，桌面上是一張糊的或裁掉的圖，
      // 而看起來只像「這個 App 的小組件做得很差」。
      expect(WidgetSurface.decode('壞掉的'), isNull);
      expect(WidgetSurface.decode('320|180'), isNull);
      expect(WidgetSurface.decode('0|180|2.0'), isNull);
      expect(WidgetSurface.fromQuery(const {}), isNull);
      expect(WidgetSurface.fromQuery(const {'w': '320', 'h': '180'}), isNull);
      expect(
        WidgetSurface.fromQuery(const {'w': '-1', 'h': '180', 'dpr': '2'}),
        isNull,
      );
    });
  });
}

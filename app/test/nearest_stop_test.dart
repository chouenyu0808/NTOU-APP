import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/nearest_stop.dart';
import 'package:ntou_app/src/transit/transit_config.dart';
import 'package:ntou_app/src/transit/transit_models.dart';

/// 「離使用者最近的是哪一站」。
///
/// **挑錯站不會有任何錯誤訊息** —— 顯示的是一個真實存在、看起來完全合理的
/// 站名，只是不是他站的那一個。所以這一段獨立測，而且座標用真的。
void main() {
  // 全部來自 TDX（v2/Bus/Stop 的 StopPosition、v3/Rail/TRA/Station 的
  // StationPosition），2026-09-06 透過中繼查證。跟 transit.json 裡是同一組。
  const gym = TransitStop(
    id: 'ntou-gym',
    name: '海大體育館',
    kind: TransitStopKind.cityBus,
    lat: 25.1506,
    lon: 121.77996,
  );
  const binhai = TransitStop(
    id: 'ntou-binhai-gate',
    name: '海大濱海校門',
    kind: TransitStopKind.cityBus,
    lat: 25.15097,
    lon: 121.77555,
  );
  const xiangfeng = TransitStop(
    id: 'ntou-xiangfeng-gate',
    name: '海大祥豐校門',
    kind: TransitStopKind.cityBus,
    lat: 25.151159,
    lon: 121.773208,
  );
  const terminal = TransitStop(
    id: 'keelung-bus-terminal',
    name: '基隆轉運站',
    kind: TransitStopKind.interCityBus,
    lat: 25.133,
    lon: 121.739,
  );

  const stops = [gym, binhai, xiangfeng, terminal];

  LastKnownPlace at(double lat, double lon) =>
      LastKnownPlace(lat: lat, lon: lon, at: DateTime(2026, 9, 6, 21));

  group('距離', () {
    test('算出來的公尺數跟實際相符', () {
      // 濱海校門到祥豐校門實測約 237 公尺。誤差抓 5%。
      final m = NearestStop.metresBetween(
        binhai.lat!,
        binhai.lon!,
        xiangfeng.lat!,
        xiangfeng.lon!,
      );
      expect(m, closeTo(237, 12));
    });

    test('校內到市區是四公里這個量級', () {
      final m = NearestStop.metresBetween(
        gym.lat!,
        gym.lon!,
        terminal.lat!,
        terminal.lon!,
      );
      expect(m, closeTo(4569, 200));
    });
  });

  group('最近的站', () {
    test('站在體育館旁邊就是體育館', () {
      expect(NearestStop.of(stops, at(25.1506, 121.77996))?.id, gym.id);
    });

    test('三個校門分得開 —— 它們只差兩百多公尺', () {
      // 這是整件事最容易錯的地方：三個門互相只差 237 到 683 公尺，
      // 座標填錯或算式寫錯就會挑到隔壁那個，而畫面上完全看不出來。
      expect(NearestStop.of(stops, at(25.15097, 121.77555))?.id, binhai.id);
      expect(NearestStop.of(stops, at(25.151159, 121.773208))?.id, xiangfeng.id);
    });

    test('在市區就是轉運站，不是校門', () {
      expect(NearestStop.of(stops, at(25.133, 121.739))?.id, terminal.id);
    });

    test('沒有位置就回 null，不要猜一站', () {
      // 猜出來的「最近的站」跟真的長得一模一樣。
      expect(NearestStop.of(stops, null), isNull);
    });

    test('沒有座標的站不參與比較', () {
      const noPosition = TransitStop(
        id: 'no-position',
        name: '沒有座標的站',
        kind: TransitStopKind.cityBus,
      );
      // 就算使用者就站在它「旁邊」（我們根本不知道它在哪），也不會選它。
      expect(
        NearestStop.of([noPosition, gym], at(25.1506, 121.77996))?.id,
        gym.id,
      );
      expect(NearestStop.of([noPosition], at(25.1506, 121.77996)), isNull);
    });
  });

  group('小組件要把哪一站排最前面', () {
    test('釘選優先於定位，而且標成 pinned', () {
      // 使用者人在體育館，但他釘了轉運站 —— 那是他自己指定的，
      // 定位不該把它蓋掉。pinned 決定小組件是「只顯示它」還是「排最前面」。
      final s = NearestStop.preferred(
        stops,
        pinnedId: terminal.id,
        place: at(25.1506, 121.77996),
      );
      expect(s.stop?.id, terminal.id);
      expect(s.pinned, isTrue);
    });

    test('定位挑的不算 pinned —— 它是猜的', () {
      final s = NearestStop.preferred(stops, place: at(25.133, 121.739));
      expect(s.stop?.id, terminal.id);
      // 猜的東西不該讓小組件把其他站藏起來。
      expect(s.pinned, isFalse);
    });

    test('兩個都沒有就回 null，照設定檔原本的順序', () {
      final s = NearestStop.preferred(stops);
      expect(s.stop, isNull);
      expect(s.pinned, isFalse);
    });

    test('釘的那一站不見了就回 null，不會偷偷改用定位', () {
      // 「我明明釘了，它自己跑掉」比「順序沒變」糟得多。
      final s = NearestStop.preferred(
        stops,
        pinnedId: 'this-stop-no-longer-exists',
        place: at(25.133, 121.739),
      );
      expect(s.stop, isNull);
      expect(s.pinned, isFalse);
    });
  });

  group('存起來的位置', () {
    test('寫出去再讀回來是同一個', () {
      final place = at(25.1506, 121.77996);
      final back = LastKnownPlace.decode(place.encode())!;

      expect(back.lat, place.lat);
      expect(back.lon, place.lon);
      expect(back.at, place.at);
    });

    test('看不懂的就回 null', () {
      expect(LastKnownPlace.decode(null), isNull);
      expect(LastKnownPlace.decode(''), isNull);
      expect(LastKnownPlace.decode('25.15|121.77'), isNull);
      expect(LastKnownPlace.decode('壞掉|的|東西'), isNull);
    });
  });

  group('設定檔裡的座標', () {
    test('每一站都有，而且落在基隆', () async {
      // 少一個的話那一站永遠不會被選成最近的 —— 那是安靜的退化，
      // 不是錯誤。基隆大約在 25.1°N、121.7°E。
      final config = TransitConfig.fromJson(_transitJson);
      expect(config.stops, isNotEmpty);
      for (final s in config.stops) {
        expect(s.hasPosition, isTrue, reason: '${s.id} 沒有座標');
        expect(s.lat, closeTo(25.14, 0.1), reason: s.id);
        expect(s.lon, closeTo(121.76, 0.1), reason: s.id);
      }
    });
  });
}

/// `assets/transit.json` 的 stops 那一段。
///
/// 直接寫在這裡而不是讀檔：`rootBundle` 在純 Dart 測試裡要另外架，
/// 而這個測試要驗的是「值對不對」，不是「檔案讀不讀得到」。
const _transitJson = <String, dynamic>{
  'version': 1,
  'stops': [
    {
      'id': 'ntou-gym',
      'name': '海大體育館',
      'kind': 'city_bus',
      'lat': 25.1506,
      'lon': 121.77996,
    },
    {
      'id': 'ntou-binhai-gate',
      'name': '海大濱海校門',
      'kind': 'city_bus',
      'lat': 25.15097,
      'lon': 121.77555,
    },
    {
      'id': 'ntou-xiangfeng-gate',
      'name': '海大祥豐校門',
      'kind': 'city_bus',
      'lat': 25.151159,
      'lon': 121.773208,
    },
    {
      'id': 'keelung-bus-terminal',
      'name': '基隆轉運站',
      'kind': 'intercity_bus',
      'lat': 25.133,
      'lon': 121.739,
    },
    {
      'id': 'tra-keelung',
      'name': '台鐵基隆站',
      'kind': 'train',
      'lat': 25.13191,
      'lon': 121.73837,
    },
  ],
};

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/exceptions.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TimetableCache cache;
  late AisRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = TimetableCache(prefs: await SharedPreferences.getInstance());
    repo = AisRepository(config: testConfig(), cache: cache, dio: fakeDio());
  });

  TimetableResult sample() => TimetableResult(
        year: '114',
        semester: '1',
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 26),
        courses: const [Course(name: '演算法')],
      );

  group('未登入時的守衛', () {
    test('剛建好還沒登入', () {
      expect(repo.isLoggedIn, isFalse);
    });

    test('沒登入就查課表 -> SessionExpired', () {
      expect(
        repo.fetchTimetable(year: '114', semester: '1'),
        throwsA(isA<SessionExpired>()),
      );
    });

    test('沒登入就開功能頁 -> SessionExpired', () {
      const fn = AisFunction(
        title: '課程課表查詢',
        path: 'Application/TKE/TKE22/TKE2211_.aspx',
        trail: ['教務系統'],
      );
      expect(repo.openFunction(fn), throwsA(isA<SessionExpired>()));
    });
  });

  group('快取代理', () {
    test('cached 回快取裡的東西', () async {
      await cache.write(sample());
      final got = await repo.cached('114', '1');
      expect(got, isNotNull);
      expect(got!.courses.single.name, '演算法');
    });

    test('沒快取時 cached 回 null', () async {
      expect(await repo.cached('114', '1'), isNull);
    });
  });

  group('登出對快取的處理', () {
    test('logout(forgetCache: true) 清掉課表快取', () async {
      await cache.write(sample());
      await repo.logout(forgetCache: true);
      expect(await repo.cached('114', '1'), isNull);
    });

    test('logout() 預設保留快取 —— 離線課表還要靠它', () async {
      await cache.write(sample());
      await repo.logout();
      expect(await repo.cached('114', '1'), isNotNull);
    });
  });

  group('beginLogin', () {
    test('登入頁抓不到驗證碼圖時，翻成一句人話而不是崩潰', () async {
      // fakeDio 回的頁面沒有 <img id="importantImg">，fetchCaptcha 回 null，
      // beginLogin 要丟 LoginFailed，不能讓 null 往下爆。
      await expectLater(repo.beginLogin(), throwsA(isA<LoginFailed>()));
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/credential_store.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('AppController Integration & Business Logic', () {
    test('init() 正確載入儲存的帳號、密碼標記與上次檢視的快取課表', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TimetableCache(prefs: prefs);
      final creds = CredentialStore();

      await creds.saveUsername('B11234567');
      await creds.savePassword('pass123');

      final sample = TimetableResult(
        year: '115',
        semester: '1',
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25),
        courses: const [Course(name: '作業系統')],
      );
      await cache.write(sample);

      final controller = AppController(
        repository: AisRepository(
          config: testConfig(),
          cache: cache,
          dio: fakeDio(),
        ),
        credentials: creds,
      );

      await controller.init();

      expect(controller.username, 'B11234567');
      expect(controller.hasSavedPassword, isTrue);
      expect(controller.year, '115');
      expect(controller.semester, '1');
      expect(controller.timetable, isNotNull);
      expect(controller.timetable!.courses.first.name, '作業系統');
      expect(controller.showingCache, isTrue);
      expect(controller.phase, AppPhase.loggedOut);
    });

    test('selectSemester() 切換學期時立即顯示該學期快取', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = TimetableCache(prefs: prefs);

      await cache.write(TimetableResult(
        year: '114',
        semester: '2',
        isEmpty: false,
        fetchedAt: DateTime(2026, 2, 1),
        courses: const [Course(name: '微積分二')],
      ));

      final controller = AppController(
        repository: AisRepository(
          config: testConfig(),
          cache: cache,
          dio: fakeDio(),
        ),
        credentials: CredentialStore(),
      );
      await controller.init();

      // 切換至 114-2
      await controller.selectSemester(newYear: '114', newSemester: '2');

      expect(controller.year, '114');
      expect(controller.semester, '2');
      expect(controller.timetable, isNotNull);
      expect(controller.timetable!.courses.first.name, '微積分二');
      expect(controller.showingCache, isTrue);
    });

    test('logout() 清空密碼與暫存狀態，退回 loggedOut', () async {
      final creds = CredentialStore();
      await creds.saveUsername('B11234567');
      await creds.savePassword('pass123');

      final controller = AppController(
        repository: AisRepository(
          config: testConfig(),
          cache: TimetableCache(prefs: await SharedPreferences.getInstance()),
          dio: fakeDio(),
        ),
        credentials: creds,
      );
      await controller.init();
      expect(controller.hasSavedPassword, isTrue);

      await controller.logout();

      expect(controller.phase, AppPhase.loggedOut);
      expect(controller.hasSavedPassword, isFalse);
      expect(await creds.readPassword(), isNull);
      expect(controller.captcha, isNull);
    });

    test('abandonLogin() 放棄未完成的登入流程，清除驗證碼並退回 loggedOut', () async {
      final controller = await newController();
      controller.phase = AppPhase.awaitingCaptcha;
      controller.captcha = Uint8List.fromList([1, 2, 3]);

      await controller.abandonLogin();

      expect(controller.phase, AppPhase.loggedOut);
      expect(controller.captcha, isNull);
    });
  });
}

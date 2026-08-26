import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/credential_store.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AppController> testLoginController({
    TimetableResult? cached,
    String body = '<html><body><img id="importantImg" src="captcha.png" /></body></html>',
  }) async {
    final cache = TimetableCache(prefs: await SharedPreferences.getInstance());
    if (cached != null) await cache.write(cached);

    final controller = AppController(
      repository: AisRepository(
        config: testConfig(),
        cache: cache,
        dio: fakeDio(body: body),
      ),
      credentials: CredentialStore(),
    );
    await controller.init();
    return controller;
  }

  Widget wrap(AppController c) => MaterialApp(
        home: LoginPage(controller: c),
      );

  void setPhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('LoginPage', () {
    testWidgets('畫面掛載後顯示帳號與密碼欄位，未達送出條件時登入按鈕停用', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      expect(find.text('學號'), findsOneWidget);
      expect(find.text('密碼'), findsOneWidget);
      expect(find.text('驗證碼'), findsOneWidget);

      final loginBtn = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(loginBtn.onPressed, isNull);

      await unmount(tester);
    });

    testWidgets('自動抓取驗證碼進入 awaitingCaptcha，且帳號、密碼、4 碼驗證碼填妥時按鈕啟用', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController();

      await tester.pumpWidget(wrap(controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.phase, AppPhase.awaitingCaptcha);
      expect(controller.captcha, isNotNull);

      // 填寫學號
      await tester.enterText(
        find.widgetWithText(TextField, '學號'),
        'B11234567',
      );
      // 填寫密碼
      await tester.enterText(
        find.widgetWithText(TextField, '密碼'),
        'password123',
      );
      // 填寫 4 碼驗證碼
      await tester.enterText(
        find.widgetWithText(TextField, '驗證碼'),
        'abcd',
      );
      await tester.pump();

      final loginBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '登入'),
      );
      expect(loginBtn.onPressed, isNotNull);

      await unmount(tester);
    });

    testWidgets('登入初始化失敗時顯示錯誤訊息卡片', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController(body: '<html><body>維護中</body></html>');

      await tester.pumpWidget(wrap(controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.error, isNotNull);
      expect(find.textContaining('拿不到驗證碼圖片'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('controller 有課表快取時顯示「先看上次抓到的課表」按鈕', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController(
        cached: TimetableResult(
          year: '115',
          semester: '1',
          isEmpty: false,
          fetchedAt: DateTime(2026, 8, 25),
          courses: const [Course(name: '微積分')],
        ),
      );

      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      expect(find.text('先看上次抓到的課表'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('記住密碼 Checkbox 點擊切換狀態', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      final checkboxFinder = find.byType(CheckboxListTile);
      expect(checkboxFinder, findsOneWidget);

      var checkbox = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkbox.value, isFalse);

      await tester.tap(checkboxFinder);
      await tester.pump();

      checkbox = tester.widget<CheckboxListTile>(checkboxFinder);
      expect(checkbox.value, isTrue);

      await unmount(tester);
    });
  });

  group('驗證碼輸入', () {
    /// 填好帳號密碼，停在「只差驗證碼」的狀態。
    Future<AppController> ready(WidgetTester tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.widgetWithText(TextField, '學號'),
        'B11234567',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '密碼'),
        'password123',
      );
      await tester.pump();
      return controller;
    }

    Finder captchaField() => find.widgetWithText(TextField, '驗證碼');

    String captchaText(WidgetTester tester) =>
        tester.widget<TextField>(captchaField()).controller!.text;

    testWidgets('打完第 4 碼就直接送出，不用再按登入鈕', (tester) async {
      await ready(tester);

      await tester.enterText(captchaField(), 'abc');
      await tester.pump();
      expect(captchaText(tester), 'abc'); // 還沒滿 4 碼，什麼都不該發生

      await tester.enterText(captchaField(), 'abcd');
      await tester.pumpAndSettle();

      // 送出後欄位會被清掉 —— 清掉了就代表真的送出去了
      expect(captchaText(tester), isEmpty);

      await unmount(tester);
    });

    testWidgets('整格一次被填滿時不自動送，讓人先看一眼', (tester) async {
      await ready(tester);

      // 貼上 / 自動填入是一步到位的（0 -> 4），不是「剛打完第 4 碼」。
      // 驗證碼是一次性的，送錯就燒掉一張，所以這種情況要等使用者自己按。
      await tester.enterText(captchaField(), 'abcd');
      await tester.pumpAndSettle();

      expect(captchaText(tester), 'abcd');
      final loginBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '登入'),
      );
      expect(loginBtn.onPressed, isNotNull);

      await unmount(tester);
    });

    testWidgets('點驗證碼圖是放大來看，不是直接換一張', (tester) async {
      await ready(tester);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      // 放大的對話框裡才給「換一張」——「每看不清一次就換一張」對學校那端
      // 就是多一次請求，而且多半換完還是看不清。
      expect(find.text('看清楚了'), findsOneWidget);
      expect(find.text('換一張'), findsOneWidget);

      await tester.tap(find.text('看清楚了'));
      await tester.pumpAndSettle();
      expect(find.text('看清楚了'), findsNothing);

      await unmount(tester);
    });
  });
}

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

    testWidgets('帳號被自己佔住時，講的是「怎麼辦」而不是系統狀態', (tester) async {
      // 學校原文是「系統同時一次僅許可一個帳號登入」—— 語法沒錯，但看到的人
      // 不會知道兇手是自己五分鐘前在電腦上開的選課系統。
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

      // error 要等 startLogin() 跑完才設 —— initState 的 postFrameCallback
      // 會把它清成 null。
      controller.error = '這個帳號目前在別的地方登入著。學校系統一次只允許一個登入。';
      controller.notifyListeners();
      await tester.pump();

      expect(find.text('這個帳號已經在別的地方登入了'), findsOneWidget);
      expect(find.textContaining('先去那邊按登出'), findsOneWidget);

      // 唯一還看得到自己資料的路要在錯誤旁邊，不是在頁尾等他捲下去找；
      // 而且只能有一顆，兩顆一樣的鈕會讓人以為它們做的是不同的事。
      expect(find.text('先看上次抓到的課表'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('抓不到驗證碼圖片不能被說成「打錯了」', (tester) async {
      // 圖根本沒出現，叫他重打一次是錯的指示。
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      controller.error = '拿不到驗證碼圖片。學校系統可能正在維護，或是登入頁改版了。';
      controller.notifyListeners();
      await tester.pump();

      expect(find.text('驗證碼不對'), findsNothing);
      expect(find.textContaining('重打一次就好'), findsNothing);
      expect(find.textContaining('可能正在維護'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('翻譯過的錯誤只講人話，不重貼一次原始訊息', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      controller.error = '登入失敗：頁面出現「驗證碼錯誤」。';
      controller.notifyListeners();
      await tester.pump();

      expect(find.text('驗證碼不對'), findsOneWidget);
      // 「頁面出現…」是 App 自己組的字串（見 AisSession），不是學校的原話 ——
      // 認得出來的失敗已經給了標題和下一步，再貼一次只是噪音。
      expect(find.textContaining('頁面出現'), findsNothing);

      await unmount(tester);
    });

    testWidgets('對不上的錯誤照原文顯示，不硬套一個可能是錯的解釋', (tester) async {
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      controller.error = '伺服器回了 503，學校那邊可能在維護。';
      controller.notifyListeners();
      await tester.pump();

      // 對不上的就照原文顯示，沒有硬掰一個標題出來
      expect(find.text('伺服器回了 503，學校那邊可能在維護。'), findsOneWidget);

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

    testWidgets('驗證碼回來時不要把游標從正在打的欄位搶走', (tester) async {
      // 驗證碼是三個請求、好幾秒之後才回來的，而那幾秒正好是使用者在打
      // 學號和密碼的時候。原本每次 notify 都無條件 requestFocus，症狀是
      // 密碼打到一半游標自己跳走，後面幾個字打進驗證碼欄 ——
      // 而密碼欄是遮起來的，使用者要到登入失敗才會發現。
      setPhoneSize(tester);
      final controller = await testLoginController();
      await tester.pumpWidget(wrap(controller));
      await tester.pump();

      // 使用者正在打密碼。
      final password = find.widgetWithText(TextField, '密碼');
      await tester.tap(password);
      await tester.pump();
      expect(tester.widget<TextField>(password).focusNode!.hasFocus, isTrue);

      // 驗證碼這時候才回來。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(
        tester.widget<TextField>(password).focusNode!.hasFocus,
        isTrue,
        reason: '游標要留在使用者正在打的那一格',
      );

      await unmount(tester);
    });
  });

  group('驗證碼欄的長度', () {
    // 這一條釘住的是「為什麼 _autoRecognizeCaptcha 要求剛好 4 碼」。
    // 那個 guard 看起來像多餘的防呆 —— 欄位不是已經 maxLength: 4 了嗎？
    // 沒有：maxLength 只擋鍵盤，擋不住程式直接設值。
    testWidgets('maxLength 擋不住程式設值，但擋得住鍵盤', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(controller: c, maxLength: 4),
        ),
      ));

      // 程式設 6 碼 —— 欄位就真的是 6 碼。這就是 OCR 認錯時發生的事，
      // 而 _canSubmit 要求長度剛好 4，所以登入鈕會一直是暗的。
      c.text = 'ab12XY';
      await tester.pump();
      expect(c.text.length, 6, reason: 'maxLength 不管程式設進來的值');

      // 相對地，從鍵盤打是擋得住的。
      await tester.enterText(find.byType(TextField), 'abcdefgh');
      await tester.pump();
      expect(c.text, 'abcd', reason: '鍵盤打進來的才會被截斷');
    });
  });
}

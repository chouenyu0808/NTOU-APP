import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/credential_store.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_ais.dart';

/// 同一支手機換一個學號登入。
///
/// 課表快取平常是**刻意留著**的：學校一次只允許一個 session，帳號在瀏覽器
/// 登著的時候，舊課表是唯一還看得到的東西。登出也留 —— 登出對話框就是這樣講的。
///
/// 但那個理由只在「同一個人」時成立。換一個學號登入，舊課表會一路留到
/// 第一次查詢回來為止，中間他看到的是別人的課。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 登入成功的回應。
  ///
  /// 學校**不回 302** —— 成功的回應長得跟登入頁幾乎一樣，只差這一行 JS
  /// 導向（失敗時導的是排隊頁 `DefaultQ.aspx`）。所以假的成功回應也必須
  /// 帶著它，不然 `login()` 會判定「登入沒有成功」。
  const loginOk = "<html><body><script>"
      "top.location.href='MainFrame.aspx';</script></body></html>";

  /// 導向之後那一頁 —— 沒有 frame，`enterPortal` 會直接得到空清單。
  const landing = '<html><body>ok</body></html>';

  /// 課表查詢頁。`_openQueryPage` 要在這裡找到學年和學期兩個下拉。
  const queryPage = '<html><head><title>TKE2240_</title></head><body><form>'
      '<input type="hidden" name="__VIEWSTATE" value="vs">'
      '<select name="Q_AYEAR"><option value="114">114</option>'
      '<option selected="selected" value="115">115</option></select>'
      '<select name="Q_SMS"><option selected="selected" value="1">上學期</option>'
      '<option value="2">下學期</option></select>'
      '<input type="submit" name="QUERY_BTN1" value="查詢">'
      '</form></body></html>';

  /// 查詢結果：學校說沒資料。夠了 —— 這一組測的是快取，不是解析。
  const emptyResult = '<html><body><form>'
      '<input type="hidden" name="__VIEWSTATE" value="vs">'
      '<select name="Q_AYEAR"><option selected="selected" value="115">115</option></select>'
      '<select name="Q_SMS"><option selected="selected" value="1">上學期</option></select>'
      '<span>查無符合資料</span></form></body></html>';

  late ScriptedAis ais;
  late TimetableCache cache;
  late AppController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ais = ScriptedAis();
    cache = TimetableCache(prefs: await SharedPreferences.getInstance());

    // 上一個人的課表，已經在這支手機上。
    await cache.write(TimetableResult(
      year: '114',
      semester: '1',
      isEmpty: false,
      fetchedAt: DateTime(2026, 8, 1),
      courses: const [Course(name: '別人的演算法')],
    ));

    controller = AppController(
      repository: AisRepository(
        config: testConfig(),
        cache: cache,
        dio: dioFor(ais),
      ),
      credentials: CredentialStore(),
      calendar: fakeCalendar(),
    );
    await controller.init();
  });

  Future<void> loginAs(String account) async {
    await controller.startLogin();
    ais.reply = (r) {
      final onLoginPage = r.page.toLowerCase().startsWith('default.aspx');
      // 送出登入打的是**同一個** Default.aspx，只是換成 POST。
      if (onLoginPage && r.method == 'POST') return loginOk;
      // 取登入頁交給內建的預設回應 —— 那裡才有驗證碼圖。
      // （`submitLogin` 失敗時會自己重抓一張，攔掉的話真正的失敗原因
      //   會被「拿不到驗證碼圖片」蓋過去。）
      if (onLoginPage) return null;
      if (r.page.startsWith('MainFrame.aspx')) return landing;
      if (r.page.startsWith('TKE2240_.aspx')) return queryPage;
      if (r.pressed('QUERY_BTN1')) return emptyResult;
      return queryPage;
    };
    await controller.submitLogin(
      account: account,
      password: 'pw',
      captchaText: 'abcd',
      remember: false,
    );
  }

  test('開 App 時先畫上一次看的課表', () {
    // 這是刻意的行為，下面兩條測的是它的**邊界**在哪裡。
    expect(controller.timetable?.courses.single.name, '別人的演算法');
    expect(controller.showingCache, isTrue);
  });

  test('換一個學號登入：上一個人的課表要整個消失', () async {
    await controller.credentials.saveUsername('B11111111');
    controller.username = 'B11111111';

    await loginAs('B22222222');

    expect(controller.phase, AppPhase.ready,
        reason: '登入本身要成功（錯誤：${controller.error}）');
    expect(await cache.read('114', '1'), isNull,
        reason: '上一個人的課表還在快取裡 —— 下次開 App 又會被畫出來');
    expect(
      controller.timetable?.courses.any((c) => c.name == '別人的演算法') ?? false,
      isFalse,
      reason: '畫面上不該出現前一個帳號的課',
    );
  });

  test('同一個學號再登入一次：快取留著', () async {
    // 反過來的那一半。留快取是有理由的（帳號在瀏覽器登著時登不進來），
    // 順手清掉的話那條路就沒了。
    await controller.credentials.saveUsername('B11111111');
    controller.username = 'B11111111';

    await loginAs('B11111111');

    expect(controller.phase, AppPhase.ready, reason: '${controller.error}');
    expect(await cache.read('114', '1'), isNotNull,
        reason: '同一個人，沒有理由把他自己的課表丟掉');
  });
}

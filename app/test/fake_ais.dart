import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/config/selectors.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/credential_store.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰網路的 HTTP 層。
///
/// widget test 裡的 HttpClient 是被擋住的，而且 [AisSession] 的節流會留下
/// 計時器 —— 測試會以「Pending timers」失敗，而訊息完全看不出跟登入有關。
///
/// 所以測試給一個立刻回應的 adapter，並且把節流設成 0。
/// 這樣跑的是**真正的程式路徑**，不是靠「測試時不要做這件事」的旗標繞過去。
import 'dart:convert';

/// 1x1 透明 PNG，供測試中 Image.memory 成功解碼。
final Uint8List kTransparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _InstantAdapter implements HttpClientAdapter {
  _InstantAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('.png') || options.path.toLowerCase().contains('captcha')) {
      return ResponseBody.fromBytes(
        kTransparentPng,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio({String body = '<html><body>stub</body></html>'}) {
  final dio = Dio();
  dio.httpClientAdapter = _InstantAdapter(body);
  return dio;
}

/// 節流和逾時都設成 0。
///
/// 兩個都會排計時器，而 widget test 只要結束時還有計時器掛著就會失敗 ——
/// 而且訊息是「A Timer is still pending」，完全看不出跟登入有關。
SelectorConfig testConfig() => SelectorConfig.fromJson(
      const {
        'min_interval_seconds': 0,
        'timeout_seconds': 0,
        // 選別的代碼對照跟著正式的 selectors.json 走 —— UI 靠它把 A/B
        // 翻成必修／選修，測試用空設定的話會驗到「沒翻譯」的假象。
        'pages': {
          'course_search': {
            'selection_types': {'A': '必修', 'B': '選修'},
          },
        },
      },
    );

/// 建一個不會碰網路的 controller。
Future<AppController> newController({TimetableResult? cached}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  final cache = TimetableCache(prefs: await SharedPreferences.getInstance());
  if (cached != null) await cache.write(cached);

  final controller = AppController(
    repository: AisRepository(
      config: testConfig(),
      cache: cache,
      dio: fakeDio(),
    ),
    credentials: CredentialStore(),
  );
  await controller.init();
  return controller;
}

/// 卸載畫面，並讓 `dispose` 觸發的收尾跑完。
///
/// `LoginPage.dispose` 會呼叫 `abandonLogin()` 放掉學校那端的 session ——
/// 那是 fire-and-forget 的，測試如果直接結束，那個請求會變成
/// 「A Timer is still pending」而讓測試紅掉（dio 每個請求都會排一個計時器，
/// 跟逾時設定無關）。
///
/// 所以測試結束前明確卸載一次，給它機會跑完。
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

// ---------- 多步的假 AIS ----------

/// 一次進來的請求，攤成好判斷的形狀。
class FakeRequest {
  FakeRequest({required this.method, required this.url, required this.form});

  final String method;
  final Uri url;

  /// POST 出去的欄位。GET 的話是空的。
  final Map<String, String> form;

  /// 路徑的最後一段，例如 `TKE2211_01.aspx`。
  String get page => url.pathSegments.isEmpty ? '' : url.pathSegments.last;

  String? operator [](String field) => form[field];

  /// 這次 POST 有沒有按下某顆送出鈕。
  ///
  /// `submitForm` 靠 **name=value** 告訴伺服器你按了哪顆，所以欄位在不在
  /// 就是「按了沒」。
  bool pressed(String button) => form.containsKey(button);

  /// 這次 POST 是不是某個欄位的連動 postback。
  bool cascaded(String field) => form['__EVENTTARGET'] == field;
}

/// 按請求內容決定回什麼的假 AIS。
///
/// 功能頁的流程是多步的：GET 派發器 → 跟 JS 導向 → POST 連動 → POST 查詢 →
/// POST 翻頁。**後面三步打的是同一個 URL**，所以「一個路徑配一份 HTML」的假
/// adapter 分不出來是哪一步 —— 必須看得到 POST 出去的欄位才行。
///
/// [reply] 回 null 表示「這一步我不管」，由內建的預設回應接手（登入頁、空殼）。
class ScriptedAis implements HttpClientAdapter {
  ScriptedAis([this.reply = _unscripted]);

  /// **刻意是可以中途換掉的。**
  ///
  /// `loggedInController` 會真的走一次 `beginLogin()` 去拿 session，而那件事
  /// 必須在 `setUp` 裡做完 —— `testWidgets` 的 body 跑在 fake async 裡，
  /// 在那裡面 await 真正的請求會停住不動。所以先建好 session，腳本才在測試裡指定。
  String? Function(FakeRequest req) reply;

  static String? _unscripted(FakeRequest req) => null;

  /// 收到過的每一個請求，照順序。測試用它斷言「有沒有送出該送的欄位」。
  final List<FakeRequest> seen = [];

  FakeRequest get last => seen.last;

  /// 只留 POST —— 斷言送出內容時不想被中間的 GET 洗掉。
  List<FakeRequest> get posts =>
      seen.where((r) => r.method == 'POST').toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri;
    if (url.path.endsWith('.png') ||
        url.toString().toLowerCase().contains('captcha')) {
      return ResponseBody.fromBytes(
        kTransparentPng,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      );
    }

    final form = <String, String>{};
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      if (bytes.isNotEmpty) {
        form.addAll(
          Uri.splitQueryString(utf8.decode(bytes, allowMalformed: true)),
        );
      }
    }

    final req = FakeRequest(method: options.method, url: url, form: form);
    seen.add(req);

    return ResponseBody.fromString(
      reply(req) ?? _fallback(req),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  /// 測試沒特別指定的請求。
  ///
  /// 登入頁要給得出驗證碼圖 —— [loggedInRepository] 靠 `beginLogin()` 拿 session，
  /// 沒有 `<img id="importantImg">` 它會丟 `LoginFailed`。
  static String _fallback(FakeRequest req) =>
      req.page.toLowerCase().startsWith('default.aspx')
          ? '<html><body><form>'
              '<input name="M_PORTAL_LOGIN_ACNT"><input name="LoginPWD">'
              '<img id="importantImg" src="Temp/Captcha/x.png?t=1">'
              '</form></body></html>'
          : '<html><body>stub</body></html>';

  @override
  void close({bool force = false}) {}
}

/// 建一個「已經有 session」的 repository，接上 [ais]。
///
/// 只走 `beginLogin()`：`openFunction` 要的就只是 session 存在而已，
/// 不需要把整套登入握手（四個 frame + 課表查詢頁）都假出來。
Future<AisRepository> loggedInRepository(ScriptedAis ais) async {
  SharedPreferences.setMockInitialValues({});
  final repo = AisRepository(
    config: testConfig(),
    cache: TimetableCache(prefs: await SharedPreferences.getInstance()),
    dio: Dio()..httpClientAdapter = ais,
  );
  await repo.beginLogin();
  ais.seen.clear(); // 登入那兩個請求跟功能頁的斷言無關
  return repo;
}

/// 已登入的 controller，功能頁測試用。
Future<AppController> loggedInController(ScriptedAis ais) async {
  FlutterSecureStorage.setMockInitialValues({});
  final repo = await loggedInRepository(ais);
  return AppController(repository: repo, credentials: CredentialStore());
}

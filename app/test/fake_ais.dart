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
      const {'min_interval_seconds': 0, 'timeout_seconds': 0},
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

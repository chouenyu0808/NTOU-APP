import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/ais_session.dart';
import 'package:ntou_app/src/ais/exceptions.dart';
import 'package:ntou_app/src/ais/page.dart';

import 'fake_ais.dart';

/// 連線層可控的假 adapter：前 [failTimes] 次丟指定型別的 DioException，之後回 200。
class _FlakyAdapter implements HttpClientAdapter {
  _FlakyAdapter({
    required this.failTimes,
    this.body = '<html>ok</html>',
    this.failType = DioExceptionType.connectionError,
  });

  int failTimes;
  final String body;
  final DioExceptionType failType;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (calls <= failTimes) {
      throw DioException(requestOptions: options, type: failType);
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

AisSession sessionWith(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return AisSession(config: testConfig(), dio: dio);
}

AisPage page(String html, {String url = 'https://ais.ntou.edu.tw/x.aspx'}) =>
    AisPage(url: url, status: 200, html: html);

void main() {
  // 純方法不碰網路，隨手給個假 adapter 就能建 session。
  final s = sessionWith(_FlakyAdapter(failTimes: 0));

  const loginHtml =
      '<html><body><input name="M_PORTAL_LOGIN_ACNT"><input name="LoginPWD"></body></html>';
  const normalHtml = '<html><body><table id="DataGrid"></table></body></html>';

  group('isSessionConflict（同帳號只能一個 session）', () {
    test('被導到 ConfirmInOrOut.aspx 算衝突', () {
      expect(
        AisSession.isSessionConflict(
          page('<html></html>', url: 'https://ais.ntou.edu.tw/ConfirmInOrOut.aspx'),
        ),
        isTrue,
      );
    });

    test('頁面出現「僅許可一個帳號登入」也算衝突', () {
      expect(
        AisSession.isSessionConflict(page('<html>系統同時一次僅許可一個帳號登入</html>')),
        isTrue,
      );
    });

    test('正常頁不算衝突', () {
      expect(AisSession.isSessionConflict(page(normalHtml)), isFalse);
    });
  });

  group('checkSession', () {
    test('正常頁原樣返回', () {
      final p = page(normalHtml);
      expect(s.checkSession(p), same(p));
    });

    test('被踢回登入頁 -> SessionExpired', () {
      expect(() => s.checkSession(page(loginHtml)), throwsA(isA<SessionExpired>()));
    });

    test('重複登入衝突 -> SessionExpired', () {
      expect(
        () => s.checkSession(
          page('<html></html>', url: 'https://ais.ntou.edu.tw/ConfirmInOrOut.aspx'),
        ),
        throwsA(isA<SessionExpired>()),
      );
    });
  });

  group('isLoginPage', () {
    test('兩個指紋都在才算登入頁', () {
      expect(s.isLoginPage(page(loginHtml)), isTrue);
    });

    test('只有一個指紋不算', () {
      expect(
        s.isLoginPage(page('<html><input name="M_PORTAL_LOGIN_ACNT"></html>')),
        isFalse,
      );
    });
  });

  group('captchaUrl', () {
    test('抓得到 img#importantImg 的 src', () {
      final url = s.captchaUrl(
        page('<html><img id="importantImg" src="/Temp/Captcha/abc.png?t=1"></html>'),
      );
      expect(url, '/Temp/Captcha/abc.png?t=1');
    });

    test('src 是空的（沒先過排隊頁）-> null', () {
      expect(s.captchaUrl(page('<html><img id="importantImg" src=""></html>')), isNull);
    });

    test('沒有驗證碼圖 -> null', () {
      expect(s.captchaUrl(page('<html></html>')), isNull);
    });
  });

  group('frameSources', () {
    final base = Uri.parse('https://ais.ntou.edu.tw/');

    test('只跟同源、有 src 的 frame，其餘一律略過', () {
      final p = page(
        '<html><frameset>'
        '<frame src="title.aspx?x=1">' // 同源 -> 收
        '<frame src="">' // 沒 src -> 略過
        '<iframe src="about:blank"></iframe>' // about: -> 略過
        '<iframe src="javascript:void(0)"></iframe>' // javascript: -> 略過
        '<frame src="//evil.example.com/x">' // 協定相對、站外 -> 略過
        '</frameset></html>',
        url: 'https://ais.ntou.edu.tw/MainFrame.aspx',
      );

      final uris = AisSession.frameSources(p, base);
      expect(uris.length, 1);
      expect(uris.single.toString(), 'https://ais.ntou.edu.tw/title.aspx?x=1');
      expect(uris.every((u) => u.host == 'ais.ntou.edu.tw'), isTrue);
    });
  });

  group('get 的重試（只有 GET 重試，且只重試連線層錯誤）', () {
    test('連線層錯誤會重試，最後成功', () async {
      final adapter = _FlakyAdapter(failTimes: 1, body: '<html>好了</html>');
      final page = await sessionWith(adapter).get('Default.aspx', retries: 2);
      expect(page.html, contains('好了'));
      expect(adapter.calls, 2); // 1 次失敗 + 1 次成功
    });

    test('重試用完後翻成一句人話（NetworkFailure）', () async {
      final adapter = _FlakyAdapter(failTimes: 99);
      await expectLater(
        sessionWith(adapter).get('Default.aspx', retries: 0),
        throwsA(isA<NetworkFailure>()
            .having((e) => e.message, 'message', contains('學校系統'))),
      );
      expect(adapter.calls, 1); // retries: 0，只試一次
    });

    test('非連線層錯誤不重試', () async {
      final adapter =
          _FlakyAdapter(failTimes: 99, failType: DioExceptionType.badResponse);
      await expectLater(
        sessionWith(adapter).get('Default.aspx', retries: 2),
        throwsA(isA<NetworkFailure>()),
      );
      expect(adapter.calls, 1); // 沒有重試
    });
  });

  group('post 不重試（POST 不冪等）', () {
    test('連線失敗直接丟 NetworkFailure，不重送', () async {
      final adapter = _FlakyAdapter(failTimes: 99);
      final session = sessionWith(adapter);
      await expectLater(
        session.post(Uri.parse('https://ais.ntou.edu.tw/Default.aspx'), {'a': 'b'}),
        throwsA(isA<NetworkFailure>()),
      );
      expect(adapter.calls, 1);
    });
  });

  _viewStateScopeTests();
}

/// 每次都回一份帶著自己 `__VIEWSTATE` 的頁面，並記下收到的欄位。
class _ViewStateAdapter implements HttpClientAdapter {
  final List<({String path, Map<String, String> form})> seen = [];

  static String _form(String viewState) =>
      '<html><body><form>'
      '<input type="hidden" name="__VIEWSTATE" value="$viewState" />'
      '</form></body></html>';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // POST 的內容在 requestStream 上，不在 options.data ——
    // dio 到這一層已經把它編碼成 bytes 了。
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
    seen.add((path: options.uri.path, form: form));
    // 每一頁的 viewstate 各不相同 —— 名字就是它的路徑。
    return ResponseBody.fromString(
      _form('VS${options.uri.path}'),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void _viewStateScopeTests() {
  group('__VIEWSTATE 跟著頁面走', () {
    test('中途 GET 過別的頁面，postback 送的還是原本那一頁的 viewstate', () async {
      // 這正是「查上課時間」的流程：postback 搜尋頁 → GET 課程詳細頁，
      // 一門接一門地重複。
      //
      // 隱藏欄位的快取如果無條件蓋掉頁面自己的值，第二門 postback 就會帶著
      // **詳細頁**的 viewstate 去送搜尋頁 —— 學校不認，回一頁沒有內容的東西。
      // 症狀是「只有第一門查得到時間」，其餘全部查不到，而且不會報錯。
      final adapter = _ViewStateAdapter();
      final s = sessionWith(adapter);
      final search = page(
        _ViewStateAdapter._form('VS_SEARCH'),
        url: 'https://ais.ntou.edu.tw/Application/TKE/TKE22/TKE2211_01.aspx',
      );

      await s.postback(search, 'DataGrid\$ctl02\$COSID');
      await s.get('Application/TKE/TKE22/TKE2240_03.aspx?PKNO=1');
      await s.postback(search, 'DataGrid\$ctl03\$COSID');

      final posts = adapter.seen.where((r) => r.form.isNotEmpty).toList();
      expect(posts, hasLength(2));
      expect(posts[0].form['__VIEWSTATE'], 'VS_SEARCH');
      expect(posts[1].form['__VIEWSTATE'], 'VS_SEARCH',
          reason: '第二次送的必須還是搜尋頁的，不是課程詳細頁的');
    });

    test('post 回同一頁時，用的是最新一次回應的 viewstate', () async {
      // 反過來這條也要成立：連續操作同一頁時，伺服器每次都會給新的
      // __VIEWSTATE，要拿最新的送，不能一直用最初載入時那份。
      final adapter = _ViewStateAdapter();
      final s = sessionWith(adapter);
      final p = page(
        _ViewStateAdapter._form('VS_OLD'),
        url: 'https://ais.ntou.edu.tw/a.aspx',
      );

      await s.postback(p, 'X');
      await s.postback(p, 'Y');

      final posts = adapter.seen.where((r) => r.form.isNotEmpty).toList();
      expect(posts[1].form['__VIEWSTATE'], 'VS/a.aspx',
          reason: '同一頁的話要用回應帶回來的新 viewstate');
    });
  });
}

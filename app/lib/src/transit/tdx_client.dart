import 'dart:async';

import 'package:dio/dio.dart';

import 'transit_config.dart';

/// 交通資料抓不到時丟這個。
///
/// **刻意只帶一句給使用者看的話，不帶原始例外。** 跟 `LoginFailed` 同樣的
/// 理由：dio 的訊息裡有完整 URL、查詢字串和堆疊，那是給我們除錯用的，
/// 不是使用者要看的東西，而且它會一路跟著顯示到畫面上。
class TransitUnavailable implements Exception {
  const TransitUnavailable(this.message);
  final String message;

  @override
  String toString() => 'TransitUnavailable: $message';
}

/// 還沒設定 TDX 金鑰。畫面靠這個型別決定要顯示設定引導而不是錯誤。
class TdxNotConfigured extends TransitUnavailable {
  const TdxNotConfigured() : super('尚未設定交通資料金鑰');
}

/// TDX 的 client：換 token、打 API。
///
/// ## 金鑰怎麼進來
///
/// 用 `--dart-define` 在 build 的時候注入，不進版控：
///
/// ```
/// flutter build apk --release --target-platform android-arm64 \
///   --dart-define=TDX_CLIENT_ID=xxx --dart-define=TDX_CLIENT_SECRET=yyy
/// ```
///
/// **這不是把 secret 藏起來** —— `--dart-define` 的值會編進 APK，
/// 有心人反編譯就挖得到。TDX 的免費金鑰最壞的下場是配額被別人用掉，
/// 這個代價收得起；真正該藏的東西（學校密碼）走的是 Keystore，不是這條路。
/// 值得這樣做的理由只有一個：金鑰不會進 git，不會跟著原始碼被推上去。
class TdxClient {
  TdxClient({
    required this.config,
    Dio? dio,
    String? clientId,
    String? clientSecret,
    DateTime Function()? now,
  })  : _clientId = clientId ?? const String.fromEnvironment('TDX_CLIENT_ID'),
        _clientSecret =
            clientSecret ?? const String.fromEnvironment('TDX_CLIENT_SECRET'),
        _now = now ?? DateTime.now,
        // 獨立的 Dio，不共用 AIS 那個。
        //
        // 那一個掛著 cookie jar 和學校的 baseUrl，而且帶著登入後的 session。
        // 把它借來打交通部的伺服器，等於每次查公車都把學校的 cookie 送出去。
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: _timeoutOf(config),
              receiveTimeout: _timeoutOf(config),
              // 自己判斷狀態碼，才能把 401/429 翻成看得懂的話。
              validateStatus: (_) => true,
            ));

  final TransitConfig config;
  final Dio _dio;
  final String _clientId;
  final String _clientSecret;
  final DateTime Function() _now;

  /// 目前這張 token 和它的到期時間。
  ///
  /// **只放在記憶體，不落地。** 它是金鑰換來的東西，寫進 SharedPreferences
  /// 等於把它留在一個 root 過的手機上讀得到的地方，而重換一張只要一個請求。
  String? _token;
  DateTime? _tokenExpiry;

  /// 正在換 token 的那個 future。
  ///
  /// 五個站點是同時開始抓的，沒有這個的話它們會同時發現「token 過期了」
  /// 而各換一張 —— 五個請求打在一個每分鐘只准 20 次的端點上。
  Future<String>? _pending;

  /// 節流用：上一個請求送出的時間。
  DateTime? _lastRequest;

  /// 節流的佇列。**這個東西是整個節流的關鍵，不要拿掉。**
  ///
  /// 沒有它的話 [_throttle] 對併發完全無效：五個站是同時發的，五個呼叫
  /// 會讀到同一個 `_lastRequest`、對同一個舊時間算間隔、同時通過檢查，
  /// 然後同時把時間寫成幾乎一樣的值 —— 看起來有節流，實際上五個請求
  /// 一起打出去，TDX 回 429，畫面上五張卡片全變「服務忙碌中」。
  Future<void> _queue = Future<void>.value();

  /// 逾時。**0 或負數代表不設逾時** —— 測試用的，跟 [SelectorConfig.timeout]
  /// 同一個慣例：dio 會為每個逾時排一個計時器，widget test 會因為那個計時器
  /// 還掛著而失敗。
  static Duration? _timeoutOf(TransitConfig c) =>
      c.timeout > Duration.zero ? c.timeout : null;

  bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  /// 排隊，確保兩個請求之間至少隔 [TransitConfig.minInterval]。
  ///
  /// **真的排隊** —— 一個接一個，不是各自檢查。呼叫端照樣可以用
  /// `Future.wait` 同時丟五個進來，它們會在這裡排成一列依序放行。
  Future<void> _throttle() {
    final next = _queue.then((_) async {
      final last = _lastRequest;
      if (last != null) {
        final gap = _now().difference(last);
        if (gap < config.minInterval) {
          await Future<void>.delayed(config.minInterval - gap);
        }
      }
      _lastRequest = _now();
    });
    // 這一環壞掉不能把後面整條鏈都拖著壞 —— 佇列只負責「隔開時間」，
    // 請求本身成不成功是上面那層的事。
    _queue = next.catchError((_) {});
    return next;
  }

  /// 拿一張還沒過期的 token，需要的話去換一張新的。
  Future<String> _accessToken() {
    final token = _token;
    final expiry = _tokenExpiry;
    if (token != null && expiry != null && _now().isBefore(expiry)) {
      return Future.value(token);
    }
    return _pending ??= _fetchToken().whenComplete(() => _pending = null);
  }

  Future<String> _fetchToken() async {
    if (!isConfigured) throw const TdxNotConfigured();
    await _throttle();

    late final Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        config.tokenUrl,
        data: {
          'grant_type': 'client_credentials',
          'client_id': _clientId,
          'client_secret': _clientSecret,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
        ),
      );
    } on DioException {
      // 這裡刻意不看例外內容。dio 會把送出的 body 放進錯誤訊息裡，
      // 而這個請求的 body 就是 client_secret 本人。
      throw const TransitUnavailable('連不上交通資料服務');
    }

    if (res.statusCode == 401 || res.statusCode == 400) {
      throw const TransitUnavailable('交通資料金鑰被拒絕，請確認金鑰是否正確');
    }
    if (res.statusCode == 429) {
      throw const TransitUnavailable('交通資料服務忙碌中，等一下再試');
    }
    if (res.statusCode != 200) {
      throw TransitUnavailable('交通資料服務回應異常（${res.statusCode}）');
    }

    final body = res.data;
    if (body is! Map) throw const TransitUnavailable('交通資料服務回應格式不符');
    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw const TransitUnavailable('交通資料服務沒有給認證碼');
    }

    // expires_in 預設 86400 秒。提早 renewMargin 換掉。
    final ttl = (body['expires_in'] as num?)?.toInt() ?? 86400;
    _token = token;
    _tokenExpiry = _now().add(Duration(seconds: ttl) - config.renewMargin);
    return token;
  }

  /// 打一個 TDX 的資料端點，回傳解析後的 JSON 陣列。
  ///
  /// [path] 是相對於 `base_url` 的路徑，[query] 是 OData 參數
  /// （`$filter`、`$top`、`$format`）。
  Future<List<Map<String, dynamic>>> get(
    String path, {
    Map<String, String> query = const {},
  }) async {
    if (path.isEmpty) throw const TransitUnavailable('這項資料尚未設定');
    final token = await _accessToken();
    await _throttle();

    late final Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(
        '${config.baseUrl}$path',
        queryParameters: {'\$format': 'JSON', ...query},
        options: Options(
          headers: {'authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
      );
    } on DioException {
      // 同樣不把 dio 的訊息帶出去 —— 那裡面有完整 URL。
      throw const TransitUnavailable('連不上交通資料服務');
    }

    if (res.statusCode == 401) {
      // token 被提早作廢了（換過金鑰、對方重啟）。丟掉重來一次就好。
      _token = null;
      _tokenExpiry = null;
      throw const TransitUnavailable('交通資料認證過期，請重新整理');
    }
    if (res.statusCode == 429) {
      throw const TransitUnavailable('交通資料服務忙碌中，等一下再試');
    }
    if (res.statusCode != 200) {
      throw TransitUnavailable('交通資料服務回應異常（${res.statusCode}）');
    }

    return unwrap(res.data);
  }

  /// 從回應裡挖出那個陣列。
  ///
  /// **TDX 的 v2 和 v3 包法不一樣**：v2 直接回一個裸陣列，v3 把它包在一個
  /// 物件裡（`{"Stations": [...]}`、`{"TrainLiveBoards": [...]}`），而那個
  /// key 每個端點都不同。公開的 swagger 在 schema 那段是截斷的，沒有金鑰
  /// 打不到真實回應 —— 與其賭一個 key 名，不如兩種都吃：是陣列就用，
  /// 是物件就找出裡面第一個陣列型別的值。
  ///
  /// 這樣寫的另一個好處是 TDX 哪天把 v2 換成 v3，這裡不用改。
  static List<Map<String, dynamic>> unwrap(Object? data) {
    List<dynamic>? list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      for (final v in data.values) {
        if (v is List) {
          list = v;
          break;
        }
      }
    }
    if (list == null) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) e,
    ];
  }
}

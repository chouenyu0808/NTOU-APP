import 'dart:async';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../config/selectors.dart';
import 'decode.dart';
import 'exceptions.dart';
import 'forms.dart';
import 'js_redirect.dart';
import 'origin.dart';
import 'page.dart';

/// log 一行。**只會收到 URL / 狀態碼 / 長度，永遠不會收到頁面內容。**
typedef AisLogger = void Function(String line);

/// `ais.ntou.edu.tw` 的 WebForms session client。
///
/// 這是 `spike/ais.py` 的移植版，刻意一個方法對一個方法，
/// 學校改版時兩邊可以對照著看。差異只有三處，每一處都有註解說明為什麼。
///
/// 安全原則（跟 spike 一樣，但在 App 上更要緊）：
///   - 密碼只存在記憶體與 Keychain / Keystore，絕不寫檔、絕不進 log
///   - **登入回應永遠不進 log、不進例外、不落地**（校方系統會回吐明文密碼）
///   - 內建節流，不要把學校的機器打爛
class AisSession {
  AisSession({required this.config, Dio? dio, CookieJar? cookieJar, this.log})
      : cookieJar = cookieJar ?? CookieJar(),
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = config.baseUrl
      ..connectTimeout = _timeout
      ..receiveTimeout = _timeout
      ..responseType = ResponseType.bytes
      ..followRedirects = true
      ..maxRedirects = 5
      // 這個系統用 403 表達「event validation 拒絕了你送的值」，
      // 用 200 表達「session 逾時」。所以 4xx 不能當成連線錯誤丟掉 ——
      // 頁面內容才是判斷依據。
      ..validateStatus = ((int? s) => s != null && s < 500)
      ..headers.addAll(<String, String>{
        'User-Agent': _kUserAgent,
        'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      });
    _dio.interceptors.add(CookieManager(this.cookieJar));
  }

  static const String _kUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  /// 登入頁的指紋。session 逾時的回應會長成這樣（**而且狀態碼是 200**）。
  static const List<String> loginMarkers = ['M_PORTAL_LOGIN_ACNT', 'LoginPWD'];

  final SelectorConfig config;
  final CookieJar cookieJar;
  final AisLogger? log;

  final Dio _dio;
  Map<String, String> _hidden = <String, String>{};
  String _lastUrl = '';
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  Uri get _base => Uri.parse(config.baseUrl);

  /// dio 用 null 表示「不設逾時」。設定檔給 0 就是那個意思。
  Duration? get _timeout =>
      config.timeout > Duration.zero ? config.timeout : null;

  // ---------- 低階 ----------

  /// 節流。學校的機器不是給我們壓測的。
  Future<void> _throttle() async {
    final gap = config.minInterval - DateTime.now().difference(_lastRequestAt);
    if (gap > Duration.zero) await Future<void>.delayed(gap);
    _lastRequestAt = DateTime.now();
  }

  /// 把 response 收進來：更新隱藏欄位快取、記住當前 URL。
  ///
  /// 關鍵：每次 postback 後 `__VIEWSTATE` 都會變，一定要重抓。
  AisPage _absorb(Response<dynamic> r, Uri requested) {
    final data = r.data;
    final bytes = data is List<int> ? data : const <int>[];
    final realUri = r.realUri.toString();
    final page = AisPage(
      url: realUri.isEmpty ? requested.toString() : realUri,
      status: r.statusCode ?? 0,
      html: decodeHtml(bytes),
    );
    _lastUrl = page.url;

    final found = scrapeHiddenFields(page.doc);
    if (found.isNotEmpty) _hidden = found;

    log?.call('  ${page.summary} viewstate ${(found['__VIEWSTATE'] ?? '').length}B');
    return page;
  }

  Uri _resolve(String path) => _base.resolve(path);

  /// GET，遇到連線層的錯誤會重試。
  ///
  /// **只有 GET 重試，POST 不重試。** GET 是冪等的；POST 送出後連線斷掉時，
  /// 沒辦法知道伺服器到底處理了沒有 —— 重送可能造成重複提交。
  /// （而且登入 POST 綁著一次性驗證碼，重送本來就會失敗。）
  Future<AisPage> get(String path, {int retries = 2}) async {
    final url = _resolve(path);
    for (var attempt = 0;; attempt++) {
      await _throttle();
      try {
        return _absorb(await _dio.getUri<dynamic>(url), url);
      } on DioException catch (e) {
        if (!_isConnectionLevel(e) || attempt >= retries) {
          throw NetworkFailure(_explain(e));
        }
        final wait = Duration(seconds: 1 << attempt);
        log?.call('  連線失敗（${e.type.name}），${wait.inSeconds} 秒後重試');
        await Future<void>.delayed(wait);
      }
    }
  }

  Future<AisPage> post(Uri url, Map<String, String> fields) async {
    await _throttle();
    try {
      final r = await _dio.postUri<dynamic>(
        url,
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, String>{
            'Referer': _lastUrl.isEmpty ? url.toString() : _lastUrl,
            'Origin': config.baseUrl.replaceAll(RegExp(r'/$'), ''),
          },
        ),
      );
      return _absorb(r, url);
    } on DioException catch (e) {
      throw NetworkFailure(_explain(e));
    }
  }

  static bool _isConnectionLevel(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.unknown;

  /// 把 dio 的錯誤翻成一句使用者看得懂的話。
  ///
  /// **不要把 `e.toString()` 丟給使用者。** dio 的訊息裡有完整 URL 和堆疊，
  /// 對學生沒有意義，而且看起來像是 App 壞了。
  static String _explain(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          '連線逾時。學校系統可能正忙（選課期間很常見），等一下再試。',
        DioExceptionType.badCertificate =>
          '無法驗證學校網站的憑證。如果你在公共 Wi-Fi 上，換個網路再試。',
        DioExceptionType.connectionError =>
          '連不上學校系統。檢查一下網路，或確認 ais.ntou.edu.tw 是不是在維護。',
        _ => '連線失敗，請再試一次。',
      };

  // ---------- WebForms 舞步 ----------

  /// 填欄位、按某顆按鈕送出。查詢頁都是這樣運作的。
  ///
  /// 跟 `__doPostBack` 的差別：這裡是 `<input type=submit>`，靠 **name=value**
  /// 告訴伺服器你按了哪顆，`__EVENTTARGET` 要留空。
  Future<AisPage> submitForm(
    AisPage page,
    String button, {
    Map<String, String>? values,
  }) async {
    final fields = formFields(page.doc)..addAll(_hidden);
    final el = page.doc.querySelector('input[name="$button"]');

    // 有些按鈕的 onclick 會順手設一個隱藏欄位再送出，例如
    //     onclick="return doQuery('1')"   ->   QUERY_TYPE = "1"
    // 漏掉的話伺服器直接拋例外，只回一句通用的 403，看不出少了什麼。
    // 呼叫端明確給的值優先，這裡只補沒給的。
    onclickSideEffects(el).forEach((k, v) {
      if (values == null || !values.containsKey(k)) {
        fields[k] = v;
        log?.call('  （依 onclick 自動設定 $k=$v）');
      }
    });

    if (values != null) {
      checkValues(page.doc, values);
      fields.addAll(values);
    }

    fields[button] = el?.attributes['value'] ?? '';
    fields['__EVENTTARGET'] = '';
    fields['__EVENTARGUMENT'] = '';

    return post(Uri.parse(page.url), fields);
  }

  /// 模擬 `__doPostBack(target, argument)`。
  ///
  /// 連動下拉靠這個。這個系統有三組：學制→系所、教師系所→教師名單、大樓→教室。
  /// 它們的 `onchange` 長這樣：
  /// ```javascript
  /// onchange="javascript:setTimeout('__doPostBack(\'Q_TCH_FACULTY_CODE\',\'\')', 0)"
  /// ```
  /// 選了上游還沒 postback 之前，下游的 `<select>` 是**0 個 option** ——
  /// 那種欄位送出去會踩 event validation，而錯誤只是一句通用的 403。
  ///
  /// 跟 [submitForm] 的差別：這裡靠 `__EVENTTARGET` 告訴伺服器誰觸發的，
  /// **不送任何按鈕的 name**。反過來做會變成「按了某顆按鈕」，執行的是別的邏輯。
  Future<AisPage> postback(
    AisPage page,
    String target, {
    String argument = '',
    Map<String, String>? values,
  }) async {
    final fields = formFields(page.doc)..addAll(_hidden);
    if (values != null) {
      checkValues(page.doc, values);
      fields.addAll(values);
    }
    fields['__EVENTTARGET'] = target;
    fields['__EVENTARGUMENT'] = argument;
    return post(Uri.parse(page.url), fields);
  }

  /// 哪些欄位改了之後要重送整張表單（ASP.NET 的 AutoPostBack）。
  ///
  /// **刻意走 DOM 而不是對原始 HTML 下正則。** 屬性裡的引號被編碼成 `&#39;`
  /// 再加一層反斜線跳脫，原始碼長這樣：
  /// ```
  /// onchange="javascript:setTimeout(&#39;__doPostBack(\&#39;Q_DEGREE_CODE\&#39;,…
  /// ```
  /// 直接 regex 只會抓到頁面上那些**沒有被編碼**的（例如分頁的 `ReQuery`），
  /// 而真正的連動下拉全部漏掉 —— 而且漏得很安靜。
  /// HTML 解析器會把屬性值的實體解碼掉，從它讀就對了。
  static Set<String> autoPostBackFields(AisPage page) {
    final out = <String>{};
    for (final el in page.doc.querySelectorAll('[onchange], [onclick]')) {
      for (final attr in ['onchange', 'onclick']) {
        final js = el.attributes[attr];
        if (js == null) continue;
        for (final m in _doPostBackRe.allMatches(js)) {
          final target = m.group(1);
          if (target != null && target.isNotEmpty) out.add(target);
        }
      }
    }
    return out;
  }

  /// `__doPostBack(\'Q_X\',\'\')` —— 反斜線是可選的，這個系統兩種寫法都有。
  static final RegExp _doPostBackRe =
      RegExp(r"""__doPostBack\(\s*\\?['"]([^'"\\]+)""");

  // ---------- 登入 ----------

  /// 取得**真正可以登入的**登入頁。
  ///
  /// AIS 在登入前擋了一層虛擬排隊。實測流程：
  /// ```
  /// GET Default.aspx   -> 有登入表單，但驗證碼 <img> 沒有 src
  /// GET DefaultQ.aspx  -> 排隊頁（人少時直接放行）
  /// GET Default.aspx   -> 這次驗證碼 src 才出現
  /// ```
  /// 跳過中間那步，驗證碼永遠是空的，登入必定失敗 ——
  /// 而且你會找不到原因，因為頁面上根本沒有圖可以看。
  ///
  /// 排隊機制是選課尖峰時保護伺服器用的，**照著走、不要繞過**。
  Future<AisPage> openLoginPage() async {
    final login = config.login;
    var page = await get(login.path);

    final queuePath = login.queuePath;
    if (queuePath != null && page.html.contains(login.queueRedirectMarker)) {
      log?.call('  偵測到排隊關卡，依序通過...');
      await get(queuePath);
      page = await get(login.path);
    }
    return page;
  }

  /// 驗證碼圖的網址。檔名每個 session 都不一樣，只能從頁面上抓，不能寫死。
  String? captchaUrl(AisPage page) {
    final src = page.doc
        .querySelector('img#${config.login.captchaImgId}')
        ?.attributes['src'];
    return (src == null || src.isEmpty) ? null : src;
  }

  /// 抓驗證碼圖片。**不要 OCR** —— 顯示給使用者自己打，體驗差不了多少，
  /// 也不會踩到「繞過防護」那條線。
  Future<Uint8List?> fetchCaptcha(AisPage page) async {
    final src = captchaUrl(page);
    if (src == null) return null;
    await _throttle();
    try {
      final r = await _dio.getUri<dynamic>(
        Uri.parse(page.url).resolve(src),
        options: Options(
          responseType: ResponseType.bytes,
          headers: <String, String>{'Referer': _lastUrl},
        ),
      );
      final data = r.data;
      return data is List<int> ? Uint8List.fromList(data) : null;
    } on DioException catch (e) {
      throw NetworkFailure(_explain(e));
    }
  }

  /// 登入。[page] 要傳 [openLoginPage] 的結果 ——
  /// 驗證碼跟 `__VIEWSTATE` 都綁在那次 session 狀態上，重抓一次頁面驗證碼就換了。
  ///
  /// 回傳登入後的落地頁（`MainFrame.aspx`）。
  ///
  /// > **這個方法裡的 `result` 含兩次明文密碼**（校方系統會回吐）。
  /// > 不要 log 它、不要存它、不要把它掛在例外上。方法結束它就該被回收。
  Future<AisPage> login({
    required AisPage page,
    required String username,
    required String password,
    String? captcha,
  }) async {
    final cfg = config.login;

    final fields = formFields(page.doc)..addAll(_hidden);
    fields[cfg.usernameField] = username;
    fields[cfg.passwordField] = password;
    if (captcha != null && captcha.isNotEmpty) {
      fields[cfg.captchaField] = captcha;
    }

    // 登入鈕：Button 用 name=value，LinkButton 用 __EVENTTARGET
    if (cfg.submitEventTarget.isNotEmpty) {
      fields['__EVENTTARGET'] = cfg.submitEventTarget;
      fields['__EVENTARGUMENT'] = cfg.submitEventArgument;
    } else if (cfg.submitField.isNotEmpty) {
      fields[cfg.submitField] = cfg.submitValue;
    }
    fields.addAll(cfg.extraFields);

    final result = await post(_resolve(cfg.path), fields);

    for (final needle in cfg.failureMarkers) {
      if (result.html.contains(needle)) {
        throw LoginFailed('登入失敗：頁面出現「$needle」。');
      }
    }

    // 登入成功時伺服器**不回 302**，而是回一頁 JS：
    //     top.location.href = 'MainFrame.aspx'
    // 成功的回應長得跟登入頁幾乎一樣（22101B vs 21988B），只差這一行，
    // 所以判斷成功要看導向、不能找「登出」這種字串。
    //
    // 登入失敗會重畫登入頁，那頁帶的是 location.href='DefaultQ.aspx'（排隊頁）。
    // 不排掉的話會把「失敗」誤判成「成功」。
    final target = jsRedirectTarget(result.html);
    final dest = _progressTarget(target, cfg);

    if (dest != null) {
      log?.call('  登入成功，跟隨 JS 導向 -> $dest');
      return get(dest);
    }

    if (cfg.successMarkers.any(result.html.contains)) return result;

    // diagnostics 只有「形狀」，沒有內容 —— 足夠分辨「驗證碼打錯」和
    // 「學校改版了」，但不含任何一個 byte 的頁面文字。
    throw LoginFailed(
      '登入沒有成功。這個系統失敗時不會給訊息，只會重畫登入頁配一張新驗證碼，'
      '所以最可能是驗證碼或密碼打錯了。',
      diagnostics:
          'status=${result.status} len=${result.html.length} redirect=${target ?? "none"}',
    );
  }

  /// 導向目標代不代表「登入有進展」。回到登入頁或排隊頁都不算。
  static String? _progressTarget(String? target, LoginConfig cfg) {
    if (target == null) return null;
    final bare = target.replaceAll(RegExp(r'^[./]+'), '');
    final notProgress = {cfg.queuePath ?? 'DefaultQ.aspx', cfg.path};
    return notProgress.contains(bare) ? null : target;
  }

  // ---------- session 狀態 ----------

  /// 這一頁是不是（被踢回的）登入頁。
  bool isLoginPage(AisPage page) => loginMarkers.every(page.html.contains);

  /// 「系統同時一次僅許可一個帳號登入，你已登入過系統」。
  ///
  /// 這個系統**每個帳號同時只能有一個 session**。舊 session 沒登出就再登入，
  /// 所有功能頁都會被導到 `ConfirmInOrOut.aspx`，而且是 200 —— 看起來像正常回應。
  static bool isSessionConflict(AisPage page) =>
      page.url.contains('ConfirmInOrOut.aspx') ||
      page.html.contains('僅許可一個帳號登入');

  /// 抓到登入頁或重複登入警告就直接停。
  ///
  /// 不擋的話，後面每一頁都會拿到同一份登入頁 HTML，parser 解出 0 筆，
  /// 然後你會跑去 debug 錯的東西。
  AisPage checkSession(AisPage page) {
    if (isSessionConflict(page)) {
      throw SessionExpired(
        '這個帳號目前在別的地方登入著。學校系統一次只允許一個登入 ——\n'
        '請先在瀏覽器上正常登出，或等幾分鐘讓那個 session 逾時，再回來重試。',
        page: page,
      );
    }
    if (isLoginPage(page)) {
      throw SessionExpired('登入逾時了，請重新登入。', page: page);
    }
    return page;
  }

  /// 載入落地頁的所有 frame，像瀏覽器一樣。
  ///
  /// **不做這件事，功能頁一律被擋。** `MainFrame.aspx` 是 frameset，
  /// 瀏覽器載完它會接著載四個 frame（title / MenuTree / portal / timeout）。
  /// 登入後直接跳去功能頁等於握手只做一半，會被導到 `ConfirmInOrOut.aspx`，
  /// 而那個訊息（「一次僅許可一個帳號登入」）會把人帶往完全錯誤的方向。
  Future<List<AisPage>> enterPortal(AisPage page) async {
    final loaded = <AisPage>[];
    for (final dest in frameSources(page, _base)) {
      try {
        loaded.add(await get(dest.toString()));
      } on AisException catch (e) {
        // 少載一個 frame 通常還是能過握手，不值得讓整次登入失敗
        log?.call('  frame ${dest.path} 載入失敗（${e.runtimeType}），繼續');
      }
    }
    return loaded;
  }

  /// 挑出要跟著載的 frame。
  ///
  /// 抽出來是為了能單獨測 —— 這段的每一個分支都對應到實際頁面上的某個東西：
  /// `viewIFrame` / `actionIFrame` 沒有 `src`、`timerIFrame` 是 `about:blank`、
  /// `titleIFrame` 的網址裡有個**空格**（`title.aspx?XX= 1908128636`）。
  static List<Uri> frameSources(AisPage page, Uri base) {
    final pageUri = Uri.parse(page.url);
    final out = <Uri>[];
    final frames = [
      ...page.doc.querySelectorAll('frame'),
      ...page.doc.querySelectorAll('iframe'),
    ];
    for (final frame in frames) {
      final src = frame.attributes['src']?.trim();
      if (src == null || src.isEmpty) continue;
      final lower = src.toLowerCase();
      if (lower.startsWith('about:') || lower.startsWith('javascript:')) continue;

      final Uri dest;
      try {
        dest = pageUri.resolve(src);
      } on FormatException {
        continue; // 解不出來的 src 就跳過，不要讓整次登入失敗
      }
      if (!sameOrigin(dest, base)) continue;
      out.add(dest);
    }
    return out;
  }

  /// 一路跟著 JS 導向走到真正有內容的頁面。
  ///
  /// `Application/…/XXXX_.aspx?progcd=…` 這種選單連結只是派發器，
  /// 直接 GET 會拿到 1.4KB 空殼，真正的內容在它導向的 `XXXX_01.aspx`。
  Future<AisPage> followJsRedirect(AisPage page, {int maxHops = 3}) async {
    final seen = <String>{page.url};
    var current = page;

    for (var i = 0; i < maxHops; i++) {
      final target = jsRedirectTarget(current.html);
      if (target == null) break;

      final dest = Uri.parse(current.url).resolve(target);
      if (!sameOrigin(dest, _base)) {
        // 校方在 MenuTree.aspx 少打一條斜線，`//portal.aspx` 會解析成站外主機。
        // 跟下去等於把帶著 session cookie 的請求送給任何人都能註冊的網域。
        log?.call('  跳過站外導向：$target');
        break;
      }
      if (seen.contains(dest.toString())) break;

      // 導回登入頁 = session 有問題。再跟下去只會走到 ConfirmInOrOut，
      // 停在這裡，讓 checkSession 報出真正的原因。
      final destPath = pathOf(dest.toString()).toLowerCase();
      if (isLoginPage(current) ||
          destPath.startsWith('default.aspx') ||
          destPath.startsWith('defaultq.aspx')) {
        break;
      }

      seen.add(dest.toString());
      log?.call('  跟隨 JS 導向 -> $target');
      current = await get(dest.toString());
    }
    return current;
  }

  /// 登出。**每次用完都要做。**
  ///
  /// `LogOut.aspx` 跟這個系統其他地方一樣**只是派發器**，只回 48 bytes：
  /// ```html
  /// <script>top.location.href='Logout.htm';</script>
  /// ```
  /// 真正把 session 作廢的是它導向的頁面。只做 GET 不跟導向的話，
  /// 程式會顯示「已登出」但其實沒有 —— 然後 session 累積、下次登入被擋，
  /// 而症狀看起來完全是另一個問題。
  Future<void> logout() async {
    try {
      final page = await followJsRedirect(await get(config.logoutPath));
      log?.call('  已登出（最後停在 ${pathOf(page.url)}）');
    } on AisException catch (e) {
      log?.call('  登出失敗（${e.runtimeType}），下次登入可能會被擋');
    } finally {
      // 就算登出請求失敗，本機的 cookie 也要清掉 ——
      // 留著一組已經作廢的 session cookie，下次登入會拿它去試，症狀更難懂。
      await cookieJar.deleteAll();
      _hidden = <String, String>{};
      _lastUrl = '';
    }
  }

  String pathOf(String url) =>
      url.startsWith(config.baseUrl) ? url.substring(config.baseUrl.length) : url;
}

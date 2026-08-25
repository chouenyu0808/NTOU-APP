import 'dart:typed_data';

import '../ais/ais_session.dart';
import '../ais/exceptions.dart';
import '../ais/forms.dart';
import '../ais/page.dart';
import '../config/selectors.dart';
import '../parsing/models.dart';
import '../parsing/tables.dart';
import '../parsing/timetable.dart';
import '../storage/timetable_cache.dart';

/// 等使用者輸入的驗證碼。
class CaptchaChallenge {
  const CaptchaChallenge(this.image);

  final Uint8List image;
}

/// 查詢頁上可選的學年 / 學期。
class SemesterOptions {
  const SemesterOptions({
    required this.years,
    required this.semesters,
    required this.defaultYear,
    required this.defaultSemester,
  });

  final List<SelectOption> years;
  final List<SelectOption> semesters;
  final String defaultYear;
  final String defaultSemester;
}

/// 把 [AisSession]、parser 和快取接起來。UI 只跟這一層講話。
///
/// 這一層負責的是**順序**：登入握手要走完四個 frame、功能頁要跟完派發器導向、
/// 每一步都要 checkSession。少任何一步，症狀都是「回應正常但內容不對」，
/// 而且錯誤訊息會把人帶往完全錯誤的方向（見 spike/README 第八節）。
class AisRepository {
  AisRepository({required this.config, required this.cache, this.log});

  final SelectorConfig config;
  final TimetableCache cache;
  final AisLogger? log;

  AisSession? _session;

  /// `openLoginPage()` 的結果。驗證碼和 `__VIEWSTATE` 都綁在這一頁的 session 狀態上，
  /// 重抓一次頁面驗證碼就換了 —— 所以要原封不動留到 [completeLogin]。
  AisPage? _loginPage;

  /// 課表查詢表單的當前狀態。每次 postback 後 `__VIEWSTATE` 都會變，
  /// 所以換學期查詢時要用**上一次回應**當基底，不是重新開一次頁面。
  AisPage? _queryPage;

  bool get isLoggedIn => _session != null && _queryPage != null;

  // ---------- 登入 ----------

  /// 開登入頁、通過排隊關卡、抓驗證碼圖。
  ///
  /// 排隊那一步不能跳過：直接 GET 拿到的登入頁，驗證碼 `<img>` 沒有 `src`，
  /// 送出去只會得到「驗證碼錯誤」，而且你在頁面上找不到任何圖可以看。
  Future<CaptchaChallenge> beginLogin() async {
    await _session?.logout();
    final session = _session = AisSession(config: config, log: log);

    final page = _loginPage = await session.openLoginPage();
    final image = await session.fetchCaptcha(page);
    if (image == null) {
      throw const LoginFailed(
        '拿不到驗證碼圖片。學校系統可能正在維護，或是登入頁改版了。',
      );
    }
    return CaptchaChallenge(image);
  }

  /// 送出登入，然後**走完瀏覽器會做的握手**：載入 MainFrame 的四個 frame、
  /// 開啟課表查詢頁、跟完派發器導向。
  ///
  /// 全部做完才算登入成功 —— 只有 POST 成功但沒載 frame 的話，
  /// 後面每一個功能頁都會被導到 `ConfirmInOrOut.aspx`，
  /// 錯誤訊息還會宣稱「一次僅許可一個帳號登入」，把人帶去查錯的方向。
  Future<SemesterOptions> completeLogin({
    required String username,
    required String password,
    required String captcha,
  }) async {
    final session = _session;
    final loginPage = _loginPage;
    if (session == null || loginPage == null) {
      throw const LoginFailed('登入流程沒有開始，請重新整理登入頁。');
    }

    final landing = await session.login(
      page: loginPage,
      username: username,
      password: password,
      captcha: captcha,
    );
    // 用完就丟。這一頁本身沒有密碼（密碼在 login() 內部的回應裡，已經回收了），
    // 但留著它只會讓過期的 __VIEWSTATE 有機會被誤用。
    _loginPage = null;

    await session.enterPortal(landing);
    return _openQueryPage(session);
  }

  /// 開課表查詢頁。
  Future<SemesterOptions> _openQueryPage(AisSession session) async {
    // 選單給的路徑是**派發器**，不是內容頁。直接 GET 只會拿到 1.4KB 空殼，
    // 真正的表單在它導向的 `TKE2240_01.aspx`。
    var page = await session.get(config.timetable.path);
    page = await session.followJsRedirect(page);
    session.checkSession(page);
    _queryPage = page;

    final t = config.timetable;
    final years = selectOptions(page.doc, t.yearField);
    final semesters = selectOptions(page.doc, t.semesterField);
    if (years.isEmpty || semesters.isEmpty) {
      throw const SessionExpired(
        '打不開課表查詢頁 —— 頁面上找不到學年學期的選單。'
        '多半是學校改版了，App 需要更新。',
      );
    }
    return SemesterOptions(
      years: years,
      semesters: semesters,
      defaultYear: selectedOption(page.doc, t.yearField) ?? years.first.value,
      defaultSemester:
          selectedOption(page.doc, t.semesterField) ?? semesters.first.value,
    );
  }

  // ---------- 課表 ----------

  /// 先給快取的，再去抓新的。
  ///
  /// 開 App 的第一秒就要看得到東西 —— 尤其是登入失敗的時候
  /// （帳號在別處登著、學校系統維護中），舊課表總比一片空白有用。
  Future<TimetableResult?> cached(String year, String semester) =>
      cache.read(year, semester);

  /// 查某個學期的選課清單。
  ///
  /// 用「選課清單」（`QUERY_BTN1`）而不是「選課課表」（`QUERY_BTN3`）：
  /// 後者掛在 Crystal Reports 上，輸出格式沒驗證過。
  Future<TimetableResult> fetchTimetable({
    required String year,
    required String semester,
  }) async {
    final session = _session;
    final page = _queryPage;
    if (session == null || page == null) {
      throw const SessionExpired('還沒登入，請先登入。');
    }

    final t = config.timetable;
    final result = await session.submitForm(
      page,
      t.listButton,
      values: {t.yearField: year, t.semesterField: semester},
    );
    session.checkSession(result);

    // 回應本身也是一份完整的查詢表單（帶著新的 __VIEWSTATE），
    // 下一次換學期就用它當基底。
    _queryPage = result;

    final empty = isEmptyResult(result.html);
    final out = TimetableResult(
      year: year,
      semester: semester,
      // 「查無符合資料」時不要再去 parse —— 那頁的 DataGrid 是空的，
      // parse 出 0 筆會跟「parser 壞了」長得一模一樣。
      courses: empty ? const [] : parseCourseList(result.html),
      columns: empty ? const [] : courseListColumns(result.html),
      isEmpty: empty,
      fetchedAt: DateTime.now(),
    );

    await cache.write(out);
    return out;
  }

  /// 登出並清掉 session。**App 進背景或使用者離開時一定要做** ——
  /// 學校系統一個帳號只允許一個 session，沒登出的話使用者下次
  /// 在瀏覽器登入會被自己的 App 擋住。
  Future<void> logout({bool forgetCache = false}) async {
    await _session?.logout();
    _session = null;
    _loginPage = null;
    _queryPage = null;
    if (forgetCache) await cache.clear();
  }

  /// session 被判定失效時呼叫，讓下一次操作重新走登入流程。
  void invalidateSession() {
    _session = null;
    _loginPage = null;
    _queryPage = null;
  }
}

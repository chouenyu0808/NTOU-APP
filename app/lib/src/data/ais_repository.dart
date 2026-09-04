import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../ais/ais_session.dart';
import '../ais/exceptions.dart';
import '../ais/form_schema.dart';
import '../ais/forms.dart';
import '../ais/page.dart';
import '../config/selectors.dart';
import '../menu/menu_catalog.dart';
import '../parsing/announcements.dart';
import '../parsing/models.dart';
import '../parsing/data_grid.dart';
import '../parsing/tables.dart';
import '../parsing/timetable.dart';
import '../storage/timetable_cache.dart';
import 'function_view.dart';

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
  AisRepository({
    required this.config,
    required this.cache,
    this.log,
    this.dio,
  });

  final SelectorConfig config;
  final TimetableCache cache;
  final AisLogger? log;

  /// 注入用的 HTTP client。正式執行時是 null（[AisSession] 自己建一個）。
  ///
  /// 存在的理由是測試：widget test 裡的 HttpClient 是被擋住的，而且節流用的
  /// 計時器會在測試結束時還掛著 —— 那會讓測試以「Pending timers」失敗，
  /// 訊息完全看不出跟登入有關。有這個接縫，測試就能跑**真正的程式路徑**，
  /// 而不是靠一堆「測試時不要做這件事」的旗標繞過去。
  final Dio? dio;

  AisSession? _session;

  /// `openLoginPage()` 的結果。驗證碼和 `__VIEWSTATE` 都綁在這一頁的 session 狀態上，
  /// 重抓一次頁面驗證碼就換了 —— 所以要原封不動留到 [completeLogin]。
  AisPage? _loginPage;

  /// 課表查詢表單的當前狀態。每次 postback 後 `__VIEWSTATE` 都會變，
  /// 所以換學期查詢時要用**上一次回應**當基底，不是重新開一次頁面。
  AisPage? _queryPage;

  bool get isLoggedIn => _session != null && _queryPage != null;

  /// 登入握手時順便讀到的電子公布欄。沒登入過就是空的。
  List<Announcement> get announcements => _announcements;
  List<Announcement> _announcements = const [];

  /// 四個 frame 裡哪一頁有公布欄，交給 parser 自己說 ——
  /// 用檔名或順序去猜，學校調整 frame 就會壞。
  static List<Announcement> _pickAnnouncements(List<AisPage> frames) {
    for (final page in frames) {
      final found = parseAnnouncements(page.html);
      if (found.isNotEmpty) return found;
    }
    return const [];
  }

  // ---------- 登入 ----------

  /// 開登入頁、通過排隊關卡、抓驗證碼圖。
  ///
  /// 排隊那一步不能跳過：直接 GET 拿到的登入頁，驗證碼 `<img>` 沒有 `src`，
  /// 送出去只會得到「驗證碼錯誤」，而且你在頁面上找不到任何圖可以看。
  Future<CaptchaChallenge> beginLogin() async {
    await _session?.logout();
    final session = _session = AisSession(config: config, log: log, dio: dio);

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

    // 入口頁的四個 frame 裡就有電子公布欄 —— **順便讀走**。
    // 選單裡雖然有「電子公布欄 > 公告訊息查詢」，但為了首頁那幾則去開那一頁
    // 等於多打一次學校的伺服器，而資料已經在手上了。
    _announcements = _pickAnnouncements(await session.enterPortal(landing));

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

  /// 查某個學期的課表。
  ///
  /// **要送兩顆按鈕，因為沒有任何一頁給得齊。**
  ///   - 「選課清單」（`QUERY_BTN1`）：16 欄有學分、選別、授課老師、人數，
  ///     但**一欄時間都沒有**（2026-09-03 對真實頁面逐欄看過）。
  ///   - 「選課課表」（`QUERY_BTN3`）：畫成格子，有星期、節次和教室，
  ///     但沒有學分也沒有老師。
  ///
  /// 兩邊靠**課號**合併。不用班別：格子裡寫 `1A`、清單裡寫 `1年A班`。
  ///
  /// 早期的註解說 `QUERY_BTN3` 掛在 Crystal Reports 上、輸出格式未驗證，
  /// 所以只用清單 —— 那是還沒抓過真實頁面時的推測。實際上它回的是一張
  /// 普通的 HTML 表格（`<table id='table2'>`）。
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
    // 「查無符合資料」時不要再去 parse —— 那頁的 DataGrid 是空的，
    // parse 出 0 筆會跟「parser 壞了」長得一模一樣。
    var courses = empty ? const <Course>[] : parseCourseList(result.html);

    // 沒有課就不必再問一次課表 —— 省一次請求，選課尖峰時每一次都算。
    if (courses.isNotEmpty) {
      courses = await _withSlots(session, courses, year, semester);
    }

    final out = TimetableResult(
      year: year,
      semester: semester,
      courses: courses,
      columns: empty ? const [] : courseListColumns(result.html),
      isEmpty: empty,
      fetchedAt: DateTime.now(),
    );

    await cache.write(out);
    return out;
  }

  /// 送「選課課表」，把星期節次和教室併回課程清單。
  ///
  /// **這一步可以失敗。** 抓不到時間的課表仍然是有用的東西（清單、學分、
  /// 老師都在），所以任何錯誤都只是「這次沒有時間」，不該讓整張課表變成
  /// 一個錯誤畫面。學校那邊改版時尤其是這樣 —— 使用者至少還看得到修了什麼。
  Future<List<Course>> _withSlots(
    AisSession session,
    List<Course> courses,
    String year,
    String semester,
  ) async {
    final t = config.timetable;
    try {
      final page = await session.submitForm(
        _queryPage!,
        t.timetableButton,
        values: {t.yearField: year, t.semesterField: semester},
      );
      session.checkSession(page);
      // 這一份帶著更新過的 __VIEWSTATE，下次換學期用它當基底。
      _queryPage = page;

      final grid = parseEnrolledGrid(page.html);
      if (grid.isEmpty) return courses;

      return [
        for (final c in courses)
          if (grid[c.code] case final g?)
            c.copyWith(
              slots: g.slots,
              // 教室只有格子裡有；清單那 16 欄沒有這一欄。
              room: g.room.isEmpty ? null : g.room,
            )
          else
            c,
      ];
    } on AisException catch (e) {
      log?.call('  選課課表抓取失敗（${e.runtimeType}），只顯示清單');
      return courses;
    }
  }

  // ---------- 通用功能頁 ----------

  /// 手機上一頁 10 筆幾乎沒用，送出時把 `PC$PageSize` 調大。
  ///
  /// 不調到上限（欄位允許到 100000）是刻意的：查詢結果是全校範圍的話，
  /// 一次拉幾千列只是把學校的機器和手機的記憶體一起拖垮。
  static const int _pageSize = 100;

  /// 打開一個功能頁。
  ///
  /// 選單給的路徑是**派發器**，GET 完只會拿到 1.4KB 空殼，要跟完 JS 導向
  /// 才會到真正的表單頁。
  Future<FunctionView> openFunction(AisFunction fn) async {
    final session = _requireSession();
    var page = await session.get(fn.path);
    page = await session.followJsRedirect(page);
    session.checkSession(page);

    final schema = FunctionSchema.fromPage(page);
    return FunctionView(
      function: fn,
      page: page,
      schema: schema,
      cascadeFields: AisSession.autoPostBackFields(page),
      values: {for (final f in schema.visibleFields) f.name: f.value},
    );
  }

  /// 改了一個連動欄位：重送整張表單，讓伺服器把下游的下拉填好。
  ///
  /// 不做這件事，下游的 `<select>` 會一直是 0 個 option，
  /// 而那種欄位送出去只會得到一句看不懂的 403。
  Future<FunctionView> cascade(
    FunctionView view,
    String field,
    String value,
  ) async {
    final session = _requireSession();
    final values = {...view.values, field: value};
    // 只送得出去的那些。**這裡漏掉過一次**：連動 postback 如果把 0 個選項的
    // 下拉也一起送，會被 event validation 擋下來 —— 而使用者看到的是
    // 「某個他根本沒碰過的欄位不是合法選項」，完全不知道發生什麼事。
    final sendable = _sendable(view, values);
    final page = await session.postback(
      view.page,
      field,
      values: sendable.values,
      omit: sendable.omit,
    );
    session.checkSession(page);

    final schema = FunctionSchema.fromPage(page);
    return view.copyWith(
      page: page,
      schema: schema,
      cascadeFields: AisSession.autoPostBackFields(page),
      // 伺服器可能重填了下游的選項，所以值要以回應為準，不是以使用者填的為準
      values: {
        for (final f in schema.visibleFields)
          f.name: values[f.name] ?? f.value,
      },
      clearResult: true,
    );
  }

  /// 按下某顆查詢按鈕。
  Future<FunctionView> runQuery(
    FunctionView view,
    String button, {
    Map<String, String>? values,
    int? pageNo,
    int? tabIndex,
    Map<String, String>? extra,
  }) async {
    final session = _requireSession();
    final merged = {...view.values, ...?values};
    final sendable = _sendable(view, merged);
    final fields = sendable.values;
    fields['PC\$PageSize'] = '$_pageSize';
    if (pageNo != null) fields['PC\$PageNo'] = '$pageNo';

    // 分頁式的頁面靠這個欄位決定用哪一組條件。差一個就會拿別組的空欄位去查，
    // 而回應是「查無符合資料」—— 看起來像沒資料，其實是問錯問題。
    if (tabIndex != null) fields['hdnSelectedTab'] = '$tabIndex';

    // [extra] 走 `_sendable` 之後才加：呼叫端要蓋掉頁面預設值的那幾顆
    // （例如「用課號還是課名查」）不一定進得了 schema。
    if (extra != null) fields.addAll(extra);

    final page = await session.submitForm(
      view.page,
      button,
      values: fields,
      // 明確指定的值優先於「拿掉」—— extra 蓋上去的不該又被 omit 掉。
      omit: sendable.omit.difference(fields.keys.toSet()),
    );
    session.checkSession(page);

    // 一頁可能有不只一張結果表格（線上加退選：可加選的課 + 已選上的課）。
    final grids = parseDataGrids(page.html);
    return view.copyWith(
      page: page,
      schema: FunctionSchema.fromPage(page),
      cascadeFields: AisSession.autoPostBackFields(page),
      values: merged,
      result: grids.isEmpty ? null : grids.first,
      extraResults: grids.skip(1).toList(),
    );
  }

  // ---------- 課程查詢 ----------

  /// 打開課程查詢頁。
  Future<FunctionView> openCourseSearch() async {
    final session = _requireSession();
    var page = await session.get(config.courseSearch.path);
    page = await session.followJsRedirect(page);
    session.checkSession(page);

    final schema = FunctionSchema.fromPage(page);
    return FunctionView(
      // Course search is not in the normal function list we fetch dynamically. We create a dummy AisFunction.
      function: AisFunction(
        title: '課程課表查詢',
        path: config.courseSearch.path,
        trail: ['教務系統', '選課系統', '課程課表查詢'],
      ),
      page: page,
      schema: schema,
      cascadeFields: AisSession.autoPostBackFields(page),
      values: {for (final f in schema.visibleFields) f.name: f.value},
    );
  }

  /// 用課名關鍵字搜尋課程
  Future<FunctionView> searchCourseByName(
    FunctionView view,
    String keyword,
  ) async {
    final t = config.courseSearch.lessonNameTab;
    return runQuery(
      view,
      t.button,
      values: {t.nameField: keyword},
      tabIndex: 1, // 關鍵字查詢是第二個標籤頁
      // **一定要指定這兩顆，不能用頁面的預設值。**
      // 頁面預設是「類別=課號、查詢模式=精準」——
      // 拿「微積分」去做課號的精準比對，永遠是「查無符合資料」，
      // 而畫面上看起來就像這門課不存在。
      extra: {t.classField: t.byName, t.modeField: t.fuzzy},
    );
  }

  /// 用系所搜尋課程
  Future<FunctionView> searchCourseByFaculty(
    FunctionView view,
    String degree,
    String faculty,
    String grade,
    String classId,
  ) async {
    final t = config.courseSearch.facultyTab;
    return runQuery(
      view,
      t.button,
      values: {
        t.degreeField: degree,
        t.facultyField: faculty,
        t.gradeField: grade,
        t.classField: classId,
      },
      tabIndex: 0, // faculty is index 0
    );
  }

  /// 點課號進課程詳細頁，把上課時間和上課地點抓回來。
  ///
  /// [eventTarget] 是那一列課號連結上的 `__doPostBack` 目標，
  /// 用 [courseDetailTarget] 從查詢結果讀出來 —— **不要自己組**，
  /// 那串 id 是 ASP.NET 依列數編的（`DataGrid$ctl02$COSID`）。
  ///
  /// **回 null 是「沒問到」，回一筆沒有時段的是「學校說這門課沒排時間」。**
  /// 兩者一定要分得開：前者重問會有答案，而把它當成後者存進表裡的話，
  /// 那門課就永遠停在「查不到上課時間」了。
  ///
  /// 抓不到就回 null。**這件事必須是可以失敗的**：使用者要的是
  /// 「把課加進預排」，時間抓不到頂多回頭手動填，不該讓整個動作失敗。
  Future<CourseDetail?> fetchCourseDetail(
    FunctionView view,
    String eventTarget,
  ) async {
    final session = _requireSession();
    final sendable = _sendable(view, view.values);
    final posted = await session.postback(
      view.page,
      eventTarget,
      values: sendable.values,
      omit: sendable.omit,
    );
    session.checkSession(posted);

    // 點課號**不會換頁**，回應只多注入一行 `fn_open('<PKNO>','<型別>')`。
    // 內容在它指的那一頁 —— 見 [courseDetailUrl]。
    final detail = courseDetailUrl(posted.html);
    if (detail == null) return null;

    // **不要跟 JS 導向。** 課程內容頁自己帶著一行指向 `/Portal.aspx` 的 script，
    // 跟下去會把剛拿到的 57KB 內容整份換成首頁 —— 而且不會報錯，
    // 症狀只是「這門課沒有上課時間」，你會跑去查 parser。
    final page = await session.get(detail);
    session.checkSession(page);

    final parsed = parseCourseDetail(page.html);
    // 每一格都是空的 —— 那是 PKNO 不對時回的空殼，不是「這門課沒排時間」。
    return parsed.isBlank ? null : parsed;
  }

  /// 按下結果表格某一列上的鈕（加選 / 退選 / 詳）。
  ///
  /// [target] 一定要是 [RowAction.target] 讀出來的 —— **不要自己組**。
  /// 那串 id 是 ASP.NET 依 DataGrid 的列數編的，而我們濾掉了分頁列和合計列，
  /// 畫面上的第幾列跟它的列號對不起來。
  ///
  /// **會改資料的鈕（加選 / 退選）由呼叫端負責先問過使用者。** 這裡只送。
  ///
  /// 學校那邊的鈕上還掛著一段 `doAddClick(...)` 前端驗證，我們沒有重現它 ——
  /// 真正的把關在伺服器，擋下來的話回應會帶著訊息。所以送出後照樣把整頁
  /// 重新解析回來，讓使用者看到學校說了什麼。
  Future<FunctionView> runRowAction(FunctionView view, String target) async {
    final session = _requireSession();
    final sendable = _sendable(view, view.values);
    final page = await session.postback(
      view.page,
      target,
      values: sendable.values,
      omit: sendable.omit,
    );
    session.checkSession(page);

    final schema = FunctionSchema.fromPage(page);
    // 一頁可能有不只一張結果表格（線上加退選：可加選的課 + 已選上的課）。
    final grids = parseDataGrids(page.html);
    return view.copyWith(
      page: page,
      schema: schema,
      cascadeFields: AisSession.autoPostBackFields(page),
      values: {
        for (final f in schema.visibleFields) f.name: f.value,
      },
      result: grids.isEmpty ? null : grids.first,
      extraResults: grids.skip(1).toList(),
    );
  }

  /// 打開「查詢必修科目表」。
  ///
  /// 這一頁沒有專屬的解析 —— 表單欄位（入學年度、部別、系所、入學身分）
  /// 全部由 `FunctionSchema` 從頁面自己的宣告讀出來，跟通用功能頁同一套。
  /// 學校加一個查詢條件，這裡自動就多一個下拉。
  Future<FunctionView> openRequiredCourses() => openFunction(
        AisFunction(
          title: '查詢必修科目表',
          path: config.requiredCoursesPath,
          trail: const ['教務系統', '選課系統', '查詢必修科目表'],
        ),
      );

  /// 送出去的欄位，加上**要從基底裡拿掉**的那些。
  ///
  /// 為什麼需要 [omit]：`submitForm` 是先用頁面上的現值當基底，再把這裡的值
  /// 蓋上去（`fields.addAll(values)`）。蓋得上去、拿不掉 —— 而使用者把一個
  /// 原本打勾的 checkbox 取消掉，正是「要拿掉」。少了這條路，取消勾選在
  /// 送出時完全不會發生。
  ///
  /// 被濾掉的：
  ///   - **0 個 option 的下拉。** 瀏覽器根本不送它；我們送空字串會被 ASP.NET 的
  ///     event validation 判定「這不是我渲染出來的值」而拋例外。
  ///   - **`disabled` 的欄位。** 瀏覽器不送 disabled 的東西。照樣送輕則被
  ///     event validation 擋成一句看不懂的 403，重則真的寫進一個使用者
  ///     不該改的欄位（性別、學生類別那一類）。
  ///   - **檔案欄位。** App 還不能上傳，送一個假值只會讓伺服器困惑。
  ///   - 頁面上沒有的欄位。切換標籤頁之後，上一組的欄位可能已經不在了。
  static ({Map<String, String> values, Set<String> omit}) _sendable(
    FunctionView view,
    Map<String, String> values,
  ) {
    final out = <String, String>{};
    final omit = <String>{};

    for (final f in view.schema.fields) {
      if (f.needsCascade || f.readOnly || f.kind == FieldKind.file) continue;
      final v = values[f.name];
      if (v == null) continue;

      switch (f.kind) {
        // 複選群組在 schema 裡是**一個**欄位，送出時要展開成各自的
        // `群組$N`。勾起來的送 `on`（瀏覽器就是送這個字），沒勾的
        // 完全不送 —— 而且要主動從基底裡拿掉。
        case FieldKind.checkboxes:
          final checked = SchemaField.splitChecked(v).toSet();
          for (final o in f.options) {
            if (checked.contains(o.value)) {
              out[o.value] = 'on';
            } else {
              omit.add(o.value);
            }
          }

        // 單選：送選中的那個值。一個都沒選就整個欄位不送。
        case FieldKind.radio:
          if (v.isEmpty) {
            omit.add(f.name);
          } else {
            out[f.name] = v;
          }

        default:
          out[f.name] = v;
      }
    }
    return (values: out, omit: omit);
  }

  AisSession _requireSession() {
    final s = _session;
    if (s == null) throw const SessionExpired('還沒登入，請先登入。');
    return s;
  }

  /// 登出並清掉 session。**App 進背景或使用者離開時一定要做** ——
  /// 學校系統一個帳號只允許一個 session，沒登出的話使用者下次
  /// 在瀏覽器登入會被自己的 App 擋住。
  Future<void> logout({bool forgetCache = false}) async {
    await _session?.logout();
    _session = null;
    _loginPage = null;
    _queryPage = null;
    _announcements = const [];
    if (forgetCache) await cache.clear();
  }

  /// session 被判定失效時呼叫，讓下一次操作重新走登入流程。
  void invalidateSession() {
    _session = null;
    _loginPage = null;
    _queryPage = null;
  }
}

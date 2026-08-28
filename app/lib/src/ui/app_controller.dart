import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ais/exceptions.dart';
import '../ais/forms.dart';
import '../data/ais_repository.dart';
import '../data/academic_calendar_source.dart';
import '../parsing/academic_calendar.dart';
import '../parsing/announcements.dart';
import '../parsing/models.dart';
import '../storage/credential_store.dart';

enum AppPhase {
  /// 讀本機資料中（學號、上次看的學期、快取課表）。
  starting,

  /// 沒有有效的 session。畫面上是登入表單。
  loggedOut,

  /// 正在開登入頁 + 通過排隊關卡 + 抓驗證碼。
  openingLogin,

  /// 驗證碼已經拿到，等使用者輸入。
  awaitingCaptcha,

  /// 送出登入 + 走完 frame 握手。
  loggingIn,

  /// 登入完成，可以查課表。
  ready,
}

/// 整個 App 的狀態。
///
/// 只有一個 controller 而不是分成登入／課表兩個，是因為這兩件事本來就綁死：
/// 學年學期的選項來自登入後才打得開的查詢頁，而 session 一失效就要退回登入。
/// 拆開只會多出一堆同步兩邊狀態的程式碼。
class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.credentials,
    AcademicCalendarSource? calendar,
  }) : calendar = calendar ?? AcademicCalendarSource();

  final AisRepository repository;
  final CredentialStore credentials;

  /// 校園行事曆。**不是 AIS 的東西** —— 學校官網的公開頁面，不用登入。
  final AcademicCalendarSource calendar;

  AppPhase phase = AppPhase.starting;

  /// 顯示給使用者的錯誤。**永遠是一句人話**，不是例外的 toString。
  String? error;

  Uint8List? captcha;

  String username = '';

  /// 有沒有存過密碼。有的話登入表單預先勾起來、密碼欄自動填。
  bool hasSavedPassword = false;

  List<SelectOption> years = const [];
  List<SelectOption> semesters = const [];
  String? year;
  String? semester;

  TimetableResult? timetable;

  /// 電子公布欄。登入握手時順便讀到的，不是另外打一次伺服器換來的。
  List<Announcement> announcements = const [];

  /// 校園行事曆。跟登入無關，開 App 就有。
  List<CalendarEvent> calendarEvents = const [];

  /// 現在顯示的是快取，還沒跟學校核對過。
  bool showingCache = false;

  bool loadingTimetable = false;

  // ---------- 啟動 ----------

  Future<void> init() async {
    username = await credentials.readUsername() ?? '';
    hasSavedPassword = (await credentials.readPassword()) != null;

    // 先把上次看的課表畫出來。**登入之前就要有東西看** ——
    // 學校系統一次只允許一個 session，使用者在電腦上開著選課系統時
    // App 一定登不進去，那時候舊課表是唯一有用的東西。
    final last = await repository.cache.lastViewed();
    if (last != null) {
      year = last.year;
      semester = last.semester;
      timetable = await repository.cached(last.year, last.semester);
      showingCache = timetable != null;
    }

    phase = AppPhase.loggedOut;
    notifyListeners();

    // 行事曆放在最後，而且**不 await 進主流程**：它要打外部網站，慢或掛掉
    // 都不該讓 App 開機卡住。抓到了再 notify 一次，那一區自己長出來。
    unawaited(_loadCalendar());
  }

  Future<void> _loadCalendar() async {
    final events = await calendar.load();
    if (events.isEmpty) return;
    calendarEvents = events;
    notifyListeners();
  }

  // ---------- 登入 ----------

  /// 開登入頁、通過排隊、抓驗證碼。
  Future<void> startLogin() async {
    phase = AppPhase.openingLogin;
    error = null;
    captcha = null;
    notifyListeners();

    await _guard(() async {
      final challenge = await repository.beginLogin();
      captcha = challenge.image;
      phase = AppPhase.awaitingCaptcha;
    }, onFailure: () async => phase = AppPhase.loggedOut);
  }

  /// 送出登入。成功之後直接查一次課表。
  ///
  /// [password] **只在這個方法的生命週期內存在**。不放進欄位、不放進 log、
  /// 不放進錯誤訊息 —— 校方系統會把它明文回吐在登入回應裡，
  /// 任何一條讓它逃出這個方法的路徑，最後都會通到崩潰回報。
  Future<void> submitLogin({
    required String account,
    required String password,
    required String captchaText,
    required bool remember,
  }) async {
    phase = AppPhase.loggingIn;
    error = null;
    notifyListeners();

    final ok = await _guard(() async {
      final options = await repository.completeLogin(
        username: account,
        password: password,
        captcha: captchaText,
      );

      // 換帳號了：把上一個人的課表快取整個丟掉。
      //
      // 快取平常是刻意留著的（學校一次只允許一個 session，帳號在瀏覽器登著
      // 的時候那是唯一看得到的東西），登出也留 —— 登出對話框就是這樣講的。
      // 但那個理由只在「同一個人」時成立。同一支手機換一個學號登入，
      // 舊的課表會一路留到第一次查詢回來為止，中間他看到的是別人的課。
      if (username.isNotEmpty && username != account) {
        await repository.cache.clear();
        timetable = null;
        showingCache = false;
        // 學年學期也要放掉 —— 那是上一個人選的，新的人要用他自己的預設值。
        year = null;
        semester = null;
      }

      username = account;
      await credentials.saveUsername(account);
      if (remember) {
        await credentials.savePassword(password);
        hasSavedPassword = true;
      } else {
        await credentials.clearPassword();
        hasSavedPassword = false;
      }

      years = options.years;
      semesters = options.semesters;
      year ??= options.defaultYear;
      semester ??= options.defaultSemester;
      announcements = repository.announcements;
      captcha = null;
      phase = AppPhase.ready;
    }, onFailure: () async => phase = AppPhase.loggedOut);

    if (ok) {
      await refreshTimetable();
      return;
    }

    // 驗證碼是一次性的：送出去之後那張圖就作廢了，不管成功失敗。
    // 不自動換一張的話，使用者會盯著一張**永遠打不對的圖**重試，
    // 而畫面上完全看不出來為什麼。
    //
    // 失敗的原因要留著 —— startLogin() 會清掉 error，但那句話正是
    // 使用者現在最需要看到的東西。
    final reason = error;
    await startLogin();
    if (phase == AppPhase.awaitingCaptcha && reason != null) {
      error = reason;
      notifyListeners();
    }
  }

  /// 讀存起來的密碼。UI 用它自動填密碼欄。
  ///
  /// 回傳值直接交給 `TextEditingController`，不留在 controller 的欄位裡。
  Future<String?> savedPassword() => credentials.readPassword();

  /// 使用者中途離開登入頁時呼叫。
  ///
  /// [beginLogin] 一開始就在學校那端開了一個 session（排隊、拿驗證碼都需要）。
  /// 使用者按返回鍵走掉的話，那個 session 會**一直掛著**，
  /// 然後擋住他自己在瀏覽器登入 —— 而他完全不會聯想到是剛才那次放棄的登入造成的。
  Future<void> abandonLogin() async {
    if (phase == AppPhase.ready) return; // 登入成功後的正常關閉，不要動它
    captcha = null;
    phase = AppPhase.loggedOut;
    await repository.logout();
  }

  /// 進背景多久之後才登出。
  ///
  /// 一開始是「一離開前景就登出」，因為學校系統一個帳號只能有一個 session，
  /// App 掛著的那個會擋住使用者自己在瀏覽器登入。但那樣切出去看一眼訊息再回來
  /// 就要重打一次驗證碼，太煩了。給兩分鐘的緩衝。
  static const Duration backgroundGrace = Duration(minutes: 2);

  Timer? _logoutTimer;
  DateTime? _pausedAt;

  /// App 進背景。
  ///
  /// **計時器不保證會跑到** —— Android 會凍結背景的 App，被凍住的 isolate
  /// 不會執行 Timer。所以這裡只是「能跑就跑」，真正一定會發生的那道防線在
  /// [handleResumed]：回到前景時檢查實際經過多久。
  ///
  /// 兩道都沒跑到的情況（App 被系統直接殺掉）就只能靠學校自己的 session 逾時。
  void handlePaused() {
    if (phase != AppPhase.ready) return;
    _pausedAt = DateTime.now();
    _logoutTimer?.cancel();
    _logoutTimer = Timer(backgroundGrace, () => unawaited(_releaseSession()));
  }

  /// 回到前景。逾時就登出，沒逾時就把計時器取消掉繼續用。
  Future<void> handleResumed() async {
    _logoutTimer?.cancel();
    _logoutTimer = null;

    final since = _pausedAt;
    _pausedAt = null;
    if (since == null || phase != AppPhase.ready) return;
    if (DateTime.now().difference(since) >= backgroundGrace) {
      await _releaseSession();
    }
  }

  /// App 要被關掉了。這是最後一次釋放 session 的機會，不等緩衝時間。
  Future<void> handleDetached() async {
    _logoutTimer?.cancel();
    await _releaseSession();
  }

  /// 結束學校那端的登入，本地退回未登入。
  ///
  /// 課表快取留著 —— 回到 App 時馬上看得到東西，只是要重新登入才能更新。
  Future<void> _releaseSession() async {
    if (phase != AppPhase.ready) return;
    await repository.logout();
    captcha = null;
    phase = AppPhase.loggedOut;
    showingCache = timetable != null;
    notifyListeners();
  }

  @override
  void dispose() {
    _logoutTimer?.cancel();
    super.dispose();
  }

  Future<void> logout() async {
    await _guard(() async {
      await repository.logout();
      await credentials.clearPassword();
      hasSavedPassword = false;
      captcha = null;
      phase = AppPhase.loggedOut;
    });
  }

  // ---------- 課表 ----------

  Future<void> selectSemester({String? newYear, String? newSemester}) async {
    year = newYear ?? year;
    semester = newSemester ?? semester;

    final y = year;
    final s = semester;
    if (y == null || s == null) return;

    // 換學期時先把快取畫出來，網路慢的時候不會空一段。
    final cached = await repository.cached(y, s);
    if (cached != null) {
      timetable = cached;
      showingCache = true;
    }
    notifyListeners();

    if (phase == AppPhase.ready) await refreshTimetable();
  }

  Future<void> refreshTimetable() async {
    final y = year;
    final s = semester;
    if (y == null || s == null) return;

    loadingTimetable = true;
    error = null;
    notifyListeners();

    await _guard(() async {
      timetable = await repository.fetchTimetable(year: y, semester: s);
      showingCache = false;
    });

    loadingTimetable = false;
    notifyListeners();
  }

  // ---------- 錯誤處理 ----------

  /// 跑一段可能失敗的流程，把例外翻成一句可以顯示的話。
  ///
  /// [SessionExpired] 特別處理：session 掉了就要退回登入，
  /// 不然使用者會一直按重新整理，而每一次都失敗。
  Future<bool> _guard(
    Future<void> Function() body, {
    Future<void> Function()? onFailure,
  }) async {
    try {
      await body();
      notifyListeners();
      return true;
    } on SessionExpired catch (e) {
      repository.invalidateSession();
      error = e.message;
      phase = AppPhase.loggedOut;
    } on AisException catch (e) {
      error = e.message;
      await onFailure?.call();
    } catch (e) {
      // 沒預期到的例外。**只說類型，不說內容** ——
      // 這條路徑上可能有登入回應的碎片，而那裡面有明文密碼。
      error = '發生未預期的錯誤（${e.runtimeType}）。請再試一次。';
      await onFailure?.call();
    }
    notifyListeners();
    return false;
  }
}

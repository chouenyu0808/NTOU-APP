import 'package:flutter/foundation.dart';

import '../ais/exceptions.dart';
import '../ais/forms.dart';
import '../data/ais_repository.dart';
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
  AppController({required this.repository, required this.credentials});

  final AisRepository repository;
  final CredentialStore credentials;

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

  /// App 離開前景時呼叫：把學校那端的 session 結束掉，本地退回未登入。
  ///
  /// 不做的話，App 掛著的 session 會擋住使用者自己在瀏覽器登入，
  /// 而錯誤訊息（「系統同時一次僅許可一個帳號登入」）完全看不出兇手是自己的手機。
  ///
  /// 課表快取留著 —— 回到 App 時馬上看得到東西，只是需要重新登入才能更新。
  Future<void> handleBackgrounded() async {
    if (phase != AppPhase.ready) return;
    await repository.logout();
    captcha = null;
    phase = AppPhase.loggedOut;
    showingCache = timetable != null;
    notifyListeners();
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

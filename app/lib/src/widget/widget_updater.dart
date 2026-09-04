import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../storage/timetable_cache.dart';
import '../storage/transit_prefs_store.dart';
import '../transit/tdx_client.dart';
import '../transit/transit_config.dart';
import '../transit/transit_models.dart';
import '../transit/transit_repository.dart';
import 'timetable_widget_data.dart';
import 'transit_widget_data.dart';
import 'widget_views.dart';

/// 桌面小組件的更新流程。
///
/// 兩個小組件畫的都是**一張 PNG**（見 [widget_views.dart] 的說明），所以這裡
/// 的工作是：組 payload → 畫圖 → 存路徑 → 叫原生重畫。
///
/// **原生那一端不做任何判斷。** 它只有三件事：把圖貼上去、在該重畫的時間點
/// 叫醒我們、把點擊轉回來。所有「現在是第幾節」「這班車還有幾分鐘」「這條
/// 路線往哪裡」的邏輯都在 Dart，因為那些判斷錯了畫面上完全看不出來，而
/// Dart 這邊有測試守著。
class WidgetUpdater {
  WidgetUpdater({
    TimetableCache? cache,
    TransitPrefsStore? prefs,
    TransitRepository? transit,
    DateTime Function()? now,
  })  : _cache = cache ?? TimetableCache(),
        _prefs = prefs ?? TransitPrefsStore(),
        _now = now ?? DateTime.now,
        _injectedTransit = transit;

  final TimetableCache _cache;
  final TransitPrefsStore _prefs;
  /// 測試注入一個假的。正式執行時是 null，用的時候自己建。
  final TransitRepository? _injectedTransit;
  final DateTime Function() _now;

  /// 畫不出來的時候隔多久再試。
  ///
  /// 畫失敗多半是背景引擎沒有畫面可用（見 [_draw]），那是個結構性的問題，
  /// 重試一百次也一樣 —— 這個間隔存在的目的是**不要變成迴圈**，
  /// 不是真的期待下一次會成功。
  static const Duration _drawRetry = Duration(minutes: 10);

  // ------------------------------------------------------------------ 課表

  /// 重畫課表小組件。
  ///
  /// [surface] 是小組件現在多大 —— 原生叫我們的時候會帶著。前景（App 剛抓完
  /// 課表）沒有這個資訊，就沿用上次畫的尺寸；**從來沒畫過就什麼都不做**，
  /// 那代表桌面上根本沒有這個小組件，畫了也沒人看。
  Future<void> refreshTimetable({WidgetSurface? surface}) async {
    final where = surface ?? await _storedSurface(WidgetKeys.timetableSurface);
    if (where == null) return;

    final now = _now();
    final last = await _cache.lastViewed();
    final timetable =
        last == null ? null : await _cache.read(last.year, last.semester);

    final payload = buildTimetableWidgetPayload(
      timetable: timetable,
      now: now,
    );

    final drawn = await _draw(
      light: TimetableWidgetView(
        payload: payload,
        size: where.size,
        brightness: Brightness.light,
      ),
      dark: TimetableWidgetView(
        payload: payload,
        size: where.size,
        brightness: Brightness.dark,
      ),
      lightKey: WidgetKeys.timetableLight,
      darkKey: WidgetKeys.timetableDark,
      surface: where,
    );

    // **成敗都要記下尺寸。** 原生是靠「畫的時候是多大」跟現在比，判斷要不要
    // 叫我們重畫 —— 失敗時不記的話它每次 onUpdate 都會看到對不上、
    // 每次都再叫一次，而每次都失敗。那是一個不會停的迴圈。
    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.timetableDrawn,
      where.encode(),
    );

    // 原生拿這個判斷「手上這張圖過期了沒有」。畫失敗的時候往後推一段再重試，
    // 同樣是為了不要變成迴圈。
    final validUntil = drawn
        ? payload.validUntil
        : now.add(_drawRetry);
    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.timetableValidUntil,
      '${validUntil.millisecondsSinceEpoch}',
    );

    if (drawn) {
      await HomeWidget.updateWidget(
        qualifiedAndroidName: WidgetKeys.timetableProvider,
      );
    }

    // **一次給完整的一串。** 這個 API 是整批取代的語意，只給下一個時刻的話
    // 其餘的會被洗掉，症狀是小組件更新一次之後就再也不動了。
    //
    // 課表小組件沒有 `updatePeriodMillis`（那個最快也只有 30 分鐘，而且會
    // 叫醒裝置）—— 它完全靠這串鬧鐘。所以畫失敗時一定要把重試那一刻也排進去，
    // 不然這個小組件就再也沒有東西會叫醒它了。
    await _schedule(
      drawn ? payload.updateTimes : [validUntil, ...payload.updateTimes],
      WidgetKeys.timetableProvider,
    );
  }

  // ------------------------------------------------------------------ 交通

  /// 重畫交通小組件。
  ///
  /// 跟課表不一樣，這裡**每次都要打網路** —— 到站時間沒有本機來源。
  ///
  /// 抓失敗時畫的是上一次的資料加上「更新失敗」，不是把畫面清空：
  /// 舊的班次資訊加上一個誠實的時間戳，比一片空白有用得多。
  Future<void> refreshTransit({
    WidgetSurface? surface,
    Duration? ifOlderThan,
  }) async {
    final where = surface ?? await _storedSurface(WidgetKeys.transitSurface);
    if (where == null) return;

    final now = _now();

    // 前景那條路徑（開 App 的時候）會帶著這個 —— 桌面上那張圖還很新的話
    // 就不要為了它多打一次 TDX。背景那條不帶，因為原生已經先判斷過了。
    if (ifOlderThan != null) {
      final at = await _storedMillis(WidgetKeys.transitUpdatedAt);
      if (at != null && now.difference(at) < ifOlderThan) return;
    }
    // 不論成敗都先記下這次嘗試。原生靠它退避 —— 沒有的話一次失敗會變成
    // 一直重試（我們畫「更新失敗」→ onUpdate → 又叫我們抓），
    // 而重試本身正是 TDX 回 429 的原因。
    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.transitLastAttempt,
      '${now.millisecondsSinceEpoch}',
    );

    final payload = await _fetchTransit(now);
    if (payload == null) return;

    await _publishTransit(payload, where);
  }

  /// App 的交通分頁剛抓到資料，順手把桌面上那張圖也更新掉。
  ///
  /// **不重新抓一次網路。** 資料已經在手上了，再打一次 TDX 純粹是浪費 ——
  /// 而那一頁本來就每 30 秒抓一次，多這一輪就是把請求量翻倍。
  ///
  /// 桌面上沒有這個小組件時什麼都不做（[_storedSurface] 回 null）。
  Future<void> publishTransit({
    required List<StopBoard> boards,
    required TransitConfig config,
    Set<String> favorites = const {},
  }) async {
    final where = await _storedSurface(WidgetKeys.transitSurface);
    if (where == null) return;

    final now = _now();
    // 整批都失敗的時候不要覆蓋桌面上的圖 —— 舊班次比五行「服務忙碌中」有用。
    if (boards.isEmpty || boards.every((b) => b.error != null)) return;

    await _publishTransit(
      buildTransitWidgetPayload(
        boards: boards,
        config: config,
        favorites: favorites,
        now: now,
      ),
      where,
    );
  }

  Future<void> _publishTransit(
    TransitWidgetPayload payload,
    WidgetSurface where,
  ) async {
    final drawn = await _draw(
      light: TransitWidgetView(
        payload: payload,
        size: where.size,
        brightness: Brightness.light,
      ),
      dark: TransitWidgetView(
        payload: payload,
        size: where.size,
        brightness: Brightness.dark,
      ),
      lightKey: WidgetKeys.transitLight,
      darkKey: WidgetKeys.transitDark,
      surface: where,
    );

    // 跟課表那邊同樣的理由：成敗都要記尺寸，不然「對不上 → 再叫一次 →
    // 又失敗」會一直繞。這裡的迴圈還會**每繞一圈就打一次 TDX**。
    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.transitDrawn,
      where.encode(),
    );
    if (!drawn) return;

    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.transitPayload,
      jsonEncode(payload.toJson()),
    );
    // **失敗的時候不動這個時間。** 它講的是「畫面上的資料有多舊」，
    // 拿失敗的時刻蓋上去等於謊報新鮮度。
    if (!payload.refreshFailed && payload.updatedAt != null) {
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.transitUpdatedAt,
        '${payload.updatedAt!.millisecondsSinceEpoch}',
      );
    }

    await HomeWidget.updateWidget(
      qualifiedAndroidName: WidgetKeys.transitProvider,
    );
  }

  /// 抓一次交通資料。抓不到就回上一次的（標著「更新失敗」）。
  ///
  /// 回 null = 連上一次的都沒有，而且這次也失敗 —— 那就不要動畫面，
  /// 讓原本那張圖留著。
  Future<TransitWidgetPayload?> _fetchTransit(DateTime now) async {
    TransitWidgetPayload? previous;
    try {
      final raw =
          await HomeWidget.getWidgetData<String>(WidgetKeys.transitPayload);
      if (raw != null && raw.isNotEmpty) {
        previous = TransitWidgetPayload.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // 舊格式讀不動就當作沒有。壞掉的快取不該讓小組件停止更新。
    }

    try {
      final repo = _injectedTransit ?? await _buildRepository();
      if (!repo.isConfigured) return previous?.copyWith(refreshFailed: true);

      final boards = await repo.boards(repo.config.stops);
      // 每一站都失敗 = 整批沒問到（沒網路、429）。**這種時候不要覆蓋** ——
      // 蓋上去的話畫面會變成五行「服務忙碌中」，而舊的班次資訊其實還有用。
      if (boards.isNotEmpty && boards.every((b) => b.error != null)) {
        return previous?.copyWith(refreshFailed: true) ??
            buildTransitWidgetPayload(
              boards: boards,
              config: repo.config,
              favorites: await _favorites(),
              now: now,
            );
      }

      return buildTransitWidgetPayload(
        boards: boards,
        config: repo.config,
        favorites: await _favorites(),
        now: now,
      );
    } catch (_) {
      // **不要把例外訊息畫到小組件上。** dio 的訊息裡有完整 URL 和堆疊，
      // 那是給我們看的，不是給使用者看的。
      return previous?.copyWith(refreshFailed: true);
    }
  }

  Future<Set<String>> _favorites() async {
    try {
      return await _prefs.readFavorites();
    } catch (_) {
      // 讀不到就當作沒釘過。排序退回照時間，小組件照常能用。
      return const {};
    }
  }

  Future<TransitRepository> _buildRepository() async {
    final config = await TransitConfig.loadFromAsset();
    return TransitRepository(config: config, client: TdxClient(config: config));
  }

  // ------------------------------------------------------------------ 共用

  /// 開 App 的時候把兩個小組件都補一次。
  ///
  /// **這是唯一保證修得好的路徑。** 背景那條有太多會靜靜失敗的環節
  /// （callback handle 還沒註冊、WorkManager 的鏈中毒、背景引擎畫不出圖），
  /// 而使用者發現小組件壞掉之後會做的第一件事就是開 App —— 那一刻要能修好。
  ///
  /// 課表是免費的（只讀本機快取），所以無條件重畫。交通要打網路，
  /// 所以只有在桌面上那份夠舊的時候才抓。
  ///
  /// 桌面上沒有小組件的話兩邊都會直接回來，不做任何事。
  Future<void> refreshAll() async {
    await refreshTimetable();
    await refreshTransit(ifOlderThan: const Duration(minutes: 25));
  }

  /// 換帳號時把小組件上的東西清掉。
  ///
  /// **一定要做。** 不清的話前一個人的課表會留在桌面上 —— 而換帳號的人
  /// 通常正是「這支手機借給別人用」的情境，那張圖上有課名和教室。
  ///
  /// 交通那半邊不清：它跟帳號完全無關（不用登入，站是寫死的），
  /// 清掉只是讓下一次重整前空一段。
  Future<void> clearTimetable() async {
    // 傳 null 進去會順便把 PNG 檔刪掉，不只是清掉 key。
    await HomeWidget.saveWidgetData<String>(WidgetKeys.timetableLight, null);
    await HomeWidget.saveWidgetData<String>(WidgetKeys.timetableDark, null);
    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.timetableValidUntil,
      null,
    );
    // 這個也要清：留著的話原生會以為手上那張圖還是照現在的尺寸畫的，
    // 而圖已經被刪了 —— 小組件會停在佔位字上不動。
    await HomeWidget.saveWidgetData<String>(WidgetKeys.timetableDrawn, null);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: WidgetKeys.timetableProvider,
    );
  }

  /// 畫淺色和深色各一張。
  ///
  /// **為什麼要兩張**：小組件是一張圖，跟不了系統的深淺色切換。使用者切成
  /// 深色之後，只有一張淺色圖的話桌面上就是一塊白的 —— 看起來完全就是壞了。
  /// 兩張都畫，`layout/` 和 `layout-night/` 各自指到不同的 ImageView，
  /// launcher 會用自己當下的設定去 inflate，切換就跟著變。
  ///
  /// 回 false = 這次沒畫成，呼叫端不要動任何狀態，讓原本那張圖留著。
  Future<bool> _draw({
    required Widget light,
    required Widget dark,
    required String lightKey,
    required String darkKey,
    required WidgetSurface surface,
  }) async {
    // **背景 isolate 用的是沒有畫面的引擎**（`FlutterEngine(context)`，從來
    // 沒附著過 FlutterView），而 renderFlutterWidget 內部是
    // `implicitView!` —— 沒有的話會是一個 null check 例外。畫不出來不是
    // 世界末日（桌面上留著上一張圖），炸掉才是。
    if (ui.PlatformDispatcher.instance.implicitView == null) {
      _log('沒有 implicitView，這個 isolate 畫不了圖');
      return false;
    }

    try {
      for (final (key, view) in [(lightKey, light), (darkKey, dark)]) {
        await HomeWidget.renderFlutterWidget(
          view,
          key: key,
          logicalSize: surface.size,
          // **一定要自己帶。** 套件的預設值是
          // `implicitView?.devicePixelRatio ?? 1`，而背景引擎那個 view 從來
          // 沒有附著過真正的畫面，讀到的是 1.0 —— 前景畫出來是 2.75 倍
          // 的清晰圖、背景畫出來是 1 倍的糊圖，而且只有在手機上看得出來。
          pixelRatio: surface.pixelRatio,
        );
      }
      _log('畫好了 $lightKey / $darkKey，${surface.size} @${surface.pixelRatio}');
      return true;
    } catch (e) {
      _log('畫圖失敗：${e.runtimeType} $e');
      return false;
    }
  }

  /// 只在 debug build 印。
  ///
  /// 這一整條路徑上的失敗全都是**安靜的** —— 畫不出來就留著上一張圖，
  /// 桌面上看起來只是「沒更新」。沒有 log 的話，唯一的除錯方式是猜。
  ///
  /// release 版一行都不印：跟 AIS 那邊同一條規則（見 main.dart）。
  /// 這裡雖然沒有密碼，但沒必要在正式版留下任何東西。
  static void _log(String line) {
    if (kDebugMode) debugPrint('[widget] $line');
  }

  Future<void> _schedule(List<DateTime> times, String provider) async {
    try {
      await HomeWidget.scheduleWidgetUpdates(
        times,
        qualifiedAndroidName: provider,
      );
    } catch (_) {
      // 排不到鬧鐘（權限、找不到 provider）就算了 —— 小組件還是會在
      // 使用者點它、或系統自己 onUpdate 的時候更新，只是反白會慢一點移動。
    }
  }

  Future<DateTime?> _storedMillis(String key) async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(key);
      final ms = int.tryParse(raw ?? '');
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<WidgetSurface?> _storedSurface(String key) async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(key);
      return raw == null ? null : WidgetSurface.decode(raw);
    } catch (_) {
      return null;
    }
  }
}

/// 小組件現在多大、螢幕密度多少。
///
/// 使用者可以把小組件拉大縮小，所以**尺寸不是常數**，是原生每次告訴我們的。
/// 拿舊尺寸畫的圖會被 ImageView 拉伸，變成一張糊掉的圖。
class WidgetSurface {
  const WidgetSurface({required this.size, required this.pixelRatio});

  final Size size;

  /// 螢幕密度。畫 PNG 的時候要照這個放大，不然桌面上是糊的。
  final double pixelRatio;

  /// 存進 widget data 的樣子：`寬|高|密度`。
  String encode() => '${size.width}|${size.height}|$pixelRatio';

  static WidgetSurface? decode(String raw) {
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final w = double.tryParse(parts[0]);
    final h = double.tryParse(parts[1]);
    final d = double.tryParse(parts[2]);
    if (w == null || h == null || d == null) return null;
    if (w <= 0 || h <= 0 || d <= 0) return null;
    return WidgetSurface(size: Size(w, h), pixelRatio: d);
  }

  /// 從原生傳來的 URI 參數建。看不懂就回 null，呼叫端會退回上次的尺寸。
  static WidgetSurface? fromQuery(Map<String, String> q) {
    final w = double.tryParse(q['w'] ?? '');
    final h = double.tryParse(q['h'] ?? '');
    final d = double.tryParse(q['dpr'] ?? '');
    if (w == null || h == null || d == null) return null;
    if (w <= 0 || h <= 0 || d <= 0) return null;
    return WidgetSurface(size: Size(w, h), pixelRatio: d);
  }
}

/// 兩端共用的名字。**改這裡要連原生的 Kotlin 一起改** —— 對不上的話
/// 小組件會是一片空白，而且兩邊都不會報錯。
class WidgetKeys {
  const WidgetKeys._();

  static const String _package = 'tw.edu.ntou.ntou_app';

  static const String timetableProvider =
      '$_package.widget.TimetableWidgetProvider';
  static const String transitProvider =
      '$_package.widget.TransitWidgetProvider';

  static const String timetableLight = 'timetable_image_light';
  static const String timetableDark = 'timetable_image_dark';

  /// 這張圖畫到什麼時候為止（epoch millis 的字串）。
  ///
  /// 存成字串不是數字：method channel 對 Dart int 是「塞得下 32 bit 就送
  /// Int、否則送 Long」，兩邊要各自處理兩種型別。epoch millis 一定超過
  /// 32 bit，但把型別分岔留在那裡遲早會踩到。
  static const String timetableValidUntil = 'timetable_valid_until';

  /// 小組件現在多大。**這一個是原生寫的**（`NtouWidgetProvider.remember`）——
  /// 前景路徑靠它知道桌面上有這塊東西、而且它多大。只有 Dart 會寫的話，
  /// 新裝的 App 永遠畫不出第一張圖：沒畫過就沒有尺寸，沒有尺寸就不畫。
  static const String timetableSurface = 'timetable_surface';

  /// 手上那張圖是照什麼尺寸畫的。**這一個是 Dart 寫的**，原生拿它跟
  /// 現在的尺寸比，判斷使用者是不是把小組件拉大縮小了。
  static const String timetableDrawn = 'timetable_drawn';

  static const String transitLight = 'transit_image_light';
  static const String transitDark = 'transit_image_dark';
  static const String transitSurface = 'transit_surface';
  static const String transitDrawn = 'transit_drawn';
  static const String transitUpdatedAt = 'transit_updated_at';
  static const String transitLastAttempt = 'transit_last_attempt';
  static const String transitPayload = 'transit_payload';
}

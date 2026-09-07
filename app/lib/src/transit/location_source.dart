import 'package:geolocator/geolocator.dart';

import 'nearest_stop.dart';

/// 量一次使用者現在在哪裡。
///
/// ## 為什麼只在前景量
///
/// 小組件是在背景更新的，而 Android 10 之後**背景取位置需要
/// `ACCESS_BACKGROUND_LOCATION`** —— 那個權限 Google Play 要人工審查，
/// 而且要說明「為什麼非得在使用者沒在用 App 的時候知道他在哪」。
/// 為了把一個站牌排到前面去要那種權限，代價完全不成比例。
///
/// 所以位置只在 App 於前景時量一次、記下來（[TransitPrefsStore.writePlace]），
/// 小組件用那一份。代價是使用者從學校走到市區而沒開過 App 的話，
/// 小組件排在最前面的還是學校那站 —— 但五個站是全部列出來的，
/// 排序錯了只是順序不理想，不會讓他看不到要的東西。
///
/// ## 為什麼要 high accuracy
///
/// 海大三個門互相只差 237 到 683 公尺。粗略定位（基地台／Wi-Fi）誤差常常
/// 上百公尺到一公里 —— **在校內會挑錯門，而畫面上是一個看起來完全合理的
/// 站名**。分不出來的話寧可不要這個功能。
class LocationSource {
  const LocationSource();

  /// 量一次。拿不到就回 null（沒權限、定位關著、逾時）。
  ///
  /// **不會自己跳權限對話框**：呼叫端要先確定使用者主動要求過這件事，
  /// 見 [ensurePermission]。
  Future<LastKnownPlace?> current({DateTime Function()? now}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // 定位拿不到不該讓交通頁卡著 —— 那一頁的主角是到站時間，
          // 位置只是拿來排順序的。
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LastKnownPlace(
        lat: p.latitude,
        lon: p.longitude,
        at: (now ?? DateTime.now)(),
      );
    } catch (_) {
      // 逾時、權限被撤、模擬器沒有定位…… 全部當作「這次沒量到」。
      // **不要把例外訊息顯示出來**，那對使用者沒有任何意義。
      return null;
    }
  }

  /// 要一次權限。回傳現在到底有沒有。
  ///
  /// 只在使用者**主動按了那個按鈕**的時候呼叫 —— 開 App 就跳定位權限
  /// 對話框是最快讓人按「拒絕」的做法，而一旦按了 deniedForever，
  /// 之後就只能請他自己去系統設定開。
  Future<bool> ensurePermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// 使用者已經永久拒絕了，只能請他去系統設定開。
  Future<bool> get deniedForever async {
    try {
      return await Geolocator.checkPermission() ==
          LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }
}

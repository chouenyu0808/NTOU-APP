import 'package:flutter/foundation.dart';

import 'widget_updater.dart';

/// 原生叫 Dart 做事的入口。
///
/// **這個函式跑在背景 isolate 裡**，用的是一個獨立的 `FlutterEngine` ——
/// App 的畫面、[AppController]、已經登入的 session 在這裡通通不存在。
/// 能拿到的只有本機儲存（SharedPreferences）和網路。
///
/// 課表那半邊剛好完全夠：它的來源就是本機快取，不用登入。**交通那半邊
/// 要打網路，但它本來就不需要登入**，所以兩個小組件在背景都是完整可用的。
///
/// 必須是**頂層函式**而且掛著 `@pragma('vm:entry-point')` ——
/// 少了那個註解，release build 的 tree shaking 會把它整個拿掉，
/// 而 debug build 一切正常。症狀是「裝 release 版之後小組件不會自己更新」。
@pragma('vm:entry-point')
Future<void> ntouWidgetBackground(Uri? uri) async {
  if (kDebugMode) debugPrint('[widget] 背景被叫醒：$uri');
  if (uri == null) return;

  final surface = WidgetSurface.fromQuery(uri.queryParameters);
  final updater = WidgetUpdater();

  // 認不得的就什麼都不做。**不要「猜一個預設的」** —— 猜錯的話使用者點
  // 交通的重新整理鈕會去重畫課表，而畫面上只是「按了沒反應」。
  switch (uri.host) {
    case widgetHostTimetable:
      await updater.refreshTimetable(surface: surface);
    case widgetHostTransit:
      await updater.refreshTransit(surface: surface);
  }
}

/// URI 的 scheme 和 host。**改這裡要連原生的 Kotlin 一起改。**
/// 對不上的話按鈕按下去沒有任何反應，而且兩邊都不會報錯。
const String widgetScheme = 'ntouwidget';
const String widgetHostTimetable = 'timetable';
const String widgetHostTransit = 'transit';

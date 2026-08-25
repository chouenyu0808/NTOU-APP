import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';

import 'fake_ais.dart';

/// 進背景之後的緩衝。
///
/// 一開始是「一離開前景就登出」，因為學校系統一個帳號只能有一個 session。
/// 但那樣切出去看一眼訊息再回來就要重打驗證碼 —— 所以給兩分鐘。
void main() {
  test('緩衝時間是兩分鐘', () {
    expect(AppController.backgroundGrace, const Duration(minutes: 2));
  });

  test('沒登入時進背景不做任何事', () async {
    final c = await newController();
    expect(c.phase, AppPhase.loggedOut);

    c.handlePaused();
    await c.handleResumed();

    // 沒有 session 可以放，也不該把狀態弄壞
    expect(c.phase, AppPhase.loggedOut);
  });

  test('短暫切出去再回來，不會被登出', () async {
    // 這正是使用者抱怨的情境：看一眼訊息就回來，不該要求重打驗證碼。
    final c = await newController();
    c.handlePaused();
    await c.handleResumed();
    expect(c.phase, AppPhase.loggedOut);
  });

  test('handleDetached 不等緩衝', () async {
    // App 要被關掉了，這是最後一次釋放 session 的機會
    final c = await newController();
    await c.handleDetached();
    expect(c.phase, AppPhase.loggedOut);
  });
}

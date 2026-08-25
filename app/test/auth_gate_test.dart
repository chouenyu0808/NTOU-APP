import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';

import 'fake_ais.dart';

/// 登入關卡的判斷依據。
///
/// `AuthGate` 本身只是「phase == ready ? HomeShell : LoginPage」，
/// 真正會出錯的是 phase 的轉換。掛載整棵畫面來測那個三元判斷不划算 ——
/// 登入頁一掛載就會去打學校的伺服器，而 dio 每個請求都會排一個計時器，
/// widget test 只要結束時還有計時器掛著就紅（訊息還完全看不出跟登入有關）。
///
/// 所以這裡測狀態機，畫面本身在真機上驗。
void main() {
  test('剛啟動就是未登入 —— 關卡會顯示登入頁', () async {
    final c = await newController();
    expect(c.phase, AppPhase.loggedOut);
  });

  test('登出之後退回未登入 —— 關卡會把使用者送回登入頁', () async {
    final c = await newController();
    await c.logout();
    expect(c.phase, AppPhase.loggedOut);
  });

  test('掛太久被放掉之後也是退回未登入', () async {
    // 進背景超過 backgroundGrace 之後 handleResumed 會釋放 session，
    // phase 回到 loggedOut —— 關卡就會自己把畫面換成登入頁。
    final c = await newController();
    c.handlePaused();
    await c.handleResumed();
    expect(c.phase, AppPhase.loggedOut);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';

import 'fake_ais.dart';

/// 登入狀態只控制學校查詢，不再取代主畫面。
void main() {
  test('剛啟動沒有學校登入狀態', () async {
    final c = await newController();
    expect(c.phase, AppPhase.loggedOut);
  });

  test('登出之後清除登入狀態', () async {
    final c = await newController();
    await c.logout();
    expect(c.phase, AppPhase.loggedOut);
  });

  test('掛太久被放掉之後也是退回未登入', () async {
    // 進背景超過 backgroundGrace 之後 handleResumed 會釋放 session，
    // phase 回到 loggedOut，本機畫面仍可繼續使用。
    final c = await newController();
    c.handlePaused();
    await c.handleResumed();
    expect(c.phase, AppPhase.loggedOut);
  });
}

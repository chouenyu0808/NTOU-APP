import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/auth_gate.dart';
import 'package:ntou_app/src/ui/login_page.dart';

import 'fake_ais.dart';

void main() {
  testWidgets('已存帳密辨識成功後完成登入並取得課表', (tester) async {
    final c = await newController();
    final ais = ScriptedAis((request) {
      if (request.page.toLowerCase().startsWith('default.aspx')) {
        return request.method == 'POST'
            ? "<script>top.location.href='MainFrame.aspx';</script>"
            : null;
      }
      if (request.page.startsWith('MainFrame.aspx')) return '<html>ok</html>';
      if (request.pressed('QUERY_BTN1')) return '<html>查無符合資料</html>';
      return '<form><input type="hidden" name="__VIEWSTATE" value="測試">'
          '<select name="Q_AYEAR"><option selected value="115">115</option></select>'
          '<select name="Q_SMS"><option selected value="1">上學期</option></select>'
          '<input type="submit" name="QUERY_BTN1" value="查詢"></form>';
    });
    c.repository.dio!.httpClientAdapter = ais;
    await c.credentials.saveUsername('B12345678');
    await c.credentials.savePassword('測試密碼');
    await c.init();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(controller: c, recognizeCaptcha: (_) async => 'AB12'),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.phase, AppPhase.ready);
    expect(c.timetable?.isEmpty, isTrue);
    expect(
      ais.posts.where((r) => r.page.toLowerCase().startsWith('default.aspx')),
      hasLength(1),
    );
    await unmount(tester);
    c.dispose();
  });

  for (final recognized in ['AB12', 'ABCDEF', '']) {
    testWidgets('已存帳密辨識結果「$recognized」最多送出一次，失敗後停下', (tester) async {
      final c = await newController();
      final ais = ScriptedAis();
      c.repository.dio!.httpClientAdapter = ais;
      await c.credentials.saveUsername('B12345678');
      await c.credentials.savePassword('測試密碼');
      await c.init();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            controller: c,
            recognizeCaptcha: (_) async => recognized,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(ais.posts.length, recognized.length == 4 ? 1 : 0);
      expect(c.phase, AppPhase.awaitingCaptcha);
      if (recognized.length == 4) {
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .any((field) => field.controller?.text == recognized),
          isTrue,
          reason: '登入失敗後的新驗證碼辨識結果不可被上一輪送出清掉',
        );
      }
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(ais.posts.length, recognized.length == 4 ? 1 : 0);
      await unmount(tester);
      c.dispose();
    });
  }

  testWidgets('辨識尚未完成時修改欄位，自動登入讓出控制權', (tester) async {
    final c = await newController();
    final ais = ScriptedAis();
    c.repository.dio!.httpClientAdapter = ais;
    await c.credentials.saveUsername('B12345678');
    await c.credentials.savePassword('測試密碼');
    await c.init();
    final result = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(controller: c, recognizeCaptcha: (_) => result.future),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'B87654321');
    result.complete('AB12');
    await tester.pumpAndSettle();
    expect(ais.posts, isEmpty);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .any((field) => field.controller?.text == 'AB12'),
      isTrue,
      reason: '修改帳號只停止自動送出，仍應填入辨識結果',
    );
    await unmount(tester);
    c.dispose();
  });

  testWidgets('沒有記住密碼時即使辨識成功也不送出', (tester) async {
    final c = await newController();
    final ais = ScriptedAis();
    c.repository.dio!.httpClientAdapter = ais;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(controller: c, recognizeCaptcha: (_) async => 'AB12'),
      ),
    );
    await tester.pumpAndSettle();
    expect(ais.posts, isEmpty);
    await unmount(tester);
    c.dispose();
  });

  testWidgets('記住帳密後啟動會準備登入，取消後不會重複跳出', (tester) async {
    final c = await newController();
    c.repository.dio!.httpClientAdapter = ScriptedAis();
    await c.credentials.saveUsername('B12345678');
    await c.credentials.savePassword('測試密碼');
    await c.init();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          controller: c,
          catalog: const MenuCatalog([]),
          planStore: PlanStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any((field) => field.controller?.text == 'B12345678'),
      isTrue,
    );
    expect(fields.any((field) => field.controller?.text == '測試密碼'), isTrue);
    expect(c.phase, AppPhase.awaitingCaptcha, reason: '測試環境無辨識服務時保留手動登入');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    await unmount(tester);
    c.dispose();
  });

  testWidgets('只有記住學號不會自動開啟登入', (tester) async {
    final c = await newController();
    c.username = 'B12345678';
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          controller: c,
          catalog: const MenuCatalog([]),
          planStore: PlanStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
    await unmount(tester);
    c.dispose();
  });
}

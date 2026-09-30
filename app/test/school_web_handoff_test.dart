import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/school_web_handoff.dart';
import 'fake_ais.dart';

void main() {
  testWidgets('取消接續保留登入，確認後先釋放登入才開啟網頁', (tester) async {
    final c = await newController(); c.phase = AppPhase.ready;
    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      expect(c.phase, AppPhase.loggedOut);
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SchoolWebHandoff(controller: c, functionTitle: '請假附件'))));
    await tester.tap(find.text('到學校網頁完成')); await tester.pumpAndSettle();
    expect(find.textContaining('不會自動帶過去'), findsOneWidget);
    await tester.tap(find.text('留在這裡')); await tester.pumpAndSettle();
    expect(c.phase, AppPhase.ready); expect(calls, isEmpty);
    await tester.tap(find.text('到學校網頁完成')); await tester.pumpAndSettle();
    await tester.tap(find.text('開啟網頁')); await tester.pumpAndSettle();
    expect(c.phase, AppPhase.loggedOut);
    expect(calls.single.arguments['url'], c.repository.config.baseUrl);
    await unmount(tester); c.dispose();
  });
}

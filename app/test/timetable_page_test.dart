import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/main.dart';
import 'package:ntou_app/src/config/selectors.dart';
import 'package:ntou_app/src/data/ais_repository.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/credential_store.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/timetable_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 畫面測試。除了「UI 整包編得起來」之外，真正要鎖的是一件事：
/// **「這學期沒課」和「App 出錯了」在畫面上必須長得不一樣。**
///
/// 搞混的代價很實際：使用者看到空白會一直重試（打驗證碼、等排隊），
/// 或者更糟 —— 以為自己沒選到課。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<AppController> controllerWith(TimetableResult? result) async {
    final cache = TimetableCache(prefs: await SharedPreferences.getInstance());
    if (result != null) await cache.write(result);

    final controller = AppController(
      repository: AisRepository(
        config: SelectorConfig.fromJson(const {}),
        cache: cache,
      ),
      credentials: CredentialStore(),
    );
    await controller.init();
    return controller;
  }

  Widget wrap(AppController c) =>
      MaterialApp(home: TimetablePage(controller: c));

  testWidgets('沒有任何資料時說「還沒有課表」', (tester) async {
    await tester.pumpWidget(wrap(await controllerWith(null)));
    await tester.pumpAndSettle();

    expect(find.text('還沒有課表'), findsOneWidget);
    expect(find.text('登入更新'), findsOneWidget);
  });

  testWidgets('學校回「查無符合資料」時，說的是沒修課，不是出錯', (tester) async {
    await tester.pumpWidget(wrap(await controllerWith(
      TimetableResult(
        year: '115',
        semester: '1',
        courses: const [],
        isEmpty: true,
        fetchedAt: DateTime(2026, 8, 25, 14, 30),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('沒有修課紀錄'), findsOneWidget);
    expect(find.textContaining('查無符合資料'), findsOneWidget);
    // 不能出現任何「錯誤」字樣 —— 這不是錯誤。
    expect(find.textContaining('錯誤'), findsNothing);
  });

  testWidgets('有課表時列出課程，並標明這是快取', (tester) async {
    await tester.pumpWidget(wrap(await controllerWith(
      TimetableResult(
        year: '115',
        semester: '1',
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25, 14, 30),
        columns: const ['課號', '課名'],
        courses: [
          const Course(
            name: '計算機概論',
            code: 'B57011RQ',
            teacher: '王小明',
            room: '電資305',
            credits: 3,
            slots: [TimeSlot(0, 3), TimeSlot(0, 4)],
            raw: {'課號': 'B57011RQ', '課名': '計算機概論'},
          ),
        ],
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('計算機概論'), findsWidgets);
    expect(find.textContaining('B57011RQ'), findsWidgets);
    // 快取橫幅：使用者要知道這是舊資料，尤其在登不進去的時候。
    expect(find.textContaining('還沒跟學校核對'), findsOneWidget);
  });

  testWidgets('解不出上課時間時，課程仍然列得出來', (tester) async {
    await tester.pumpWidget(wrap(await controllerWith(
      TimetableResult(
        year: '115',
        semester: '1',
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25),
        courses: const [Course(name: '線性代數', slots: [])],
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('線性代數'), findsOneWidget);
    expect(find.textContaining('沒有畫成格子'), findsOneWidget);
  });

  testWidgets('App 根層編得起來也畫得出來', (tester) async {
    // 這個測試的重點不在斷言，而是**把 main.dart 拉進編譯範圍**。
    // 沒有它，App 入口只有真的 flutter run 時才會被編譯到 ——
    // 而這台機器上還沒有 Android / iOS SDK 可以跑。
    await tester.pumpWidget(NtouApp(controller: await controllerWith(null)));
    await tester.pumpAndSettle();

    expect(find.byType(TimetablePage), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/transit/transit_models.dart' show ArrivalTone;
import 'package:ntou_app/src/widget/timetable_widget_data.dart';
import 'package:ntou_app/src/widget/transit_widget_data.dart';
import 'package:ntou_app/src/widget/widget_views.dart';

/// 桌面小組件畫出來的那張圖。
///
/// **這裡刻意只包一層 `Directionality`，不包 `MaterialApp`。**
/// 正式執行時 `HomeWidget.renderFlutterWidget` 就是這樣畫的 ——
/// 沒有 Theme、沒有 DefaultTextStyle、沒有 MediaQuery。
/// 用 MaterialApp 包起來測的話，少帶 color 的 TextStyle 會被上層補起來，
/// 測試全綠而手機上是黃底紅字。
void main() {
  Future<void> draw(WidgetTester tester, Widget view) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: view),
    );
  }

  TimetableWidgetPayload timetable({
    required List<TimetableWidgetRow> rows,
    int highlightIndex = -1,
    bool highlightStarted = false,
    bool timesKnown = true,
    String? emptyMessage,
  }) =>
      TimetableWidgetPayload(
        dateLabel: '9 月 3 日',
        weekdayLabel: '星期四',
        rows: rows,
        highlightIndex: highlightIndex,
        highlightStarted: highlightStarted,
        timesKnown: timesKnown,
        emptyMessage: emptyMessage,
        updateTimes: [DateTime(2026, 9, 4)],
      );

  TimetableWidgetRow row(String name, {bool done = false}) =>
      TimetableWidgetRow(
        period: '第 1-2 節',
        time: '08:20–10:10',
        name: name,
        room: 'A101',
        done: done,
      );

  group('課表小組件', () {
    testWidgets('沒有 Theme 也畫得出來', (tester) async {
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(rows: [row('程式設計'), row('線性代數')]),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('9 月 3 日'), findsOneWidget);
      expect(find.text('星期四'), findsOneWidget);
      expect(find.text('程式設計'), findsOneWidget);
    });

    testWidgets('深色也畫得出來', (tester) async {
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(rows: [row('程式設計')]),
          size: const Size(320, 180),
          brightness: Brightness.dark,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('程式設計'), findsOneWidget);
    });

    testWidgets('右上角的標分得出「現在」和「下一堂」', (tester) async {
      // 這兩個字對使用者的意義完全不同：一個是已經在上課（可能遲到了），
      // 一個是還沒開始。
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(
            rows: [row('程式設計')],
            highlightIndex: 0,
            highlightStarted: true,
          ),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );
      expect(find.text('現在'), findsOneWidget);

      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(rows: [row('程式設計')], highlightIndex: 0),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );
      expect(find.text('下一堂'), findsOneWidget);
    });

    testWidgets('今天的課上完了就說「今天結束」', (tester) async {
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(rows: [row('程式設計', done: true)]),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('今天結束'), findsOneWidget);
    });

    testWidgets('沒有節次時間表時說「今天第一堂」，不說「下一堂」', (tester) async {
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(
            rows: [row('程式設計')],
            highlightIndex: 0,
            timesKnown: false,
          ),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('今天第一堂'), findsOneWidget);
      expect(find.text('下一堂'), findsNothing);
    });

    testWidgets('放不下的時候說有幾堂被藏起來，不是直接切掉', (tester) async {
      // 直接切掉的話畫面上跟「今天就這幾堂」長得一模一樣。
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(
            rows: [for (var i = 1; i <= 6; i++) row('第 $i 堂')],
            highlightIndex: 0,
          ),
          size: const Size(320, 130),
          brightness: Brightness.light,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('還有'), findsOneWidget);
    });

    testWidgets('放不下時把視窗捲到反白那一堂，不是永遠從第一堂開始', (tester) async {
      // 下午四點要看的是接下來那堂，不是早上已經上完的兩堂。
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(
            rows: [for (var i = 1; i <= 6; i++) row('第 $i 堂', done: i < 5)],
            highlightIndex: 4,
          ),
          size: const Size(320, 130),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('第 5 堂'), findsOneWidget);
      expect(find.text('第 1 堂'), findsNothing);
    });

    testWidgets('空白時把該說的話說出來', (tester) async {
      await draw(
        tester,
        TimetableWidgetView(
          payload: timetable(rows: const [], emptyMessage: '今天沒有課'),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('今天沒有課'), findsOneWidget);
      // 沒有課的時候右上角不要掛一個空的標。
      expect(find.text('下一堂'), findsNothing);
      expect(find.text('今天結束'), findsNothing);
    });
  });

  group('交通小組件', () {
    TransitWidgetPayload transit({
      DateTime? updatedAt,
      bool refreshFailed = false,
      List<TransitWidgetStop>? stops,
    }) =>
        TransitWidgetPayload(
          stops: stops ??
              [
                const TransitWidgetStop(
                  name: '海大體育館',
                  rows: [
                    TransitWidgetRow(
                      route: '103',
                      towards: '往 八斗子車站',
                      eta: '12 分',
                      tone: ArrivalTone.normal,
                      favorite: false,
                    ),
                  ],
                ),
              ],
          updatedAt: updatedAt ?? DateTime(2026, 9, 3, 10, 32),
          refreshFailed: refreshFailed,
        );

    testWidgets('沒有 Theme 也畫得出來', (tester) async {
      await draw(
        tester,
        TransitWidgetView(
          payload: transit(),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('海大體育館'), findsOneWidget);
      expect(find.text('103'), findsOneWidget);
      expect(find.text('12 分'), findsOneWidget);
    });

    testWidgets('一定要標資料時間', (tester) async {
      // 小組件最快 30 分鐘才自動更新一次，上面的「12 分」必然是舊的。
      // 不標時間的話它跟即時資料長得一模一樣，使用者會照著出門。
      await draw(
        tester,
        TransitWidgetView(
          payload: transit(),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('資料時間 10:32'), findsOneWidget);
    });

    testWidgets('更新失敗時講出來，而且不動資料時間', (tester) async {
      await draw(
        tester,
        TransitWidgetView(
          payload: transit(refreshFailed: true),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('10:32 的資料 · 更新失敗'), findsOneWidget);
    });

    testWidgets('沒有可搭的車時說的是哪一句', (tester) async {
      await draw(
        tester,
        TransitWidgetView(
          payload: transit(
            stops: const [
              TransitWidgetStop(
                name: '基隆轉運站',
                rows: [],
                note: '只有 2 班到站後收班的車，沒有可搭乘的班次',
              ),
            ],
          ),
          size: const Size(320, 180),
          brightness: Brightness.light,
        ),
      );

      expect(find.textContaining('收班'), findsOneWidget);
    });

    testWidgets('塞不下就少畫幾列，不要溢位', (tester) async {
      await draw(
        tester,
        TransitWidgetView(
          payload: transit(
            stops: [
              for (var s = 0; s < 5; s++)
                TransitWidgetStop(
                  name: '站 $s',
                  rows: [
                    for (var i = 0; i < 6; i++)
                      TransitWidgetRow(
                        route: '10$i',
                        towards: '往 某個很長很長的終點站名稱',
                        eta: '$i 分',
                        tone: ArrivalTone.normal,
                        favorite: false,
                      ),
                  ],
                ),
            ],
          ),
          size: const Size(320, 140),
          brightness: Brightness.light,
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}

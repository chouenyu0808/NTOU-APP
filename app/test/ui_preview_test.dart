import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/ui/app_controller.dart';
import 'package:ntou_app/src/ui/home_page.dart';
import 'package:ntou_app/src/ui/module_list_page.dart';
import 'package:ntou_app/src/ui/timetable_page.dart';
import 'package:ntou_app/src/ui/theme.dart';

import 'fake_ais.dart';

/// 以合成資料檢查手機尺寸；指定字型時另輸出可人工檢視的畫面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['NTOU_REVIEW_FONT'];
  late MenuCatalog catalog;
  setUpAll(() async {
    catalog = MenuCatalog.fromJson(
      jsonDecode(await File('assets/menu_tree.json').readAsString()) as List,
    );
    if (fontPath != null) {
      final bytes = await File(fontPath).readAsBytes();
      await (FontLoader(
        'ReviewFont',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      final iconBytes = await File(Platform.environment['NTOU_REVIEW_ICONS']!)
          .readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
    }
  });
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('手機版面不溢出：${brightness.name}、字體 $scale 倍', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = await newController();
        c.phase = AppPhase.ready;
        c.defaultYear = '115';
        c.defaultSemester = '1';
        c.year = '115';
        c.semester = '1';
        c.timetable = TimetableResult(
          year: '115',
          semester: '1',
          isEmpty: false,
          fetchedAt: DateTime(2026, 9, 14, 8, 30),
          courses: const [
            Course(
              name: '資料結構',
              teacher: '王老師',
              room: '電資 201',
              slots: [TimeSlot(0, 2), TimeSlot(0, 3)],
            ),
            Course(
              name: '離散數學',
              teacher: '李老師',
              room: '電資 302',
              slots: [TimeSlot(0, 6), TimeSlot(0, 7)],
            ),
            Course(
              name: '程式設計',
              room: '電資 101',
              slots: [TimeSlot(2, 2), TimeSlot(2, 3), TimeSlot(2, 4)],
            ),
            Course(
              name: '大學英文',
              room: '人文 202',
              slots: [TimeSlot(4, 3), TimeSlot(4, 4)],
            ),
          ],
        );

        final theme = NtouTheme.of(brightness);
        for (final entry in <String, Widget>{
          'home': HomePage(controller: c, now: DateTime(2026, 9, 14, 9, 0)),
          'services': ModuleListPage(controller: c, catalog: catalog),
          'timetable': TimetablePage(controller: c),
        }.entries) {
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: fontPath == null
                    ? theme
                    : theme.copyWith(
                        textTheme: theme.textTheme.apply(
                          fontFamily: 'ReviewFont',
                        ),
                        appBarTheme: theme.appBarTheme.copyWith(
                          titleTextStyle: theme.appBarTheme.titleTextStyle
                              ?.copyWith(fontFamily: 'ReviewFont'),
                        ),
                      ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: entry.value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (fontPath != null) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/ui-review/${entry.key}-${brightness.name}-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await unmount(tester);
        }
        c.dispose();
      });
    }
  }
}

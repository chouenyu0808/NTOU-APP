import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/form_schema.dart';
import 'package:ntou_app/src/ui/schema_field_input.dart';
import 'package:ntou_app/src/ui/theme.dart';

void main() {
  /// 把一個欄位單獨畫出來，並記下它有沒有回報過值。
  Future<List<String>> pump(
    WidgetTester tester,
    SchemaField field, {
    String value = '',
    bool enabled = true,
  }) async {
    final changed = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: Scaffold(
        body: SchemaFieldInput(
          field: field,
          value: value,
          enabled: enabled,
          onChanged: changed.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changed;
  }

  const attachment = SchemaField(
    name: 'FileUpload1',
    label: '附件',
    kind: FieldKind.file,
  );

  group('要附檔案的那一格', () {
    testWidgets('會告訴使用者這份申請要到學校網頁版送', (tester) async {
      await pump(tester, attachment);

      // 學校的名字（cname）照樣要顯示 —— 使用者得看得出是哪一格在講話。
      expect(find.text('附件'), findsOneWidget);
      expect(
        find.text('這一格要附檔案，App 還附不上 —— 這份申請請到學校網頁版送出'),
        findsOneWidget,
      );
    });

    testWidgets('不是一個可以打字的輸入框', (tester) async {
      final changed = await pump(tester, attachment);

      // 能打字的話使用者會把檔名打進去，然後送出一個伺服器看不懂的值。
      final box = tester.widget<TextField>(find.byType(TextField));
      expect(box.enabled, isFalse);
      expect(changed, isEmpty);

      // 畫面上一個字都沒有：不要讓它看起來像「已經選好檔案了」。
      expect(box.controller?.text, isEmpty);
    });
  });

  group('別的欄位不要被這句話沾到', () {
    testWidgets('一般文字欄位照樣打得了字，也不會出現那句說明', (tester) async {
      final changed = await pump(
        tester,
        const SchemaField(
          name: 'Q_CRS_NAME',
          label: '課程名稱',
          kind: FieldKind.text,
        ),
      );

      expect(find.textContaining('學校網頁版'), findsNothing);
      await tester.enterText(find.byType(TextFormField), '演算法');
      expect(changed, ['演算法']);
    });
  });
}

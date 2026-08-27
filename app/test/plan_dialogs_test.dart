import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/planner/plan_models.dart';
import 'package:ntou_app/src/ui/plan_dialogs.dart';
import 'package:ntou_app/src/ui/theme.dart';

/// 這幾個對話框以前是 planner_page.dart 裡的私有 class，所以只能透過整頁
/// 去測。「手動輸入」搬到課程瀏覽頁之後它們變成兩邊共用的，就直接對著
/// 對話框本身測 —— 開一整頁只為了驗「課名沒填要擋下來」是繞遠路。
void main() {
  /// 開一個對話框。回傳的 box 在對話框關掉之後才會有值。
  ///
  /// 分成 `value` 和 `closed` 兩個欄位：對話框可能回 `null`（按取消），
  /// 光看 `value == null` 分不出「還開著」和「取消了」。
  Future<_Box<T>> show<T>(WidgetTester tester, Widget dialog) async {
    final box = _Box<T>();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: NtouTheme.of(Brightness.light),
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.shrink());
      }),
    ));
    showDialog<T>(context: ctx, builder: (_) => dialog).then((v) {
      box.value = v;
      box.closed = true;
    });
    await tester.pumpAndSettle();
    return box;
  }

  group('AddCourseDialog', () {
    testWidgets('沒填課名會被擋下並提示，對話框不關掉', (tester) async {
      final box = await show<PlannedCourse>(tester, const AddCourseDialog());

      await tester.tap(find.widgetWithText(FilledButton, '新增'));
      await tester.pumpAndSettle();

      expect(find.text('請輸入課名'), findsOneWidget);
      expect(box.closed, isFalse);
    });

    testWidgets('填了課名就回一門 PlannedCourse', (tester) async {
      final box = await show<PlannedCourse>(tester, const AddCourseDialog());

      await tester.enterText(
          find.widgetWithText(TextFormField, '課名 *'), '離散數學');
      await tester.enterText(
          find.widgetWithText(TextFormField, '學分數（選填）'), '3');
      await tester.tap(find.widgetWithText(FilledButton, '新增'));
      await tester.pumpAndSettle();

      expect(box.value!.course.name, '離散數學');
      expect(box.value!.course.credits, 3);
      // 一個時段都沒點，就不算「使用者自己填的」——
      // 之後從學校抓到時間時才不會被當成手動值而不敢蓋掉。
      expect(box.value!.slotsAreManual, isFalse);
    });

    testWidgets('點了時段就標記成手動填的，重新查詢不要蓋掉', (tester) async {
      final box = await show<PlannedCourse>(tester, const AddCourseDialog());

      await tester.enterText(
          find.widgetWithText(TextFormField, '課名 *'), '演算法');
      // 對話框是 scrollable 的，時段格子在摺線下面 —— 不捲過去 tap 會落空。
      await tester.ensureVisible(find.bySemanticsLabel('星期一第 3 節'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('星期一第 3 節'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '新增'));
      await tester.pumpAndSettle();

      expect(box.value!.slots, const [TimeSlot(0, 3)]);
      expect(box.value!.slotsAreManual, isTrue);
    });
  });

  group('EditSlotsDialog', () {
    testWidgets('帶進去的時段是打勾的，再點一下就取消', (tester) async {
      final box = await show<List<TimeSlot>>(
        tester,
        const EditSlotsDialog(initial: [TimeSlot(0, 3)]),
      );

      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('星期一第 3 節'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '儲存'));
      await tester.pumpAndSettle();

      expect(box.value, isEmpty);
    });

    testWidgets('按取消回 null —— 「沒有改」跟「清空了」不是同一件事', (tester) async {
      // 回空清單的話呼叫端會把原本的時段清掉，而使用者按的是「取消」。
      final box = await show<List<TimeSlot>>(
        tester,
        const EditSlotsDialog(initial: [TimeSlot(0, 3)]),
      );

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(box.closed, isTrue);
      expect(box.value, isNull);
    });
  });
}

class _Box<T> {
  T? value;
  bool closed = false;
}

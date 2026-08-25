import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/form_schema.dart';
import 'package:ntou_app/src/ais/page.dart';
import 'package:ntou_app/src/data/function_view.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';
import 'package:ntou_app/src/parsing/data_grid.dart';

void main() {
  AisPage newPage() => AisPage(url: 'u', status: 200, html: '<html></html>');

  const schema =
      FunctionSchema(title: '課程課表查詢', fields: [], buttons: [], groups: []);

  FunctionView view({String functionTitle = '課程課表查詢'}) => FunctionView(
        function: AisFunction(
          title: functionTitle,
          path: 'Application/TKE/TKE22/TKE2211_.aspx',
          trail: const ['教務系統'],
        ),
        page: newPage(),
        schema: schema,
        cascadeFields: const {'Q_DEPT'},
      );

  group('title', () {
    test('優先用選單的中文名（function.title）', () {
      expect(view(functionTitle: '課程課表查詢').title, '課程課表查詢');
    });

    test('function.title 為空時退回頁面解析出的 schema.title', () {
      // 個人課表那頁 <title> 只有 TKE2240_，function.title 才是可靠來源；
      // 反過來 function.title 空的時候，schema.title 補位。
      expect(view(functionTitle: '').title, '課程課表查詢');
    });
  });

  group('needsCascade', () {
    test('欄位在 cascadeFields 裡才要連動重送', () {
      final v = view();
      expect(v.needsCascade('Q_DEPT'), isTrue);
      expect(v.needsCascade('Q_YEAR'), isFalse);
    });
  });

  group('copyWith', () {
    test('沒傳的欄位保留原值', () {
      final v = view();
      final copy = v.copyWith();
      expect(copy.function, v.function);
      expect(copy.page, v.page);
      expect(copy.schema, v.schema);
      expect(copy.cascadeFields, v.cascadeFields);
      expect(copy.values, v.values);
      expect(copy.result, isNull);
    });

    test('更新 values 與 page，其餘不動', () {
      final v = view();
      final p2 = newPage();
      final v2 = v.copyWith(values: {'Q_DEPT': 'CS'}, page: p2);
      expect(v2.values, {'Q_DEPT': 'CS'});
      expect(v2.page, same(p2));
      expect(v2.function, v.function);
    });

    test('result 帶進來就存起來', () {
      const r = DataGridResult(columns: ['課名'], rows: [
        ['演算法']
      ], isEmpty: false);
      final v2 = view().copyWith(result: r);
      expect(v2.result, same(r));
    });

    test('clearResult 把 result 清成 null，即使同時傳了新的 result', () {
      // 換頁重查前要先清掉舊結果，不能因為呼叫端手滑同時帶了 result 就清不掉。
      final withResult = view().copyWith(
        result: const DataGridResult(columns: [], rows: [], isEmpty: true),
      );
      expect(withResult.result, isNotNull);

      final cleared = withResult.copyWith(
        result: const DataGridResult(columns: [], rows: [], isEmpty: false),
        clearResult: true,
      );
      expect(cleared.result, isNull);
    });
  });
}

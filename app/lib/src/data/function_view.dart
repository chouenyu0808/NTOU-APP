import '../ais/form_schema.dart';
import '../ais/page.dart';
import '../menu/menu_catalog.dart';
import '../parsing/data_grid.dart';

/// 一個功能頁「現在的樣子」。
///
/// 這個系統是有狀態的：每次 postback 之後 `__VIEWSTATE` 會換、下拉的選項可能被
/// 重新填、結果表格可能出現。所以不能只記「使用者填了什麼」，
/// 必須把**最後一次回應的整頁**留著當下一次送出的基底。
class FunctionView {
  const FunctionView({
    required this.function,
    required this.page,
    required this.schema,
    required this.cascadeFields,
    this.result,
    this.values = const {},
  });

  final AisFunction function;

  /// 最後一次回應。下一次送出要用它的 `__VIEWSTATE`。
  final AisPage page;

  final FunctionSchema schema;

  /// 改了就要重送整張表單的欄位（AutoPostBack）。
  final Set<String> cascadeFields;

  /// 查詢結果。還沒查過就是 null —— 那跟「查了但沒資料」不一樣，
  /// UI 要分開顯示，不然使用者不知道自己按了沒。
  final DataGridResult? result;

  /// 使用者目前填的值。
  final Map<String, String> values;

  /// 顯示用的標題：頁面自己的 `<title>` 不一定有填（`TKE2240_` 就是空的），
  /// 所以以選單的中文名為準。
  String get title => function.title.isNotEmpty ? function.title : schema.title;

  bool needsCascade(String fieldName) => cascadeFields.contains(fieldName);

  FunctionView copyWith({
    AisPage? page,
    FunctionSchema? schema,
    Set<String>? cascadeFields,
    DataGridResult? result,
    Map<String, String>? values,
    bool clearResult = false,
  }) =>
      FunctionView(
        function: function,
        page: page ?? this.page,
        schema: schema ?? this.schema,
        cascadeFields: cascadeFields ?? this.cascadeFields,
        result: clearResult ? null : (result ?? this.result),
        values: values ?? this.values,
      );
}

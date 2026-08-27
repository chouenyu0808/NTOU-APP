import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_text.dart';
import 'tables.dart';

/// 分頁狀態。
///
/// 這個系統的 GridView 預設**每頁只有 10 筆**，而且翻頁是 postback。
/// 手機上一頁 10 筆幾乎沒用，所以 App 送出時會把 `PC$PageSize` 調大。
class GridPaging {
  const GridPaging({
    this.pageSizeField = 'PC\$PageSize',
    this.pageNoField = 'PC\$PageNo',
    this.pageSize = 10,
    this.pageNo = 1,
    this.lastPage = 1,
  });

  final String pageSizeField;
  final String pageNoField;
  final int pageSize;
  final int pageNo;

  /// 最後一頁的頁碼。
  ///
  /// 分頁列一次只顯示 10 個頁碼，但「>>」（跳到最後）那顆的 onclick 帶著真正的
  /// 末頁頁碼：`gotoPage('PC_PageNo', 11, 'doQuery', '5')`。
  /// 所以總頁數是讀出來的，不是從顯示的頁碼猜的。
  final int lastPage;

  bool get hasMore => lastPage > pageNo;
}

/// 一次查詢的結果表格。
///
/// 刻意不轉成具名的資料類別：50 個功能頁的欄位各不相同，硬要對應等於為每一頁
/// 寫一個 model。這裡保留學校給的欄名和欄序，UI 照著畫 ——
/// 學校加一欄，App 就多顯示一欄，不用改程式。
class DataGridResult {
  const DataGridResult({
    required this.columns,
    required this.rows,
    required this.isEmpty,
    this.paging = const GridPaging(),
  });

  final List<String> columns;
  final List<List<String>> rows;

  /// 學校明確回了「查無符合資料」。
  ///
  /// 跟 `rows.isEmpty` **不是同一件事**：後者可能是我們沒認出表格。
  /// 前者要跟使用者說「沒有資料」，後者要說「App 可能需要更新」。
  final bool isEmpty;

  final GridPaging paging;

  int get rowCount => rows.length;

  /// 轉成 表頭->值 的 map，方便挑欄位。
  List<Map<String, String>> get records => [
        for (final r in rows)
          if (r.length == columns.length)
            {for (var i = 0; i < columns.length; i++) columns[i]: r[i]},
      ];
}

final RegExp _pageSizeRe =
    RegExp(r'name="PC\$?PageSize"[^>]*value="(\d+)"', caseSensitive: false);
final RegExp _pageNoRe =
    RegExp(r'name="PC\$?PageNo"[^>]*value="(\d+)"', caseSensitive: false);

// 分頁列每一顆都是
//     gotoPage('PC_PageNo', <目標頁>, 'doQuery', '<QUERY_TYPE>')
// 「>>」（跳到最後）那顆帶的就是末頁頁碼，所以總頁數是讀出來的。
final RegExp _gotoPageRe =
    RegExp(r"gotoPage\(\s*'PC_PageNo'\s*,\s*(\d+)", caseSensitive: false);

/// 查詢結果的表格。
///
/// **id 不是每一頁都叫 `DataGrid`。** 課程查詢是 `DataGrid`，但查詢必修科目表
/// 是 **`DataGrid1`** —— 只認前者的話，那一頁在 App 裡會顯示「這一頁的結果
/// 不是表格」，而使用者用瀏覽器看明明就有一張表。
dom.Element? findDataGrid(dom.Document doc) =>
    doc.querySelector('table#DataGrid') ??
    doc.querySelector('table[id^="DataGrid"]');

/// 解析查詢結果。
///
/// 先找 `table#DataGrid`（這個系統所有查詢結果都用這個 id），
/// 找不到才退回「表頭關鍵字比對」的啟發式。
DataGridResult parseDataGrid(String html) {
  final empty = isEmptyResult(html);
  final doc = html_parser.parse(html);
  final table = findDataGrid(doc);

  var rows = <List<String>>[];
  if (table != null) {
    for (final tr in table.querySelectorAll('tr')) {
      final cells =
          tr.querySelectorAll('td, th').map((c) => clean(c.text)).toList();
      if (cells.isNotEmpty) rows.add(cells);
    }
  }

  final columns = rows.isEmpty ? <String>[] : rows.first;
  final body = rows.isEmpty
      ? <List<String>>[]
      : rows
          .skip(1)
          // 分頁列和合計列的欄數跟表頭不同，塞進去只會是垃圾
          .where((r) => r.length == columns.length)
          .toList();

  return DataGridResult(
    columns: columns,
    rows: body,
    isEmpty: empty,
    paging: GridPaging(
      pageSize: int.tryParse(_pageSizeRe.firstMatch(html)?.group(1) ?? '') ?? 10,
      pageNo: int.tryParse(_pageNoRe.firstMatch(html)?.group(1) ?? '') ?? 1,
      lastPage: _gotoPageRe
          .allMatches(html)
          .map((m) => int.tryParse(m.group(1)!) ?? 1)
          .fold(1, (a, b) => a > b ? a : b),
    ),
  );
}

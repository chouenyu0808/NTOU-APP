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
    this.actions = const [],
    this.paging = const GridPaging(),
  });

  /// 第 [row] 列第 [col] 欄上的動作，沒有就回 null。
  RowAction? actionAt(int row, int col) =>
      row < actions.length ? actions[row][col] : null;

  final List<String> columns;
  final List<List<String>> rows;

  /// 每一列上可以按的東西：**欄索引 → 動作**。跟 [rows] 等長、一一對應。
  ///
  /// 為什麼另外開一個而不是把 [rows] 變成富型別：50 個功能頁共用這一份解析，
  /// 絕大多數頁面一顆動作鈕都沒有。動作是少數頁面的加料，不是每一列的本質。
  final List<Map<int, RowAction>> actions;

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

/// 這一頁上**所有**的結果表格。
///
/// 線上加退選一頁有兩張：`DataGrid1` 是可加選的課（加選 / 詳），
/// `DataGrid3` 是已選上的課（退選）。只取第一張的話，
/// **整個「退選」功能在 App 裡等於不存在** —— 而使用者用瀏覽器看明明就有。
///
/// 順序照文件順序，畫面上就照這個順序疊。
List<dom.Element> findDataGrids(dom.Document doc) {
  final exact = doc.querySelector('table#DataGrid');
  if (exact != null) return [exact];
  return doc.querySelectorAll('table[id^="DataGrid"]');
}

/// 解析這一頁上所有的結果表格。
///
/// 只有一張時跟 [parseDataGrid] 等價。空表格（連表頭都沒有）不收 ——
/// 那多半是版面用的 table，不是結果。
List<DataGridResult> parseDataGrids(String html) {
  final doc = html_parser.parse(html);
  final tables = findDataGrids(doc);
  if (tables.length <= 1) return [parseDataGrid(html)];

  final empty = isEmptyResult(html);
  final paging = _pagingOf(html);
  return [
    for (final t in tables) ?_resultOf(t, empty: empty, paging: paging),
  ];
}

/// 解析查詢結果。
///
/// 先找 `table#DataGrid`（這個系統所有查詢結果都用這個 id），
/// 找不到才退回「表頭關鍵字比對」的啟發式。
DataGridResult parseDataGrid(String html) {
  final doc = html_parser.parse(html);
  final table = findDataGrid(doc);
  final empty = isEmptyResult(html);
  final paging = _pagingOf(html);

  return table == null
      ? DataGridResult(
          columns: const [], rows: const [], isEmpty: empty, paging: paging)
      : (_resultOf(table, empty: empty, paging: paging) ??
          DataGridResult(
              columns: const [], rows: const [], isEmpty: empty, paging: paging));
}

/// 一張表格 → 一份結果。連表頭都沒有就回 null。
DataGridResult? _resultOf(
  dom.Element table, {
  required bool empty,
  required GridPaging paging,
}) {
  final rows = <List<String>>[];
  final rowActions = <Map<int, RowAction>>[];
  for (final tr in table.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td, th');
    if (tds.isEmpty) continue;
    rows.add([for (final c in tds) clean(c.text)]);
    rowActions.add({
      for (var i = 0; i < tds.length; i++) i: ?_actionIn(tds[i]),
    });
  }
  if (rows.isEmpty) return null;

  final columns = rows.first;
  // 分頁列和合計列的欄數跟表頭不同，塞進去只會是垃圾。
  // **動作要跟著同一個條件濾**，不然兩份索引會錯開一列 ——
  // 那會讓「加選」按到別門課，而畫面上完全看不出來。
  final keep = <int>[
    for (var i = 1; i < rows.length; i++)
      if (rows[i].length == columns.length) i,
  ];

  return DataGridResult(
    columns: columns,
    rows: [for (final i in keep) rows[i]],
    actions: [for (final i in keep) rowActions[i]],
    isEmpty: empty,
    paging: paging,
  );
}

GridPaging _pagingOf(String html) => GridPaging(
      pageSize: int.tryParse(_pageSizeRe.firstMatch(html)?.group(1) ?? '') ?? 10,
      pageNo: int.tryParse(_pageNoRe.firstMatch(html)?.group(1) ?? '') ?? 1,
      lastPage: _gotoPageRe
          .allMatches(html)
          .map((m) => int.tryParse(m.group(1)!) ?? 1)
          .fold(1, (a, b) => a > b ? a : b),
    );

// ---------- 列上的動作鈕（加選 / 退選 / 詳） ----------

/// 唯讀動作的 id 後綴。`DataGrid1_ctl02_dolink` 是「詳」，只是換一頁看內容。
///
/// **認不出來的一律當成會改資料**（見 [RowAction.mutating]）——
/// 學校哪天多一顆我們沒看過的鈕，最壞的情況是多問使用者一次，
/// 而不是替他按下一個他沒想按的東西。
const String kReadOnlyActionSuffix = '_dolink';

/// 一列上可以按的東西。
///
/// 真實的標記（線上加退選，2026-09-03 抓的頁面）：
/// ```html
/// <a id="DataGrid1_ctl02_edit" ML="CL_加選"
///    onclick="return doAddClick('DataGrid1_ctl02_edit','1','0','B',1);…"
///    KEY="PKNO|…|SEG|102,103,104|COSID|B57031EC|CH_LESSON|資訊安全實務與管理|…"
///    href="javascript:__doPostBack('DataGrid1$ctl02$edit','')">加選</a>
/// ```
class RowAction {
  const RowAction({
    required this.label,
    required this.target,
    required this.mutating,
    this.data = const {},
  });

  /// 按鈕上的字（`加選`、`退選`、`詳`）。
  final String label;

  /// `__doPostBack` 的目標（`DataGrid1$ctl02$edit`）。
  ///
  /// **不要自己組。** 那串 id 是 ASP.NET 依列數編的，而且濾掉分頁列之後
  /// 列號跟畫面上的順序對不起來。
  final String target;

  /// 按下去會不會改到學校那邊的資料。真的會的話按之前一定要問。
  final bool mutating;

  /// 這一列的 `KEY` 屬性拆出來的東西。
  ///
  /// 學校把整筆課程資料塞在這裡，所以不用再打一次伺服器就知道：
  /// `SEG`（上課時間代碼）、`CRD`（學分）、`LECTR_TCH_CH`（老師）、
  /// `MAX_ST`（人數上限）、`IS_CAN_INS`（能不能加選）、`INS_INFO`（加選須知）。
  final Map<String, String> data;

  /// 學校自己就說這門不能加。
  bool get blocked => data['IS_CAN_INS'] == '0';

  /// 加選須知。有的話按之前要讓使用者看到 ——
  /// 「須於實習前至系辦完成實習申請流程」這種話，事後才看到就太晚了。
  String get notice => data['IS_INS_INFO'] == '1' ? (data['INS_INFO'] ?? '') : '';

  /// 課名，拿來做確認對話框的標題。
  String get courseName => data['CH_LESSON'] ?? '';
}

/// 這一格裡有沒有可以按的東西。
RowAction? _actionIn(dom.Element cell) {
  for (final a in cell.querySelectorAll('a')) {
    final target = _postBackTargetOf(a.attributes['href'] ?? '');
    if (target == null) continue;

    final id = a.attributes['id'] ?? '';
    return RowAction(
      label: clean(a.text),
      target: target,
      mutating: !id.endsWith(kReadOnlyActionSuffix),
      data: _parseKeyAttr(a.attributes['KEY'] ?? a.attributes['key'] ?? ''),
    );
  }
  return null;
}

/// `javascript:__doPostBack('DataGrid1$ctl02$edit','')` → `DataGrid1$ctl02$edit`。
///
/// 走屬性值而不是對原始 HTML 下正則：頁面上的引號是 `&#39;`，
/// 拿正則比原始碼一列都對不到（跟 `courseDetailTarget` 同一個坑）。
String? _postBackTargetOf(String href) =>
    RegExp(r"""__doPostBack\(\s*['"]([^'"]+)""").firstMatch(href)?.group(1);

/// `KEY="k|v|k|v|…"`。值可以是空的（`IS_STOP||IS_CHECK_MAX|1`）。
Map<String, String> _parseKeyAttr(String raw) {
  if (raw.isEmpty) return const {};
  final parts = raw.split('|');
  return {
    for (var i = 0; i + 1 < parts.length; i += 2) parts[i]: parts[i + 1],
  };
}

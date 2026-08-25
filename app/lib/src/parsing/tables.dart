import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'html_text.dart';

/// 把頁面上每個 `<table>` 轉成 rows x cells 的純文字二維陣列。
/// WebForms 的 GridView / DataGrid 都吃這招。
List<List<List<String>>> extractTables(String html) {
  final doc = html_parser.parse(html);
  final tables = <List<List<String>>>[];
  for (final table in doc.querySelectorAll('table')) {
    final rows = <List<String>>[];
    for (final tr in table.querySelectorAll('tr')) {
      final cells = tr
          .querySelectorAll('td, th')
          .map((td) => clean(td.text))
          .toList();
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isNotEmpty) tables.add(rows);
  }
  return tables;
}

/// 第一列當表頭，其餘轉 map。
/// **欄數不符的列直接跳過** —— 那通常是分頁列或合計列，硬塞進去只會產生垃圾資料。
List<Map<String, String>> tableToRecords(
  List<List<String>> rows, {
  int headerRow = 0,
}) {
  if (rows.length <= headerRow) return const [];
  final header = rows[headerRow];
  final out = <Map<String, String>>[];
  for (final row in rows.skip(headerRow + 1)) {
    if (row.length != header.length) continue;
    out.add({for (var i = 0; i < header.length; i++) header[i]: row[i]});
  }
  return out;
}

/// 挑出表頭同時含有這些字的表格。
///
/// 比 nth-child 選擇器耐改版 —— 學校在旁邊加一個 `<div>` 不會害你抓錯表。
List<List<String>>? pickTable(String html, List<String> mustContain) {
  for (final rows in extractTables(html)) {
    final head = rows.first.join(' ');
    if (mustContain.every(head.contains)) return rows;
  }
  return null;
}

/// 表頭 -> 值，容許部分比對。
///
/// 同一個欄位在不同頁面的表頭字串常常差一兩個字（「課名」/「課程名稱」/
/// 「科目名稱」），所以給幾個候選，先試完全相符再試包含。
String firstOf(Map<String, String> rec, List<String> keys) {
  for (final k in keys) {
    final v = rec[k];
    if (v != null) return v;
  }
  for (final k in keys) {
    for (final e in rec.entries) {
      if (e.key.contains(k)) return e.value;
    }
  }
  return '';
}

double? toDouble(String? text) {
  final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(text ?? '');
  return m == null ? null : double.tryParse(m.group(0)!);
}

// ---------- 表格格線（rowspan / colspan） ----------

int _span(dom.Element cell, String attr) {
  final raw = (cell.attributes[attr] ?? '1').trim();
  final n = int.tryParse(raw) ?? 1;
  return n < 1 ? 1 : n;
}

/// 把含 rowspan / colspan 的 `<table>` 攤平成規則的二維陣列。
///
/// 被跨欄／跨列涵蓋的每一格都放**同一個** cell 物件，
/// 所以呼叫端可以用 `identical()` 判斷「這幾格是同一堂課」。
///
/// **課表非做不可**：連堂課是用 rowspan 表示的，照位置逐格讀的話，
/// 兩小時的課只會出現在第一節 —— 課表就是錯的，而且錯得很安靜
/// （看起來完全正常，只是課提早一小時結束）。
List<List<dom.Element?>> expandGrid(dom.Element table) {
  final grid = <List<dom.Element?>>[];

  List<dom.Element?> ensureRow(int r) {
    while (grid.length <= r) {
      grid.add(<dom.Element?>[]);
    }
    return grid[r];
  }

  void place(int r, int c, dom.Element cell) {
    final row = ensureRow(r);
    while (row.length <= c) {
      row.add(null);
    }
    row[c] = cell;
  }

  final rows = table.querySelectorAll('tr');
  for (var r = 0; r < rows.length; r++) {
    // 先看直接子元素；有些頁面把 td 包在 tbody 底下，那時退回全域搜尋
    var cells = rows[r]
        .children
        .where((e) => e.localName == 'td' || e.localName == 'th')
        .toList();
    if (cells.isEmpty) cells = rows[r].querySelectorAll('td, th');

    final row = ensureRow(r);
    var col = 0;
    for (final cell in cells) {
      // 這一格已經被上面的 rowspan 佔住了，往右找
      while (col < row.length && row[col] != null) {
        col++;
      }
      final rs = _span(cell, 'rowspan');
      final cs = _span(cell, 'colspan');
      for (var dr = 0; dr < rs; dr++) {
        for (var dc = 0; dc < cs; dc++) {
          place(r + dr, col + dc, cell);
        }
      }
      col += cs;
    }
  }

  final width = grid.fold<int>(0, (w, row) => row.length > w ? row.length : w);
  for (final row in grid) {
    while (row.length < width) {
      row.add(null);
    }
  }
  return grid;
}

/// 格線轉純文字，方便肉眼比對。跨格的內容會在每一格重複出現。
List<List<String>> gridText(List<List<dom.Element?>> grid) => [
      for (final row in grid) [for (final c in row) c == null ? '' : clean(c.text)],
    ];

/// 查詢頁沒資料時回的訊息。**狀態碼一樣是 200**，頁面結構完全正常，
/// 只有這一行字不一樣 —— 不認得的話會以為 parser 壞了，然後去 debug 錯的東西。
const List<String> kEmptyResultMarkers = [
  '查無符合資料',
  'There is no matching data',
];

/// 這次查詢是不是「沒有資料」。
///
/// 「空結果」和「解析失敗」要分得開，這是兩件完全不同的事：
/// 前者要跟使用者說「這學期沒有修課紀錄」，後者要說「App 需要更新」。
bool isEmptyResult(String html) => kEmptyResultMarkers.any(html.contains);

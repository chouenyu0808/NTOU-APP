import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/data_grid.dart';

void main() {
  group('parseDataGrid & GridPaging', () {
    test('解析標準 DataGrid 表格與欄位', () {
      const html = '''
      <html>
        <body>
          <table id="DataGrid">
            <tr>
              <th>學號</th>
              <th>姓名</th>
              <th>系所</th>
            </tr>
            <tr>
              <td>B11234567</td>
              <td>王小明</td>
              <td>資工系</td>
            </tr>
            <tr>
              <td>B11234568</td>
              <td>李小華</td>
              <td>電機系</td>
            </tr>
          </table>
        </body>
      </html>
      ''';

      final result = parseDataGrid(html);

      expect(result.isEmpty, isFalse);
      expect(result.columns, ['學號', '姓名', '系所']);
      expect(result.rowCount, 2);
      expect(result.rows[0], ['B11234567', '王小明', '資工系']);
      expect(result.rows[1], ['B11234568', '李小華', '電機系']);

      final records = result.records;
      expect(records.length, 2);
      expect(records[0], {'學號': 'B11234567', '姓名': '王小明', '系所': '資工系'});
      expect(records[1], {'學號': 'B11234568', '姓名': '李小華', '系所': '電機系'});
    });

    test('過濾欄位數與表頭不相符的列（如合計列或分頁列）', () {
      const html = '''
      <html>
        <body>
          <table id="DataGrid">
            <tr>
              <th>代碼</th>
              <th>名稱</th>
            </tr>
            <tr>
              <td>A01</td>
              <td>必修</td>
            </tr>
            <tr>
              <td colspan="2">共 1 筆資料（合計列）</td>
            </tr>
          </table>
        </body>
      </html>
      ''';

      final result = parseDataGrid(html);
      expect(result.columns, ['代碼', '名稱']);
      expect(result.rowCount, 1);
      expect(result.rows.single, ['A01', '必修']);
    });

    test('無 table#DataGrid 時回傳空欄位與空資料列', () {
      const html = '<html><body><div>沒有表格</div></body></html>';
      final result = parseDataGrid(html);
      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
      expect(result.rowCount, 0);
      expect(result.records, isEmpty);
      expect(result.isEmpty, isFalse);
    });

    test('學校回「查無符合資料」時標記 isEmpty 為 true', () {
      const html = '''
      <html>
        <body>
          <span>查無符合資料</span>
        </body>
      </html>
      ''';

      final result = parseDataGrid(html);
      expect(result.isEmpty, isTrue);
      expect(result.rowCount, 0);
    });

    test('解析分頁狀態 (PageSize, PageNo, lastPage, hasMore)', () {
      const html = '''
      <html>
        <body>
          <input type="hidden" name="PC\$PageSize" value="20" />
          <input type="hidden" name="PC\$PageNo" value="2" />
          <table id="DataGrid">
            <tr><th>標題</th></tr>
            <tr><td>內容</td></tr>
          </table>
          <a href="javascript:gotoPage('PC_PageNo', 1, 'doQuery', '1')">1</a>
          <a href="javascript:gotoPage('PC_PageNo', 2, 'doQuery', '1')">2</a>
          <a href="javascript:gotoPage('PC_PageNo', 5, 'doQuery', '5')">&gt;&gt;</a>
        </body>
      </html>
      ''';

      final result = parseDataGrid(html);
      final paging = result.paging;

      expect(paging.pageSize, 20);
      expect(paging.pageNo, 2);
      expect(paging.lastPage, 5);
      expect(paging.hasMore, isTrue);
    });

    test('末頁時 hasMore 為 false', () {
      const html = '''
      <html>
        <body>
          <input type="hidden" name="PC\$PageSize" value="10" />
          <input type="hidden" name="PC\$PageNo" value="5" />
          <a href="javascript:gotoPage('PC_PageNo', 5, 'doQuery', '5')">5</a>
        </body>
      </html>
      ''';

      final result = parseDataGrid(html);
      expect(result.paging.pageNo, 5);
      expect(result.paging.lastPage, 5);
      expect(result.paging.hasMore, isFalse);
    });
  });
}

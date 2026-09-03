import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/data_grid.dart';

import 'fixtures.dart';

/// 對著真實的「線上加退選」頁面測（2026-09-03 抓）。
const String _fixture = 'Application_TKE_TKE20_TKE2011_01.html';

bool _has() => File('${fixturesDir.path}/$_fixture').existsSync();

void main() {
  group('線上加退選的動作鈕（真實頁面）', () {
    late DataGridResult r;

    setUpAll(() {
      if (fixturesAvailable && _has()) r = parseDataGrid(fixture(_fixture));
    });

    test('前兩欄是動作欄，每一列都有加選和詳', () {
      if (!_has()) return;
      expect(r.rows, isNotEmpty);

      final first = r.actionAt(0, 0);
      expect(first, isNotNull);
      expect(first!.label, '加選');
      expect(first.target, 'DataGrid1\$ctl02\$edit');
      expect(first.mutating, isTrue);

      final detail = r.actionAt(0, 1);
      expect(detail!.label, '詳');
      expect(detail.target, 'DataGrid1\$ctl02\$dolink');
      // 「詳」只是換一頁看內容，不該問使用者要不要送出
      expect(detail.mutating, isFalse);
    }, skip: skipReason);

    test('KEY 屬性帶著整筆課程資料，不用再打一次伺服器', () {
      if (!_has()) return;
      final a = r.actionAt(0, 0)!;

      expect(a.courseName, '資訊安全實務與管理');
      expect(a.data['COSID'], 'B57031EC');
      expect(a.data['CRD'], '3');
      expect(a.data['LECTR_TCH_CH'], '傅湘源');
      expect(a.data['MAX_ST'], '50');
      // SEG 就是上課時間代碼 —— 週一 2、3、4 節
      expect(a.data['SEG'], '102,103,104');
    }, skip: skipReason);

    test('學校說不能加的那門認得出來', () {
      if (!_has()) return;
      // 企業實習：IS_CAN_INS|0，須先到系辦完成實習申請
      final internship = [
        for (var i = 0; i < r.rows.length; i++)
          if (r.actionAt(i, 0)?.courseName == '企業實習') r.actionAt(i, 0)!,
      ];
      expect(internship, hasLength(1));
      expect(internship.single.blocked, isTrue);
      expect(internship.single.notice, contains('系辦'));
    }, skip: skipReason);

    test('動作跟課號同一列，沒有錯開', () {
      if (!_has()) return;
      // 這是最要命的一種錯：動作錯開一列，「加選」就會加到別門課，
      // 而畫面上完全看不出來（每一列都有鈕、看起來很正常）。
      final codeCol = r.columns.indexOf('課號');
      expect(codeCol, greaterThan(0));

      for (var i = 0; i < r.rows.length; i++) {
        final a = r.actionAt(i, 0);
        if (a == null || a.data['COSID'] == null) continue;
        expect(a.data['COSID'], r.rows[i][codeCol], reason: '第 $i 列');
      }
    }, skip: skipReason);
  });

  group('一頁兩張表（真實頁面）', () {
    test('可加選的課和已選上的課都要解析出來', () {
      if (!_has()) return;
      final grids = parseDataGrids(fixture(_fixture));

      // DataGrid1 = 可加選（加選 / 詳）、DataGrid3 = 已選上（退選）。
      // 只取第一張的話，整個「退選」功能在 App 裡等於不存在。
      expect(grids, hasLength(2));
      expect(grids[0].columns, contains('選別'));
      expect(grids[1].columns, contains('課號'));

      final drop = grids[1].actionAt(0, 0);
      expect(drop, isNotNull);
      expect(drop!.label, '退選');
      expect(drop.mutating, isTrue, reason: '退選會改資料，按之前一定要問');
    }, skip: skipReason);

    test('已選上的那張就是使用者這學期的三門課', () {
      if (!_has()) return;
      final grids = parseDataGrids(fixture(_fixture));
      expect(grids[1].rows, hasLength(3));
    }, skip: skipReason);

    test('只有一張表的頁面照舊', () {
      final grids = parseDataGrids(
        '<table id="DataGrid"><tr><td>課號</td></tr><tr><td>B1</td></tr></table>',
      );
      expect(grids, hasLength(1));
    });
  });

  group('動作解析（合成頁面）', () {
    DataGridResult parse(String body) => parseDataGrid(
          '<table id="DataGrid1">'
          '<tr><td>&nbsp;</td><td>課號</td></tr>$body</table>',
        );

    test('引號是 HTML 實體也讀得出目標', () {
      // 頁面上寫的是 &#39; —— 拿正則比原始 HTML 一列都對不到。
      final r = parse(
        '<tr><td><a id="G_ctl02_edit" '
        'href="javascript:__doPostBack(&#39;G\$ctl02\$edit&#39;,&#39;&#39;)">加選</a></td>'
        '<td>B123</td></tr>',
      );
      expect(r.actionAt(0, 0)!.target, 'G\$ctl02\$edit');
    });

    test('認不出來的鈕當成會改資料 —— 寧可多問一次', () {
      final r = parse(
        '<tr><td><a id="G_ctl02_whatever" '
        'href="javascript:__doPostBack(&#39;G\$ctl02\$whatever&#39;,&#39;&#39;)">？</a></td>'
        '<td>B123</td></tr>',
      );
      expect(r.actionAt(0, 0)!.mutating, isTrue);
    });

    test('沒有 postback 的連結不算動作', () {
      final r = parse('<tr><td><a href="https://x.example">說明</a></td>'
          '<td>B123</td></tr>');
      expect(r.actionAt(0, 0), isNull);
    });

    test('KEY 裡的空值不會讓後面的欄位整個偏移', () {
      final r = parse(
        '<tr><td><a id="G_ctl02_edit" KEY="A|1|B||C|3" '
        'href="javascript:__doPostBack(&#39;G\$ctl02\$edit&#39;,&#39;&#39;)">加選</a></td>'
        '<td>B123</td></tr>',
      );
      expect(r.actionAt(0, 0)!.data, {'A': '1', 'B': '', 'C': '3'});
    });

    test('沒有動作的頁面照常解析，actions 是空的', () {
      final r = parse('<tr><td>x</td><td>B123</td></tr>');
      expect(r.rows, hasLength(1));
      expect(r.actionAt(0, 0), isNull);
    });
  });
}

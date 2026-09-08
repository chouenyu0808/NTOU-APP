import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';

/// 選單目錄。資料來自 spike 遞迴展開整棵 TreeView 抓下來的 131 個功能。
///
/// **2026-09-07 重抓：50 → 131 個。** 學校一次上架了整個成績系統（`GRD`
/// 模組，舊選單裡完全沒有）、教育學程、職涯發展、獎助學金等 13 個新模組。
void main() {
  final file = File('assets/menu_tree.json');
  final catalog = MenuCatalog.fromJson(
    jsonDecode(file.readAsStringSync()) as List,
  );

  test('131 個功能全部讀得到', () {
    expect(catalog.functions.length, 131);
    expect(catalog.functions.every((f) => f.path.isNotEmpty), isTrue);
    expect(catalog.functions.every((f) => f.title.isNotEmpty), isTrue);
  });

  test('26 個模組，順序跟網頁選單一致', () {
    // 使用者看到的第一層就是這 26 個。順序照選單原本的，不要自己排序 ——
    // 排序過的清單跟網頁對不起來，使用者要重新找。
    expect(catalog.modules, [
      '教務系統',
      '學生證補發作業',
      '暑修作業',
      '職涯發展',
      '學生宿舍管理系統',
      '學生宿舍修繕系統',
      '校外租賃訊息管理',
      '導師工作-班級系統',
      '就學貸款-減免補助',
      '學生團體保險',
      '獎助學金管理',
      '學習助學金系統',
      '學生請假',
      '獎懲-操行管理',
      '遺失物-拾獲物管理',
      '問卷調查系統',
      '學生社團活動資訊系統',
      '五育護照',
      '學生兵役管理',
      '新生體檢收件作業',
      '體育室辦證系統',
      'SDGs',
      '教育學程作業',
      '網路服務申請',
      '電子公布欄',
      '連結校內資訊系統',
    ]);
  });

  test('成績系統整組在教務系統底下', () {
    // 這一組是 2026-09-07 才出現的。在那之前 selectors.json 裡寫著
    // 「成績查詢不在這個系統的學生選單裡，50 個功能全部檢查過」。
    final grades = catalog.groupsOf('教務系統')['成績系統']!;
    expect(grades.map((f) => f.title), containsAll(<String>[
      '查詢各式成績',
      '查詢當學期成績預警',
      '查詢缺曠課紀錄',
    ]));

    // 「成績系統」這個分組**不是全部唯讀** —— 底下混著兩個申請頁。
    // 整組當成查詢放行的話，使用者會在「看成績」的心情下誤送申請。
    //
    // 這裡用的是**檔名**代碼（`byCode` 認的是那個），progcd 是另一組：
    // 例如「查詢各式成績」progcd=STU2020 但檔名是 GRD5010。
    for (final code in ['GRD5010', 'GRD3060', 'GRD7050', 'TKE2250']) {
      expect(catalog.byCode(code)!.mutating, isFalse, reason: code);
    }
    for (final code in ['ENRA200', 'MAP0006']) {
      expect(catalog.byCode(code)!.mutating, isTrue, reason: code);
    }
  });

  group('新選單帶進來的路徑形狀', () {
    test('副檔名大寫也要抽得出代碼', () {
      // 131 個功能裡只有「填寫問卷」是 `QUE2010_.ASPX`。regex 沒有
      // caseSensitive: false 的話它的 code 是空字串，byCode 永遠查不到，
      // 而畫面上只是「這個功能點進去沒反應」。
      final q = catalog.functions.firstWhere((f) => f.title == '填寫問卷');
      expect(q.path, contains('.ASPX'));
      expect(q.code, 'QUE2010');
      expect(q.mutating, isTrue); // 問卷送出去不能改
    });

    test('共用同一支 aspx 的 12 個功能靠 PAGETYPE 分得開', () {
      // 全部都是 TKE2070_01.aspx?PAGETYPE=xxx。用檔名的話 12 個代碼一模一樣，
      // byCode 隨便回一個，而且畫面上看不出來拿錯了。
      final shared = catalog.functions
          .where((f) => f.path.contains('TKE2070_01.aspx'))
          .toList();
      expect(shared.length, 12);
      expect(shared.map((f) => f.code).toSet().length, 12);
      expect(catalog.byCode('TKE2080')!.title, '選課學分超過上限學生名單查詢');
    });

    test('那 12 個就是系辦報表，而且全部落在選課系統', () {
      final staff = catalog.functions.where((f) => f.staffOnly).toList();
      expect(staff.length, 12);

      // 它們全部集中在同一組 —— 所以「選課系統」26 個項目裡有 12 個是
      // 學生看不懂也用不到的行政統計，那一組看起來像是壞的。
      expect(staff.map((f) => f.group).toSet(), {'選課系統'});
      expect(catalog.groupsOf('教務系統')['選課系統']!.length, 26);

      // 系辦報表全是查詢，不該有任何一個被標成會送出資料 ——
      // 收進摺疊區的東西如果還掛著警告，等於把警告也藏起來了。
      expect(staff.any((f) => f.mutating), isFalse);
    });
  });

  test('選課那一整組都擋著', () {
    // 舊選單只有「線上加退選」一個入口，新選單把整條流程都放出來了。
    // 期中退選的檔名是 TKE2050、progcd 是 STU1050 —— 比對的是整個 path，
    // 所以清單裡寫哪一個都會中。
    for (final code in ['TKE2011', 'TKE2020', 'TKE2030', 'TKE2040', 'TKE2050']) {
      final f = catalog.byCode(code);
      expect(f, isNotNull, reason: '$code 不在選單裡了');
      expect(f!.mutating, isTrue, reason: '${f.title} ($code)');
    }
    expect(catalog.byCode('TKE2050')!.mutationWarning, contains('加不回來'));
  });

  test('模組底下保留子分組的層次', () {
    final groups = catalog.groupsOf('教務系統');
    expect(groups.keys, contains('選課系統'));
    expect(
      groups['選課系統']!.map((f) => f.title),
      contains('課程課表查詢'),
    );
  });

  test('功能代碼抓得出來', () {
    final f = catalog.functions
        .firstWhere((f) => f.path.contains('TKE2211'));
    expect(f.code, 'TKE2211');
    expect(f.module, '教務系統');
  });

  group('會改資料的功能', () {
    test('線上加退選被標成 mutating', () {
      // 選課期間誤觸一次，後果不是重跑一次能解決的
      final f = catalog.byCode('TKE2011')!;
      expect(f.title, '線上加退選');
      expect(f.mutating, isTrue);
      expect(f.mutationWarning, contains('加選或退選'));
    });

    test('申請休退學、修改密碼也是', () {
      expect(catalog.byCode('ENRD140')!.mutating, isTrue);
      final pwd = catalog.functions
          .firstWhere((f) => f.path.contains('PWD1020'));
      expect(pwd.mutating, isTrue);
      expect(pwd.mutationWarning, contains('密碼'));
    });

    test('純查詢的功能不會被誤標', () {
      // 誤標的代價是每次查課表都跳一個嚇人的警告，久了就沒人看警告了
      expect(catalog.byCode('TKE2211')!.mutating, isFalse); // 課程課表查詢
      expect(catalog.byCode('TKE2240')!.mutating, isFalse); // 個人課表
      expect(catalog.byCode('ENRA120')!.mutating, isFalse); // 必修科目表
      expect(catalog.byCode('SEC2050')!.mutating, isFalse); // 請假查詢
      expect(catalog.byCode('BBS3010')!.mutating, isFalse); // 公告訊息查詢
    });

    test('請假的申請/取消/刪除是 mutating，查詢/列印不是', () {
      expect(catalog.byCode('SEC6000')!.mutating, isTrue); // 申請
      expect(catalog.byCode('SEC2020')!.mutating, isTrue); // 取消
      expect(catalog.byCode('SEC2030')!.mutating, isTrue); // 刪除
      expect(catalog.byCode('SEC2050')!.mutating, isFalse); // 查詢
      expect(catalog.byCode('SEC2090')!.mutating, isFalse); // 列印證明聯
    });
  });

  test('頂層的單獨功能不混進模組裡', () {
    final titles = catalog.standalone.map((f) => f.title);
    expect(titles, contains('修改密碼'));
    expect(titles, contains('登入記錄查詢'));
    // 它們沒有上層模組，所以不該出現在任何模組的清單中
    for (final m in catalog.modules) {
      expect(catalog.inModule(m).map((f) => f.title), isNot(contains('修改密碼')));
    }
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';

/// 選單目錄。資料來自 spike 遞迴展開整棵 TreeView 抓下來的 50 個功能。
void main() {
  final file = File('assets/menu_tree.json');
  final catalog = MenuCatalog.fromJson(
    jsonDecode(file.readAsStringSync()) as List,
  );

  test('50 個功能全部讀得到', () {
    expect(catalog.functions.length, 50);
    expect(catalog.functions.every((f) => f.path.isNotEmpty), isTrue);
    expect(catalog.functions.every((f) => f.title.isNotEmpty), isTrue);
  });

  test('13 個模組，順序跟網頁選單一致', () {
    // 使用者看到的第一層就是這 13 個。順序照選單原本的，不要自己排序 ——
    // 排序過的清單跟網頁對不起來，使用者要重新找。
    expect(catalog.modules, [
      '教務系統',
      '暑修作業',
      '學生宿舍管理系統',
      '校外租賃訊息管理',
      '就學貸款-減免補助',
      '學生請假',
      '學生社團活動資訊系統',
      '學生兵役管理',
      '新生體檢收件作業',
      '體育室辦證系統',
      'SDGs',
      '電子公布欄',
      '連結校內資訊系統',
    ]);
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

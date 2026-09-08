import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/announcements.dart';

import 'fixtures.dart';

void main() {
  group('電子公布欄', () {
    const row = '<div class="msg-list">'
        '<a href="javascript:void(0);" '
        'onclick="return openBbsAnnouncement(\'9005901\');" class="d-block">'
        '<span><i class="ri-calendar-event-fill"></i>115/08/26</span>'
        '<span class="msg-subj">學生宿舍開放入住首二日</span>'
        '<span class="bbs-unit"><i class="ri-building-line"></i>'
        '<span>學務處住宿輔導組</span></span>'
        '</a></div>';

    test('日期、標題、單位、公告編號都讀得出來', () {
      final a = parseAnnouncements('<div id="BBS_BLOCK">$row</div>').single;

      expect(a.title, '學生宿舍開放入住首二日');
      expect(a.unit, '學務處住宿輔導組');
      expect(a.id, '9005901');
      // 民國 115 = 西元 2026
      expect(a.date, DateTime(2026, 8, 26));
    });

    test('標題裡的日期不能被當成發布日期', () {
      // 公告標題常常自己就含日期。抓錯的話排序會整個亂掉，
      // 而畫面上看起來完全正常 —— 只是順序不對。
      const tricky = '<div class="msg-list">'
          '<a onclick="return openBbsAnnouncement(\'1\');">'
          '<span>115/08/11</span>'
          '<span class="msg-subj">115/09/30 前請完成繳費</span>'
          '</a></div>';

      final a = parseAnnouncements('<div id="BBS_BLOCK">$tricky</div>').single;
      expect(a.date, DateTime(2026, 8, 11));
    });

    test('沒有公布欄區塊時回空的，不要爆掉', () {
      expect(parseAnnouncements('<html><body>沒有公告</body></html>'), isEmpty);
    });

    test('沒有標題的列直接跳過', () {
      const empty = '<div class="msg-list"><a><span>115/08/26</span></a></div>';
      expect(parseAnnouncements('<div id="BBS_BLOCK">$empty</div>'), isEmpty);
    });
  });

  group('真實的入口頁', () {
    final missing = File('${fixturesDir.path}/Portal.html').existsSync()
        ? null
        : '沒有 Portal.html';

    test('登入握手載到的那一頁上就有公告，不用另外開 BBS3010', () {
      final list = parseAnnouncements(fixture('Portal.html'));

      expect(list, isNotEmpty);
      // 每一則都要有標題和單位 —— 少了單位的話使用者不知道那是誰發的
      expect(list.every((a) => a.title.isNotEmpty), isTrue);
      expect(list.every((a) => a.unit.isNotEmpty), isTrue);
      expect(list.every((a) => a.id.isNotEmpty), isTrue);
      expect(list.every((a) => a.date != null), isTrue);

      // **這裡刻意不對特定某一則做斷言。**
      //
      // 原本寫著「最新那一則是『學生宿舍開放入住』、2026-08-26」。公告是
      // 每天都在換的東西 —— 2026-09-08 重抓一次 Portal.html，第一則變成
      // 「【食安宣導】中聯油品訟訴相關新聞」，測試就紅了，而 parser 一行
      // 都沒改。那種紅燈只會訓練人去改測試遷就 fixture。
      //
      // 換成驗「解出來的東西合不合理」：日期真的被解析成日期，而不是
      // 靜靜地變成 1970 或今天。
      final year = DateTime.now().year;
      for (final a in list) {
        expect(a.date!.year, greaterThanOrEqualTo(year - 3), reason: a.title);
        expect(a.date!.year, lessThanOrEqualTo(year + 1), reason: a.title);
      }
    }, skip: missing);
  });

  group('全文頁路徑', () {
    test('用編號拼出 BBS3010_02 的路徑', () {
      const a = Announcement(title: 'x', id: '9005901');
      expect(
        a.detailPath,
        'Application/BBS/BBS30/BBS3010_02.aspx'
        '?pkno=9005901&progcd=BBS3010&TYPE=PORTAL',
      );
    });

    test('沒有編號就是不能點開（null，不是空字串）', () {
      // 空字串會被當成一個「有路徑」的東西送去 GET，拿回一頁錯的內容。
      const a = Announcement(title: 'x');
      expect(a.detailPath, isNull);
    });
  });
}

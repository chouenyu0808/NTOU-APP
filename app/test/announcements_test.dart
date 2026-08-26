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

      // 真實資料裡最新那一則
      expect(list.first.title, contains('學生宿舍開放入住'));
      expect(list.first.unit, '學務處住宿輔導組');
      expect(list.first.date, DateTime(2026, 8, 26));
    }, skip: missing);
  });
}

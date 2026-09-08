import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/announcement_detail.dart';

import 'fixtures.dart';

/// 公告全文（BBS3010_02）。
void main() {
  group('合成頁面', () {
    // 這一頁的版面是 bootstrap row/col：標籤欄 + 值欄。
    String field(String label, String valueHtml) => '''
      <div class="row">
        <div class="col-xl-1 col-form-label"><span ml="PL_$label">$label</span></div>
        <div class="col-xl-11 col-lg-10">$valueHtml</div>
      </div>
    ''';

    String page({
      String subject = '主旨一行',
      String bodyHtml = '內文',
      String unit = '學務處衛生保健組　學校公告',
      String attachment = '無',
    }) => '''
      <html><body>
        <span id="unit_type_title">$unit</span>
        ${field('主旨', '<span id="M_BBS_SUBJ">$subject</span>')}
        ${field('內容', '<span id="L_BBS_CONTENT">$bodyHtml</span>')}
        ${field('附件', attachment)}
        ${field('承辦人', '林妙蓉')}
        ${field('登載期間', '115/09/08~115/10/30')}
      </body></html>
    ''';

    test('主旨、單位、承辦人、登載期間都讀得出來', () {
      final d = parseAnnouncementDetail(page());
      expect(d.subject, '主旨一行');
      // 單位取全形空白前那一段，「學校公告」是分類不是單位。
      expect(d.unit, '學務處衛生保健組');
      expect(d.handler, '林妙蓉');
      expect(d.postingPeriod, '115/09/08~115/10/30');
    });

    test('**內文保留 <br> 換行；單 br 換行、雙 br 空一行**', () {
      // 學校用 <br> 排段落，全部壓成一行會變成一坨。單 <br> 是段落內換行，
      // <br><br> 是段落之間 —— 那個區別保留下來，讀起來才有層次。
      final d = parseAnnouncementDetail(
        page(bodyHtml: '第一段<br>第二段<br><br>第三段'),
      );
      expect(d.body, '第一段\n第二段\n\n第三段');
    });

    test('連續好幾個 <br> 收成最多一個空行', () {
      // 學校常常連打四五個 <br>，照搬會在畫面上留一大片空白。
      final d = parseAnnouncementDetail(
        page(bodyHtml: 'A<br><br><br><br>B'),
      );
      expect(d.body, 'A\n\nB');
    });

    test('沒有附件時照實顯示「無」，不是空白', () {
      expect(parseAnnouncementDetail(page(attachment: '無')).attachment, '無');
    });

    test('缺欄位不會爆掉，只是那一格空的', () {
      final d = parseAnnouncementDetail('<html><body>什麼都沒有</body></html>');
      expect(d.subject, '');
      expect(d.body, '');
      expect(d.hasBody, isFalse);
    });
  });

  group('真實頁面', () {
    const f = 'Application_BBS_BBS30_BBS3010_02.html';

    test('食安宣導那則：主旨、單位、內文、登載期間', () {
      final d = parseAnnouncementDetail(fixture(f));
      expect(d.subject, contains('食安宣導'));
      expect(d.unit, '學務處衛生保健組');
      expect(d.postingPeriod, '115/09/08~115/10/30');
      expect(d.handler, '林妙蓉');

      // 內文有真的段落（<br> 換行），而且不是一整坨。
      expect(d.hasBody, isTrue);
      expect(d.body, contains('中聯油品'));
      expect(d.body, contains('\n'), reason: '<br> 要換成換行');
    }, skip: skipUnless(f));
  });
}

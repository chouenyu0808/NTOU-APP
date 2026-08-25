import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/ais_session.dart';
import 'package:ntou_app/src/ais/decode.dart';
import 'package:ntou_app/src/ais/js_redirect.dart';
import 'package:ntou_app/src/ais/page.dart';
import 'package:ntou_app/src/parsing/tables.dart';
import 'package:ntou_app/src/parsing/timetable.dart';

import 'fixtures.dart';

/// 對著**真實抓下來的頁面**測。
///
/// fixture 沒進版控（含個資，見 .gitignore），所以檔案不在時整組 skip ——
/// 跟 spike 的 pytest 一樣的做法。有 fixture 的人跑得到，沒有的人也不會紅。
void main() {
  group('真實頁面', () {
    setUpAll(() {
      if (!fixturesAvailable) {
        // ignore: avoid_print
        print('找不到 ${fixturesDir.path}，跳過真實頁面測試。'
            '要跑的話先用 spike/login.py --save 抓一次。');
      }
    });

    test('登入成功的回應：靠導向判斷，不能靠找字串', () {
      final html = fixture('login_post.html');
      // 這是整個登入流程最容易踩的雷：成功的回應**還是帶著登入表單**，
      // 跟登入頁只差一行導向指令。用「找『登出』」判斷會把成功當成失敗。
      expect(html.contains('M_PORTAL_LOGIN_ACNT'), isTrue,
          reason: '成功的回應裡仍然有登入表單 —— 所以不能用表單存在與否判斷');
      expect(jsRedirectTarget(html), 'MainFrame.aspx');
    }, skip: skipReason);

    test('登入失敗的回應沒有前進的導向', () {
      final html = fixture('login_failed.html');
      final target = jsRedirectTarget(html);
      expect(target, anyOf(isNull, isNot('MainFrame.aspx')));
    }, skip: skipReason);

    test('重複登入被擋：先認 session 衝突，再認登入頁', () {
      // 這一頁**同時**帶著登入表單和衝突訊息。判斷順序反過來的話，
      // 使用者會看到「登入逾時，請重新登入」，然後重登、再被擋，無限循環。
      final page = pageOf('session_blocked.html');
      expect(AisSession.isSessionConflict(page), isTrue);
      expect(page.html.contains('M_PORTAL_LOGIN_ACNT'), isTrue,
          reason: '它也長得像登入頁 —— 所以 checkSession 的順序很重要');
    }, skip: skipReason);

    test('排隊頁會導回登入頁', () {
      expect(jsRedirectTarget(fixture('queue.html')), 'Default.aspx');
    }, skip: skipReason);

    group('MainFrame 的 frame 握手', () {
      test('挑出四個要載的 frame', () {
        final page = pageOf('mainframe.html',
            url: 'https://ais.ntou.edu.tw/MainFrame.aspx');
        final sources = AisSession.frameSources(
          page,
          Uri.parse('https://ais.ntou.edu.tw/'),
        );
        final paths = sources.map((u) => u.path).toList();

        expect(paths, contains('/MenuTree.aspx'));
        expect(paths, contains('/portal.aspx'));
        expect(paths, contains('/timeout.aspx'));
        expect(paths, contains('/title.aspx'));
        // viewIFrame / actionIFrame 沒有 src，timerIFrame 是 about:blank
        expect(sources.length, 4);
      });

      test('title.aspx 網址裡的空格不會炸掉', () {
        // 實際的 src 是 `title.aspx?XX= 1908128636` —— 校方多打了一個空格。
        // 這種東西不處理的話，登入握手會在最後一哩路丟例外。
        final html = fixture('mainframe.html');
        expect(html.contains('XX= '), isTrue, reason: '確認這個空格真的存在');

        final page = pageOf('mainframe.html',
            url: 'https://ais.ntou.edu.tw/MainFrame.aspx');
        expect(
          () => AisSession.frameSources(page, Uri.parse('https://ais.ntou.edu.tw/')),
          returnsNormally,
        );
      });
    }, skip: skipReason);

    test('個人課表查詢：六個學期都是「查無符合資料」', () {
      // 2026-08-25 實測，這個帳號還沒在本校選課。
      // 這個測試是在鎖「空結果認得出來」，不是在鎖「一定沒資料」——
      // 之後有課了，這裡會變成 red，那正是該回來調 parser 的時候。
      for (final f in [
        'Application_TKE_TKE22_TKE2240_01__QUERY_BTN1_115_1.html',
        'Application_TKE_TKE22_TKE2240_01__QUERY_BTN1_114_2.html',
      ]) {
        if (!has(f)) continue;
        expect(isEmptyResult(fixture(f)), isTrue, reason: f);
      }
    }, skip: skipReason);

    test('全校課程查詢：真實的 DataGrid 解得出課', () {
      // 個人課表沒資料，所以 parser 拿全校課程來對 —— 表格結構是同一套。
      final html = fixture('Application_TKE_TKE22_TKE2211_01__QUERY_BTN1_0_0507.html');
      expect(isEmptyResult(html), isFalse);

      final columns = courseListColumns(html);
      expect(columns, contains('課號'));
      expect(columns, contains('課名'));

      final courses = parseCourseList(html);
      expect(courses, isNotEmpty);
      expect(courses.first.code, isNotEmpty);
      expect(courses.first.name, isNotEmpty);
      expect(courses.first.credits, isNotNull);

      // 這一頁的結果**沒有上課時間欄**（2026-08-25 實測）。
      // 所以「解不出時段」在這裡是正確行為，不是 bug。
      expect(columns.any((c) => c.contains('時間')), isFalse);
      expect(courses.every((c) => c.slots.isEmpty), isTrue);
    }, skip: skipReason);
  });

  group('編碼假設', () {
    test('每一份 fixture 都宣告 UTF-8', () {
      // decodeHtml 只支援 UTF-8（見它的註解）。這個測試就是那個假設的守門員：
      // 哪天學校改成 Big5，這裡會先紅，而不是使用者先看到一頁亂碼。
      final files = fixtureFiles();
      expect(files, isNotEmpty);
      for (final f in files) {
        final charset = sniffCharset(f.readAsBytesSync())?.toLowerCase();
        expect(charset, anyOf(isNull, 'utf-8'), reason: f.path);
      }
    }, skip: skipReason);
  });
}

AisPage pageOf(String name, {String url = 'https://ais.ntou.edu.tw/x.aspx'}) =>
    AisPage(url: url, status: 200, html: fixture(name));

bool has(String name) => File('${fixturesDir.path}/$name').existsSync();

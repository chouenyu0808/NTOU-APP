import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/config/selectors.dart';

void main() {
  group('SelectorConfig.fromJson', () {
    test('秒數轉成 Duration', () {
      final c = SelectorConfig.fromJson({
        'min_interval_seconds': 1.5,
        'timeout_seconds': 20,
      });
      expect(c.minInterval, const Duration(milliseconds: 1500));
      expect(c.timeout, const Duration(seconds: 20));
    });

    test('缺欄位時給預設值', () {
      final c = SelectorConfig.fromJson(const {});
      expect(c.version, 0);
      expect(c.baseUrl, 'https://ais.ntou.edu.tw/');
      expect(c.minInterval, const Duration(seconds: 1));
      expect(c.timeout, const Duration(seconds: 20));
      expect(c.logoutPath, 'LogOut.aspx');
    });

    test('login 區塊解析，且原樣保留校方的拼字', () {
      final c = SelectorConfig.fromJson({
        'login': {
          'submit_field': 'LGOIN_BTN', // 校方把 LOGIN 拼錯，照抄不要修
          'submit_value': '登入/Login',
          'username_field': 'M_PORTAL_LOGIN_ACNT',
          'failure_markers': ['密碼錯誤', '驗證碼錯誤'],
          'extra_fields': {'foo': 'bar'},
        },
      });
      expect(c.login.submitField, 'LGOIN_BTN');
      expect(c.login.submitValue, '登入/Login');
      expect(c.login.usernameField, 'M_PORTAL_LOGIN_ACNT');
      expect(c.login.failureMarkers, ['密碼錯誤', '驗證碼錯誤']);
      expect(c.login.extraFields, {'foo': 'bar'});
    });

    test('failure_markers 裡的非字串會被濾掉', () {
      final c = SelectorConfig.fromJson({
        'login': {
          'failure_markers': ['密碼錯誤', 123, null, '驗證碼錯誤'],
        },
      });
      expect(c.login.failureMarkers, ['密碼錯誤', '驗證碼錯誤']);
    });

    test('timetable 區塊從 pages.timetable.query 解析', () {
      final c = SelectorConfig.fromJson({
        'pages': {
          'timetable': {
            'path': 'Application/TKE/TKE22/TKE2240_.aspx?progcd=STU1220',
            'query': {
              'year_field': 'Q_AYEAR',
              'semester_field': 'Q_SMS',
              'list_button': 'QUERY_BTN1',
              'timetable_button': 'QUERY_BTN3',
            },
          },
        },
      });
      expect(c.timetable.yearField, 'Q_AYEAR');
      expect(c.timetable.semesterField, 'Q_SMS');
      expect(c.timetable.listButton, 'QUERY_BTN1');
      expect(c.timetable.timetableButton, 'QUERY_BTN3');
    });
  });

  group('隨 App 打包的 assets/selectors.json', () {
    // flutter test 的工作目錄是套件根目錄（app/），跟 fixtures.dart 讀 ../spike 一致。
    final file = File('assets/selectors.json');

    test('是合法 JSON 且能解出設定', () {
      final c = SelectorConfig.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      // 鎖住幾個「改了登入就會壞」的值。
      expect(c.login.submitField, 'LGOIN_BTN', reason: '校方的拼字，不要順手修正');
      expect(c.login.usernameField, isNotEmpty);
      expect(c.login.passwordField, isNotEmpty);
      expect(c.login.captchaField, isNotEmpty);
      expect(c.baseUrl, startsWith('https://'));
    });
  });

  group('app 和 spike 的設定沒有各走各的', () {
    // `selectors.json` 和 `menu_tree.json` 各有兩份：App 打包一份、
    // spike 探索用一份。**兩份是手動同步的，而且沒有任何東西在看著。**
    //
    // 2026-09-08 就是這樣出事的：學校上架了整個成績系統，選單從 50 個長到
    // 131 個，但兩份 selectors.json 裡都還寫著「成績查詢不在這個系統的學生
    // 選單裡，50 個功能全部檢查過」。改的時候先改了 app 那份，spike 那份
    // 留在原地 —— 下一個人翻到 spike 那份會直接放棄找成績。
    //
    // 註解不比對：兩份的用途不同（一份給 Dart、一份給 Python 探索），
    // `course_search` 本來就各自記著不同的東西。比的是**路徑** ——
    // 那是「同一個學校系統」的事實，兩邊不該有兩種答案。
    final appJson = jsonDecode(File('assets/selectors.json').readAsStringSync())
        as Map<String, dynamic>;
    final spikeJson =
        jsonDecode(File('../spike/selectors.json').readAsStringSync())
            as Map<String, dynamic>;

    test('每個 page 的 path 一致', () {
      final appPages = (appJson['pages'] as Map).cast<String, dynamic>();
      final spikePages = (spikeJson['pages'] as Map).cast<String, dynamic>();

      expect(appPages.keys.toSet(), spikePages.keys.toSet(),
          reason: '有一邊多了或少了功能');

      for (final key in appPages.keys) {
        if (key.startsWith('_')) continue;
        final a = (appPages[key] as Map)['path'];
        final b = (spikePages[key] as Map)['path'];
        expect(a, b, reason: '$key 的路徑兩邊不一樣');
      }
    });

    test('base_url 一致', () {
      expect(appJson['base_url'], spikeJson['base_url']);
    });

    test('menu_tree.json 兩份完全相同', () {
      // 這一份沒有「用途不同」的空間 —— 它就是學校選單的抄本，
      // 兩邊必須是同一份。App 的選單是從它打包進去的，spike 的
      // `--fetch-all` 也讀它來決定要抓哪些頁。
      final a = File('assets/menu_tree.json').readAsStringSync();
      final b = File('../spike/fixtures/menu_tree.json').readAsStringSync();
      expect(
        jsonDecode(a),
        jsonDecode(b),
        reason: '重抓選單之後要兩邊都更新（spike 那份是 --menu 直接寫出來的）',
      );
    });
  });
}

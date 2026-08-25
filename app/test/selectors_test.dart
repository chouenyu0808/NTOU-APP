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
}

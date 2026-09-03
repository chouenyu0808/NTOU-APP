import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/course_detail_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<CourseDetailCache> cache() async =>
      CourseDetailCache(prefs: await SharedPreferences.getInstance());

  group('CourseDetailCache', () {
    test('時間和地點一起 round-trip', () async {
      final c = await cache();
      await c.write('115', '1', {
        'B57011RQ 1年A班': const CourseDetail(
          code: 'B57011RQ',
          slots: [TimeSlot(0, 2), TimeSlot(0, 3)],
          room: 'INS105',
        ),
      });

      final back = await c.read('115', '1');
      expect(back, hasLength(1));
      expect(back['B57011RQ 1年A班']!.room, 'INS105');
      expect(back['B57011RQ 1年A班']!.slots,
          const [TimeSlot(0, 2), TimeSlot(0, 3)]);
    });

    test('換學期就是另一張表', () async {
      final c = await cache();
      await c.write('115', '1', {'X': const CourseDetail(code: 'X')});

      expect(await c.read('115', '2'), isEmpty);
    });

    test('merge 只加新的那幾門，不會蓋掉表上其他課', () async {
      // 頁面上記憶體裡那份是開頁時非同步讀回來的，讀完之前就有探測回來時
      // 用它去蓋整張表，等於把表清掉 —— 而症狀要到下一次開 App 才看得到。
      final c = await cache();
      await c.write('115', '1', {'甲': const CourseDetail(code: '甲')});

      await c.merge('115', '1', {'乙': const CourseDetail(code: '乙')});

      final back = await c.read('115', '1');
      expect(back.keys, containsAll(['甲', '乙']));
    });

    test('壞掉的表當作沒有，不要讓加課清單開不起來', () async {
      SharedPreferences.setMockInitialValues({
        'course_details.115.1': '這不是 JSON',
      });
      expect(await (await cache()).read('115', '1'), isEmpty);
    });
  });

  group('從舊的「只有時間」那張表搬過來', () {
    /// 舊格式：`{key: [slot, ...]}`，抓失敗和「學校沒排時間」都存成空陣列。
    void seedLegacy(Map<String, List<TimeSlot>> times) {
      SharedPreferences.setMockInitialValues({
        'course_times.115.1': jsonEncode({
          for (final e in times.entries)
            e.key: [for (final s in e.value) s.toJson()],
        }),
      });
    }

    test('查到過的時間留著，不用重問一次', () async {
      seedLegacy({
        'B57011RQ 1年A班': const [TimeSlot(0, 2), TimeSlot(0, 3)],
      });

      final back = await (await cache()).read('115', '1');
      expect(back['B57011RQ 1年A班']!.slots,
          const [TimeSlot(0, 2), TimeSlot(0, 3)]);
    });

    test('空陣列一律不搬 —— 那裡面混著抓失敗的', () async {
      // 舊版把「抓失敗」和「學校沒排時間」都存成空陣列，分不出來。
      // 搬過來的話那些課會繼續卡在查不到，而且重開 App 也好不了。
      seedLegacy({
        'B57011RQ 1年A班': const [TimeSlot(0, 2)],
        'B57012RQ 1年A班': const [],
      });

      final back = await (await cache()).read('115', '1');
      expect(back.keys, ['B57011RQ 1年A班']);
    });

    test('搬完就把舊表清掉，不要每次開頁都搬一遍', () async {
      seedLegacy({'B57011RQ 1年A班': const [TimeSlot(0, 2)]});
      final prefs = await SharedPreferences.getInstance();

      await CourseDetailCache(prefs: prefs).read('115', '1');

      expect(prefs.getString('course_times.115.1'), isNull);
      expect(prefs.getString('course_details.115.1'), isNotNull);
    });
  });
}

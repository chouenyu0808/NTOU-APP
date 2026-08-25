import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/storage/timetable_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TimetableCache', () {
    test('write 與 read 正常 round-trip', () async {
      final cache = TimetableCache(prefs: await SharedPreferences.getInstance());

      final sample = TimetableResult(
        year: '115',
        semester: '1',
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25, 12, 0),
        columns: const ['課號', '課名'],
        courses: [
          const Course(
            name: '演算法',
            code: 'CS201',
            teacher: '李教授',
            room: '電資201',
            credits: 3.0,
            slots: [TimeSlot(1, 3), TimeSlot(1, 4)],
            raw: {'課號': 'CS201', '課名': '演算法'},
          ),
        ],
      );

      await cache.write(sample);
      final readBack = await cache.read('115', '1');

      expect(readBack, isNotNull);
      expect(readBack!.year, '115');
      expect(readBack.semester, '1');
      expect(readBack.isEmpty, isFalse);
      expect(readBack.courses.length, 1);
      expect(readBack.courses.first.name, '演算法');
      expect(readBack.courses.first.code, 'CS201');
      expect(readBack.courses.first.slots, [const TimeSlot(1, 3), const TimeSlot(1, 4)]);
      expect(readBack.columns, ['課號', '課名']);
    });

    test('未寫入之學年學期 read 回傳 null', () async {
      final cache = TimetableCache(prefs: await SharedPreferences.getInstance());
      final result = await cache.read('114', '2');
      expect(result, isNull);
    });

    test('遇到損毀的 JSON 快取回傳 null 而不拋出例外', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('timetable.115.1', '{bad json content...');

      final cache = TimetableCache(prefs: prefs);
      final result = await cache.read('115', '1');
      expect(result, isNull);
    });

    test('write 自動更新 lastViewed，且 lastViewed 正確讀取', () async {
      final cache = TimetableCache(prefs: await SharedPreferences.getInstance());
      expect(await cache.lastViewed(), isNull);

      final sample = TimetableResult(
        year: '115',
        semester: '2',
        isEmpty: true,
        fetchedAt: DateTime(2026, 8, 25),
        courses: const [],
      );

      await cache.write(sample);
      final last = await cache.lastViewed();

      expect(last, isNotNull);
      expect(last!.year, '115');
      expect(last.semester, '2');
    });

    test('lastViewed 資料長度異常時回傳 null', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('timetable.last_viewed', ['115']); // 只給 1 個元素

      final cache = TimetableCache(prefs: prefs);
      expect(await cache.lastViewed(), isNull);
    });

    test('clear() 精準刪除所有 timetable. 前綴的 key，不影響其他 key', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('timetable.115.1', 'data1');
      await prefs.setString('timetable.115.2', 'data2');
      await prefs.setStringList('timetable.last_viewed', ['115', '1']);
      await prefs.setString('user.preference.theme', 'dark');

      final cache = TimetableCache(prefs: prefs);
      await cache.clear();

      expect(await cache.read('115', '1'), isNull);
      expect(await cache.read('115', '2'), isNull);
      expect(await cache.lastViewed(), isNull);

      // 其他 key 仍保留
      expect(prefs.getString('user.preference.theme'), 'dark');
    });
  });
}

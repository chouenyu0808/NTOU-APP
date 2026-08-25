import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';

void main() {
  group('TimeSlot', () {
    test('compareTo 先比 weekday 再比 period', () {
      const mon1 = TimeSlot(0, 1);
      const mon2 = TimeSlot(0, 2);
      const tue1 = TimeSlot(1, 1);

      expect(mon1.compareTo(mon2), lessThan(0));
      expect(mon2.compareTo(mon1), greaterThan(0));
      expect(mon1.compareTo(tue1), lessThan(0));
      expect(tue1.compareTo(mon2), greaterThan(0));
      expect(mon1.compareTo(const TimeSlot(0, 1)), 0);
    });

    test('相等性與 hashCode', () {
      const s1 = TimeSlot(2, 3);
      const s2 = TimeSlot(2, 3);
      const s3 = TimeSlot(2, 4);

      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, isNot(equals(s3)));
    });

    test('toString 格式化為中文字串', () {
      expect(const TimeSlot(0, 1).toString(), '(一1)');
      expect(const TimeSlot(2, 5).toString(), '(三5)');
      expect(const TimeSlot(6, 0).toString(), '(日0)');
    });

    test('JSON 序列化與反序列化', () {
      const slot = TimeSlot(4, 8);
      final json = slot.toJson();
      expect(json, {'weekday': 4, 'period': 8});
      expect(TimeSlot.fromJson(json), slot);
    });
  });

  group('Course', () {
    test('copyWith 支援更新 slots', () {
      const original = Course(
        name: '資料結構',
        code: 'CS102',
        teacher: '張老師',
      );

      final updated = original.copyWith(slots: [const TimeSlot(1, 3)]);
      expect(updated.name, '資料結構');
      expect(updated.code, 'CS102');
      expect(updated.teacher, '張老師');
      expect(updated.slots, [const TimeSlot(1, 3)]);
    });

    test('JSON round-trip 正確保留全部具名與 raw 欄位', () {
      const course = Course(
        name: '演算法',
        code: 'CS201',
        teacher: '李教授',
        room: '電資201',
        credits: 3.0,
        classLabel: '資工二A',
        selectionType: '必修',
        slots: [TimeSlot(0, 3), TimeSlot(0, 4)],
        raw: {'課號': 'CS201', '課名': '演算法', '備註': '無'},
      );

      final json = course.toJson();
      final restored = Course.fromJson(json);

      expect(restored.name, course.name);
      expect(restored.code, course.code);
      expect(restored.teacher, course.teacher);
      expect(restored.room, course.room);
      expect(restored.credits, course.credits);
      expect(restored.classLabel, course.classLabel);
      expect(restored.selectionType, course.selectionType);
      expect(restored.slots, course.slots);
      expect(restored.raw, course.raw);
    });
  });

  group('TimetableResult', () {
    test('label 格式正確', () {
      final res = TimetableResult(
        year: '115',
        semester: '1',
        courses: const [],
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25),
      );
      expect(res.label, '115 學年度第 1 學期');
    });

    test('hasSlots 正確反映是否有任何課程含有時段', () {
      final withoutSlots = TimetableResult(
        year: '115',
        semester: '1',
        courses: const [Course(name: '課A', slots: [])],
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25),
      );
      expect(withoutSlots.hasSlots, isFalse);

      final withSlots = TimetableResult(
        year: '115',
        semester: '1',
        courses: const [
          Course(name: '課A', slots: []),
          Course(name: '課B', slots: [TimeSlot(0, 1)]),
        ],
        isEmpty: false,
        fetchedAt: DateTime(2026, 8, 25),
      );
      expect(withSlots.hasSlots, isTrue);
    });

    test('JSON round-trip 正確保留全部資料', () {
      final time = DateTime(2026, 8, 25, 15, 30);
      final sample = TimetableResult(
        year: '115',
        semester: '2',
        isEmpty: false,
        fetchedAt: time,
        columns: const ['課號', '課名', '學分'],
        courses: [
          const Course(
            name: '計算機圖學',
            code: 'CS501',
            credits: 3.0,
            slots: [TimeSlot(3, 1), TimeSlot(3, 2)],
          ),
        ],
      );

      final json = sample.toJson();
      final restored = TimetableResult.fromJson(json);

      expect(restored.year, '115');
      expect(restored.semester, '2');
      expect(restored.isEmpty, isFalse);
      expect(restored.fetchedAt, time);
      expect(restored.columns, ['課號', '課名', '學分']);
      expect(restored.courses.length, 1);
      expect(restored.courses.first.name, '計算機圖學');
      expect(restored.courses.first.slots, [const TimeSlot(3, 1), const TimeSlot(3, 2)]);
    });
  });
}

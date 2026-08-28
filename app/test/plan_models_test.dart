import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/planner/plan_models.dart';

void main() {
  group('PlannedCourse', () {
    test('key 優先使用 code，若 code 為空則使用 name', () {
      const c1 = PlannedCourse(
        course: Course(name: '演算法', code: 'CS201'),
      );
      expect(c1.key, 'CS201');

      const c2 = PlannedCourse(
        course: Course(name: '微積分', code: ''),
      );
      expect(c2.key, '微積分');
    });

    test('同課號不同班別是兩筆不同的課', () {
      // 真實資料：B57011RQ 計算機概論同時有 1年A班和 1年B班，
      // 課號和課名一模一樣，上課時間不一樣。
      const a = PlannedCourse(
        course: Course(name: '計算機概論', code: 'B57011RQ', classLabel: '1年A班'),
      );
      const b = PlannedCourse(
        course: Course(name: '計算機概論', code: 'B57011RQ', classLabel: '1年B班'),
      );
      expect(a.key, isNot(b.key));
    });

    test('copyWith 正確複製並更新欄位', () {
      const original = PlannedCourse(
        course: Course(name: '計算機組織', code: 'CS301'),
        slots: [TimeSlot(0, 3)],
        note: '舊備註',
        slotsAreManual: false,
      );

      final updated = original.copyWith(
        slots: [TimeSlot(0, 3), TimeSlot(0, 4)],
        note: '新備註',
        slotsAreManual: true,
      );

      expect(updated.course.name, '計算機組織');
      expect(updated.slots, [const TimeSlot(0, 3), const TimeSlot(0, 4)]);
      expect(updated.note, '新備註');
      expect(updated.slotsAreManual, isTrue);

      // 未傳入參數時保留原值
      final unmodified = original.copyWith();
      expect(unmodified.slots, original.slots);
      expect(unmodified.note, original.note);
      expect(unmodified.slotsAreManual, original.slotsAreManual);
    });

    test('JSON 序列化與反序列化 round-trip', () {
      const course = PlannedCourse(
        course: Course(
          name: '作業系統',
          code: 'CS401',
          teacher: '陳教授',
          room: '電資101',
          credits: 3.0,
        ),
        slots: [TimeSlot(1, 1), TimeSlot(1, 2)],
        note: '重要必修',
        slotsAreManual: true,
      );

      final json = course.toJson();
      final restored = PlannedCourse.fromJson(json);

      expect(restored.course.name, course.course.name);
      expect(restored.course.code, course.course.code);
      expect(restored.course.teacher, course.course.teacher);
      expect(restored.course.room, course.course.room);
      expect(restored.course.credits, course.course.credits);
      expect(restored.slots, course.slots);
      expect(restored.note, course.note);
      expect(restored.slotsAreManual, course.slotsAreManual);
      expect(restored.key, course.key);
    });
  });

  group('Conflict', () {
    test('describe() 產生友善的衝突字串', () {
      const a = PlannedCourse(
        course: Course(name: '資料庫系統'),
        slots: [TimeSlot(2, 3), TimeSlot(2, 4)],
      );
      const b = PlannedCourse(
        course: Course(name: '計算機網路'),
        slots: [TimeSlot(2, 3)],
      );

      final conflict = Conflict(a, b, const [TimeSlot(2, 3)]);
      expect(conflict.describe(), '資料庫系統 和 計算機網路 都在 (三3)');
    });

    test('describe() 多個衝突時段以頓號連接', () {
      const a = PlannedCourse(
        course: Course(name: '軟體工程'),
        slots: [TimeSlot(0, 1), TimeSlot(0, 2)],
      );
      const b = PlannedCourse(
        course: Course(name: '編譯器設計'),
        slots: [TimeSlot(0, 1), TimeSlot(0, 2)],
      );

      final conflict = Conflict(a, b, const [TimeSlot(0, 1), TimeSlot(0, 2)]);
      expect(conflict.describe(), '軟體工程 和 編譯器設計 都在 (一1)、(一2)');
    });
  });

  group('CoursePlan', () {
    test('label 格式正確', () {
      const plan = CoursePlan(year: '115', semester: '1');
      expect(plan.label, '115 學年度第 1 學期');
      expect(plan.isEmpty, isTrue);
    });

    test('add 新增課程，重複 key 不會重複加入', () {
      const c1 = PlannedCourse(course: Course(name: '課程A', code: 'A01'));
      const c2 = PlannedCourse(course: Course(name: '課程B', code: 'B01'));
      const c1Duplicate = PlannedCourse(
        course: Course(name: '課程A修改版', code: 'A01'),
        note: '不同備註',
      );

      var plan = const CoursePlan(year: '115', semester: '1');
      plan = plan.add(c1);
      expect(plan.courses.length, 1);
      expect(plan.contains('A01'), isTrue);

      plan = plan.add(c2);
      expect(plan.courses.length, 2);
      expect(plan.contains('B01'), isTrue);

      // 重複 key 不變動
      plan = plan.add(c1Duplicate);
      expect(plan.courses.length, 2);
      expect(plan.courses.first.note, '');
    });

    test('remove 依 key 移除課程', () {
      const c1 = PlannedCourse(course: Course(name: '課程A', code: 'A01'));
      const c2 = PlannedCourse(course: Course(name: '課程B', code: 'B01'));

      var plan = const CoursePlan(year: '115', semester: '1', courses: [c1, c2]);
      expect(plan.contains('A01'), isTrue);

      plan = plan.remove('A01');
      expect(plan.courses.length, 1);
      expect(plan.contains('A01'), isFalse);
      expect(plan.contains('B01'), isTrue);

      // 移除不存在的 key 無副作用
      plan = plan.remove('NONEXIST');
      expect(plan.courses.length, 1);
    });

    test('update 更新指定 key 的課程', () {
      const c1 = PlannedCourse(
        course: Course(name: '課程A', code: 'A01'),
        note: '舊備註',
      );
      const c2 = PlannedCourse(course: Course(name: '課程B', code: 'B01'));

      var plan = const CoursePlan(year: '115', semester: '1', courses: [c1, c2]);

      const c1Updated = PlannedCourse(
        course: Course(name: '課程A', code: 'A01'),
        note: '新備註',
        slots: [TimeSlot(0, 1)],
      );

      plan = plan.update(c1Updated);
      expect(plan.courses.length, 2);
      expect(plan.courses.first.note, '新備註');
      expect(plan.courses.first.slots.length, 1);
    });

    test('totalCredits 正確累加有學分的課，學分為 null 視為 0', () {
      const c1 = PlannedCourse(course: Course(name: '課1', credits: 3.0));
      const c2 = PlannedCourse(course: Course(name: '課2', credits: 2.5));
      const c3 = PlannedCourse(course: Course(name: '課3', credits: null));

      const plan = CoursePlan(
        year: '115',
        semester: '1',
        courses: [c1, c2, c3],
      );

      expect(plan.totalCredits, 5.5);
    });

    test('missingSlotCount 正確計算未填時段的課程數量', () {
      const c1 = PlannedCourse(
        course: Course(name: '有時段'),
        slots: [TimeSlot(0, 1)],
      );
      const c2 = PlannedCourse(
        course: Course(name: '無時段1'),
        slots: [],
      );
      const c3 = PlannedCourse(
        course: Course(name: '無時段2'),
        slots: [],
      );

      const plan = CoursePlan(
        year: '115',
        semester: '1',
        courses: [c1, c2, c3],
      );

      expect(plan.missingSlotCount, 2);
    });

    test('conflicts() 準確偵測衝堂課程與時段，無時段者不參與比對', () {
      const c1 = PlannedCourse(
        course: Course(name: '課A', code: 'A'),
        slots: [TimeSlot(0, 1), TimeSlot(0, 2), TimeSlot(1, 3)],
      );
      const c2 = PlannedCourse(
        course: Course(name: '課B', code: 'B'),
        slots: [TimeSlot(0, 2), TimeSlot(0, 3)],
      );
      const c3 = PlannedCourse(
        course: Course(name: '課C', code: 'C'),
        slots: [TimeSlot(1, 3)],
      );
      const c4NoSlots = PlannedCourse(
        course: Course(name: '課D無時段', code: 'D'),
        slots: [],
      );

      const plan = CoursePlan(
        year: '115',
        semester: '1',
        courses: [c1, c2, c3, c4NoSlots],
      );

      final conflicts = plan.conflicts();
      expect(conflicts.length, 2);

      // c1 與 c2 衝 (一2)
      final conflictAB = conflicts.firstWhere(
        (c) => c.a.key == 'A' && c.b.key == 'B',
      );
      expect(conflictAB.slots, [const TimeSlot(0, 2)]);

      // c1 與 c3 衝 (二3)
      final conflictAC = conflicts.firstWhere(
        (c) => c.a.key == 'A' && c.b.key == 'C',
      );
      expect(conflictAC.slots, [const TimeSlot(1, 3)]);
    });

    test('asCourses() 攤平為 Course 列表並注入 slots', () {
      const c1 = PlannedCourse(
        course: Course(name: '課A', code: 'A', teacher: '王老師'),
        slots: [TimeSlot(0, 1), TimeSlot(0, 2)],
      );

      const plan = CoursePlan(
        year: '115',
        semester: '1',
        courses: [c1],
      );

      final courses = plan.asCourses();
      expect(courses.length, 1);
      expect(courses.first.name, '課A');
      expect(courses.first.code, 'A');
      expect(courses.first.teacher, '王老師');
      expect(courses.first.slots, [const TimeSlot(0, 1), const TimeSlot(0, 2)]);
    });

    test('CoursePlan JSON 序列化與反序列化 round-trip', () {
      const plan = CoursePlan(
        year: '115',
        semester: '2',
        courses: [
          PlannedCourse(
            course: Course(
              name: '離散數學',
              code: 'MATH201',
              credits: 3.0,
            ),
            slots: [TimeSlot(3, 5), TimeSlot(3, 6)],
            note: '必修課',
            slotsAreManual: true,
          ),
        ],
      );

      final json = plan.toJson();
      final restored = CoursePlan.fromJson(json);

      expect(restored.year, '115');
      expect(restored.semester, '2');
      expect(restored.label, plan.label);
      expect(restored.courses.length, 1);
      expect(restored.courses.first.course.name, '離散數學');
      expect(restored.courses.first.course.code, 'MATH201');
      expect(restored.courses.first.slots, [const TimeSlot(3, 5), const TimeSlot(3, 6)]);
      expect(restored.courses.first.note, '必修課');
      expect(restored.courses.first.slotsAreManual, isTrue);
    });

    group('同課號的兩個班互不干擾', () {
      // 這一組驗的是一個會默默改掉資料的 bug：`key` 曾經只有課號，
      // 兩個班在同一份預排裡時，動其中一個會連另一個一起動 ——
      // 而畫面上看起來就只是「我明明只動了一門」。
      const a = PlannedCourse(
        course: Course(name: '計算機概論', code: 'B57011RQ', classLabel: '1年A班'),
        slots: [TimeSlot(0, 2)],
      );
      const b = PlannedCourse(
        course: Course(name: '計算機概論', code: 'B57011RQ', classLabel: '1年B班'),
        slots: [TimeSlot(2, 5)],
      );
      const plan = CoursePlan(year: '115', semester: '1', courses: [a, b]);

      test('兩個班都加得進去', () {
        expect(const CoursePlan(year: '115', semester: '1').add(a).add(b).courses,
            hasLength(2));
      });

      test('改 A 班的時段不會動到 B 班', () {
        final after =
            plan.update(a.copyWith(slots: const [TimeSlot(4, 7)], slotsAreManual: true));

        expect(after.courses, hasLength(2));
        expect(after.courses.first.slots, const [TimeSlot(4, 7)]);
        expect(after.courses.last.slots, const [TimeSlot(2, 5)],
            reason: 'B 班的時段不該被 A 班的編輯蓋掉');
      });

      test('刪掉 A 班之後 B 班還在', () {
        final after = plan.remove(a.key);

        expect(after.courses, hasLength(1));
        expect(after.courses.single.course.classLabel, '1年B班');
      });
    });
  });
}

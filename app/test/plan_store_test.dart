import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/planner/plan_models.dart';
import 'package:ntou_app/src/storage/plan_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PlanStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PlanStore(prefs: await SharedPreferences.getInstance());
  });

  CoursePlan plan(
    String year,
    String semester, {
    List<PlannedCourse> courses = const [],
  }) =>
      CoursePlan(year: year, semester: semester, courses: courses);

  group('PlanStore', () {
    test('沒存過時 read 回 null', () async {
      expect(await store.read('114', '1'), isNull);
    });

    test('write 後 read 得回同一份預排', () async {
      final p = plan('114', '1', courses: const [
        PlannedCourse(
          course: Course(name: '演算法', code: 'CS201'),
          slots: [TimeSlot(0, 3)],
          note: '一定要修',
        ),
      ]);
      await store.write(p);

      final back = await store.read('114', '1');
      expect(back, isNotNull);
      expect(back!.year, '114');
      expect(back.semester, '1');
      expect(back.courses.single.course.code, 'CS201');
      expect(back.courses.single.slots, const [TimeSlot(0, 3)]);
      expect(back.courses.single.note, '一定要修');
    });

    test('不同學期分開存，互不覆蓋', () async {
      // 預排跟課表快取分開就是為了這個：清一個不會誤傷另一個。
      await store.write(plan('114', '1'));
      await store.write(plan('114', '2'));
      expect(await store.read('114', '1'), isNotNull);
      expect(await store.read('114', '2'), isNotNull);
    });

    test('同學期重寫不會在索引裡留重複', () async {
      final prefs = await SharedPreferences.getInstance();
      await store.write(plan('114', '1'));
      await store.write(plan('114', '1'));
      expect(prefs.getStringList('plan._index'), ['114|1']);
    });

    test('delete 之後 read 回 null，索引也移掉', () async {
      final prefs = await SharedPreferences.getInstance();
      await store.write(plan('114', '1'));
      await store.write(plan('114', '2'));
      await store.delete('114', '1');

      expect(await store.read('114', '1'), isNull);
      expect(await store.read('114', '2'), isNotNull);
      expect(prefs.getStringList('plan._index'), ['114|2']);
    });

    test('壞掉的 JSON 當成沒有，不讓它整個炸開', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('plan.114.1', '{ 這不是 json');
      expect(await store.read('114', '1'), isNull);
    });
  });
}

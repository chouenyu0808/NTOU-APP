import '../parsing/models.dart';

/// 預排清單裡的一門課。
///
/// 跟 [Course] 分開的原因：同一門課在「查詢結果」和「我的預排」裡是不同的東西。
/// 前者是學校給的事實，後者是使用者的計畫 —— 計畫可以有學校沒有的資訊
/// （自己填的上課時間、備註），也可以被使用者改。混在一起的話，
/// 下次重新查詢就會把使用者填的東西蓋掉。
class PlannedCourse {
  const PlannedCourse({
    required this.course,
    this.slots = const [],
    this.note = '',
    this.slotsAreManual = false,
  });

  final Course course;

  /// 上課時段。
  ///
  /// **目前幾乎一定是使用者自己填的。** 學校的課程查詢結果（17 欄）
  /// 結構上就不含上課時間和教室，所以 [Course.slots] 在這條路徑上永遠是空的。
  /// 之後如果確認得了課表的來源，這裡才會有自動填入的值。
  final List<TimeSlot> slots;

  /// 使用者自己填的時段，重新查詢時不要蓋掉。
  final bool slotsAreManual;

  final String note;

  String get key => course.code.isNotEmpty ? course.code : course.name;

  PlannedCourse copyWith({
    List<TimeSlot>? slots,
    String? note,
    bool? slotsAreManual,
  }) =>
      PlannedCourse(
        course: course,
        slots: slots ?? this.slots,
        note: note ?? this.note,
        slotsAreManual: slotsAreManual ?? this.slotsAreManual,
      );

  Map<String, dynamic> toJson() => {
        'course': course.toJson(),
        'slots': [for (final s in slots) s.toJson()],
        'note': note,
        'slots_are_manual': slotsAreManual,
      };

  static PlannedCourse fromJson(Map<String, dynamic> j) => PlannedCourse(
        course: Course.fromJson((j['course'] as Map).cast<String, dynamic>()),
        slots: [
          for (final s in (j['slots'] as List? ?? const []))
            TimeSlot.fromJson((s as Map).cast<String, dynamic>()),
        ],
        note: j['note'] as String? ?? '',
        slotsAreManual: j['slots_are_manual'] as bool? ?? false,
      );
}

/// 兩門課撞在同一格。
class Conflict {
  const Conflict(this.a, this.b, this.slots);

  final PlannedCourse a;
  final PlannedCourse b;

  /// 撞到的那幾格。兩門課可能連撞好幾節。
  final List<TimeSlot> slots;

  String describe() {
    final where = slots.map((s) => s.toString()).join('、');
    return '${a.course.name} 和 ${b.course.name} 都在 $where';
  }
}

/// 某個學年學期的預排清單。
class CoursePlan {
  const CoursePlan({
    required this.year,
    required this.semester,
    this.courses = const [],
  });

  final String year;
  final String semester;
  final List<PlannedCourse> courses;

  String get label => '$year 學年度第 $semester 學期';

  bool get isEmpty => courses.isEmpty;

  /// 總學分。**只算得到有學分數的課** —— 學校沒給的就當 0，不要猜。
  double get totalCredits =>
      courses.fold(0, (sum, c) => sum + (c.course.credits ?? 0));

  /// 有幾門課還沒填上課時間。這些排不進格子，也驗不了衝堂。
  int get missingSlotCount => courses.where((c) => c.slots.isEmpty).length;

  bool contains(String key) => courses.any((c) => c.key == key);

  CoursePlan add(PlannedCourse c) =>
      contains(c.key) ? this : copyWith(courses: [...courses, c]);

  CoursePlan remove(String key) =>
      copyWith(courses: courses.where((c) => c.key != key).toList());

  CoursePlan update(PlannedCourse updated) => copyWith(
        courses: [
          for (final c in courses) c.key == updated.key ? updated : c,
        ],
      );

  CoursePlan copyWith({List<PlannedCourse>? courses}) => CoursePlan(
        year: year,
        semester: semester,
        courses: courses ?? this.courses,
      );

  /// 找出所有撞堂。
  ///
  /// 只比對**填了時段**的課 —— 沒填時段的課不代表不衝突，
  /// 只是我們不知道，所以不能報「沒有衝突」讓使用者安心。
  /// UI 要另外顯示 [missingSlotCount]。
  List<Conflict> conflicts() {
    final out = <Conflict>[];
    for (var i = 0; i < courses.length; i++) {
      for (var j = i + 1; j < courses.length; j++) {
        final a = courses[i];
        final b = courses[j];
        final shared = a.slots.where(b.slots.contains).toList()..sort();
        if (shared.isNotEmpty) out.add(Conflict(a, b, shared));
      }
    }
    return out;
  }

  /// 攤平成 [Course] 給課表格子畫。
  List<Course> asCourses() => [
        for (final p in courses) p.course.copyWith(slots: p.slots),
      ];

  Map<String, dynamic> toJson() => {
        'year': year,
        'semester': semester,
        'courses': [for (final c in courses) c.toJson()],
      };

  static CoursePlan fromJson(Map<String, dynamic> j) => CoursePlan(
        year: j['year'] as String? ?? '',
        semester: j['semester'] as String? ?? '',
        courses: [
          for (final c in (j['courses'] as List? ?? const []))
            PlannedCourse.fromJson((c as Map).cast<String, dynamic>()),
        ],
      );
}

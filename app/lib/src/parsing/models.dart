/// 課表上的一格：星期幾、第幾節。
///
/// [weekday] 0 = 週一。[period] 用學校自己的節次編號（`Q_CLASS` 的值是 00–16），
/// 不是「第幾個小時」—— 海大有第 0 節，硬轉成小時只會錯開一格。
class TimeSlot implements Comparable<TimeSlot> {
  const TimeSlot(this.weekday, this.period);

  final int weekday;
  final int period;

  @override
  int compareTo(TimeSlot other) => weekday != other.weekday
      ? weekday.compareTo(other.weekday)
      : period.compareTo(other.period);

  @override
  bool operator ==(Object other) =>
      other is TimeSlot && other.weekday == weekday && other.period == period;

  @override
  int get hashCode => Object.hash(weekday, period);

  Map<String, int> toJson() => {'weekday': weekday, 'period': period};

  static TimeSlot fromJson(Map<String, dynamic> j) =>
      TimeSlot((j['weekday'] as num).toInt(), (j['period'] as num).toInt());

  @override
  String toString() => '(${'一二三四五六日'[weekday.clamp(0, 6)]}$period)';
}

/// 一堂課。
///
/// [raw] 保留原始表格的整列（表頭 -> 值）。
///
/// 為什麼要留：個人選課清單的欄位還沒見過真實資料（這個帳號還沒選過課），
/// 所以我們不知道它到底有哪幾欄。認得的欄位放進具名欄位，
/// 認不得的留在 [raw] 裡讓 UI 照樣顯示 —— 這樣就算猜錯欄名，
/// 使用者看到的也是「多幾個沒對到的欄位」，不是「一片空白」。
class Course {
  const Course({
    required this.name,
    this.code = '',
    this.teacher = '',
    this.room = '',
    this.credits,
    this.classLabel = '',
    this.selectionType = '',
    this.slots = const [],
    this.raw = const {},
  });

  final String name;
  final String code;
  final String teacher;
  final String room;
  final double? credits;

  /// 年級班別，例如「1年A班」。
  final String classLabel;

  /// 選別（A = 必修 之類），學校自己的代碼。
  final String selectionType;

  /// 上課時段。抓不到時是空的 —— 課還是要顯示，只是排不進格子裡。
  final List<TimeSlot> slots;

  final Map<String, String> raw;

  Course copyWith({List<TimeSlot>? slots}) => Course(
        name: name,
        code: code,
        teacher: teacher,
        room: room,
        credits: credits,
        classLabel: classLabel,
        selectionType: selectionType,
        slots: slots ?? this.slots,
        raw: raw,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'code': code,
        'teacher': teacher,
        'room': room,
        'credits': credits,
        'class_label': classLabel,
        'selection_type': selectionType,
        'slots': [for (final s in slots) s.toJson()],
        'raw': raw,
      };

  static Course fromJson(Map<String, dynamic> j) => Course(
        name: j['name'] as String? ?? '',
        code: j['code'] as String? ?? '',
        teacher: j['teacher'] as String? ?? '',
        room: j['room'] as String? ?? '',
        credits: (j['credits'] as num?)?.toDouble(),
        classLabel: j['class_label'] as String? ?? '',
        selectionType: j['selection_type'] as String? ?? '',
        slots: [
          for (final s in (j['slots'] as List? ?? const []))
            TimeSlot.fromJson(s as Map<String, dynamic>),
        ],
        raw: (j['raw'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
      );
}

/// 一次查詢的結果。
///
/// [isEmpty] 和「courses 是空的」不一樣：前者是學校明確回了「查無符合資料」，
/// 後者可能是 parser 沒認出表格。UI 要分開講，不然使用者會以為 App 壞了
/// （或更糟：以為自己沒選到課）。
class TimetableResult {
  const TimetableResult({
    required this.year,
    required this.semester,
    required this.courses,
    required this.isEmpty,
    required this.fetchedAt,
    this.columns = const [],
  });

  final String year;
  final String semester;
  final List<Course> courses;
  final bool isEmpty;
  final DateTime fetchedAt;

  /// 原始表格的表頭順序，UI 照這個順序顯示 [Course.raw]。
  final List<String> columns;

  String get label => '$year 學年度第 $semester 學期';

  bool get hasSlots => courses.any((c) => c.slots.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'year': year,
        'semester': semester,
        'courses': [for (final c in courses) c.toJson()],
        'is_empty': isEmpty,
        'fetched_at': fetchedAt.toIso8601String(),
        'columns': columns,
      };

  static TimetableResult fromJson(Map<String, dynamic> j) => TimetableResult(
        year: j['year'] as String? ?? '',
        semester: j['semester'] as String? ?? '',
        courses: [
          for (final c in (j['courses'] as List? ?? const []))
            Course.fromJson(c as Map<String, dynamic>),
        ],
        isEmpty: j['is_empty'] as bool? ?? false,
        fetchedAt:
            DateTime.tryParse(j['fetched_at'] as String? ?? '') ?? DateTime(1970),
        columns: (j['columns'] as List?)?.whereType<String>().toList() ?? const [],
      );
}

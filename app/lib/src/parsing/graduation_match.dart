/// 把成績單上的課，對到畢業必修表上的要求。
///
/// **為什麼要自己對：** 學校的畢業資格頁（`ENRG010`）只認它自己登錄過的，
/// 而抵免不一定已經掛進去 —— 2026-09-17 實測，同一個帳號在成績頁有 19 筆
/// 抵免、歷年累計 40 學分，畢業資格那一頁卻是每一類「已得 0、還差全部」。
/// 使用者需要知道的是「我還有哪些必修沒修」，那個答案現在兩頁都沒有。
library;

import 'grades.dart';
import 'graduation.dart';
import 'html_text.dart';

/// 一項必修要求，配上成績裡對應到的那門課。
class RequirementMatch {
  const RequirementMatch({required this.requirement, this.course});

  final RequiredCourse requirement;

  /// 成績裡同名的那門課，對不到就是 null。
  final CourseGrade? course;

  /// **學校自己登錄的修課紀錄。** 這是權威來源，比我們比對出來的可靠。
  bool get bySchool => requirement.taken;

  /// 我們從成績比對到的（學校還沒登錄）。
  bool get byMatch => !bySchool && course != null;

  /// 這一項可以算完成了。
  bool get done => bySchool || (course?.mark.isPassed ?? false);

  /// 正在修，還沒有成績。
  bool get inProgress => !done && (course?.mark.isPending ?? false);
}

/// 整張必修表的比對結果。
class GraduationMatch {
  const GraduationMatch({
    required this.byRequirement,
    required this.unmatched,
  });

  /// 每一項要求對到的課。鍵是 `GraduationStatus` 裡那些 [RequiredCourse]
  /// **實例本身**（`RequiredCourse` 沒有覆寫 `==`，所以這是同一性比對）——
  /// 畫面上拿同一個物件來查就對得到。
  final Map<RequiredCourse, CourseGrade> byRequirement;

  /// 成績裡**沒有對到任何一項必修**的課。
  ///
  /// **一定要列出來，不能默默丟掉。** 只認完全同名的話，「體育」對不上
  /// 「19-體育課程」、「國文」對不上「12-國文領域」、「博雅【人文探索】」
  /// 對不上「11-博雅課程」—— 那些是命名差異，不是「你沒修」。
  /// 使用者看得到這份清單才判斷得出來哪些其實已經抵掉了。
  final List<CourseGrade> unmatched;

  CourseGrade? operator [](RequiredCourse r) => byRequirement[r];

  RequirementMatch of(RequiredCourse r) =>
      RequirementMatch(requirement: r, course: byRequirement[r]);
}

/// 比對用的名字。
///
/// 只做三件事：壓空白、全形括號換半形、拿掉學校在要求前面加的編號
/// （`12-國文領域` → `國文領域`、`28-資工系專題(一)` → `資工系專題(一)`）。
///
/// **刻意不做任何模糊比對。** 見 [matchGraduation] 的說明。
String _key(String name) {
  final t = clean(name)
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(' ', '');
  return t.replaceFirst(RegExp(r'^\d+-'), '');
}

/// 排序用：先拿已經過了的，再拿正在修的，最後才是不及格／退選的。
///
/// 同一門課修兩次（先當掉再重修）在成績裡是兩列。對到要求上的應該是
/// **過了的那一列**，不是當掉的那一列。
int _preference(CourseGrade c) {
  if (c.mark.isPassed) return 0;
  if (c.mark.isPending) return 1;
  return 2;
}

/// 把 [grades] 對到 [status] 的必修表上。
///
/// **只認完全同名，一個字都不能差。**
///
/// 這不是偷懶，是在真實資料上驗過的：用「包含」去比的話，
///
/// - 要求「程式設計」會被課程「程式設計**實習**」對上 —— 那是另一門
///   1 學分的課，而畫面上會打一個勾說必修過了
/// - 要求「程式設計**(二)**」會被課程「程式設計」對上 —— 同樣是別門課
///
/// 兩個都會害使用者少修一門必修，而畫面上看起來完全正常。
/// 反過來的錯（明明抵掉了卻說還沒修）只會讓他多看一眼，代價小得多，
/// 所以**寧可對不到，不要對錯**。對不到的課全部列在 [GraduationMatch.unmatched]。
///
/// 一門課只能滿足一項要求：「英文(大一英文)」在必修表上有兩列，
/// 成績裡有兩門就兩列都對得到，只有一門就只對得到一列。
GraduationMatch matchGraduation(GraduationStatus status, GradeReport grades) {
  // 名字 -> 還沒被用掉的課，好的排前面
  final pool = <String, List<CourseGrade>>{};
  for (final c in grades.courses) {
    pool.putIfAbsent(_key(c.name), () => []).add(c);
  }
  for (final list in pool.values) {
    list.sort((a, b) => _preference(a).compareTo(_preference(b)));
  }

  final used = <CourseGrade>{};
  final byRequirement = <RequiredCourse, CourseGrade>{};

  for (final group in status.groups) {
    for (final r in group.courses) {
      final candidates = pool[_key(r.name)];
      if (candidates == null) continue;
      for (final c in candidates) {
        if (used.contains(c)) continue;
        used.add(c);
        byRequirement[r] = c;
        break;
      }
    }
  }

  return GraduationMatch(
    byRequirement: byRequirement,
    unmatched: [
      for (final c in grades.courses)
        if (!used.contains(c)) c,
    ],
  );
}

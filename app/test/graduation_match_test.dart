import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/grades.dart';
import 'package:ntou_app/src/parsing/graduation.dart';
import 'package:ntou_app/src/parsing/graduation_match.dart';

import 'fixtures.dart';

/// 把成績單上的課對到畢業必修表。
///
/// 這裡每一種錯都有方向性，而且**兩個方向的代價差很多**：
///
/// - 對錯了（說你修過其實沒修）→ 少修一門必修 → 畢不了業
/// - 對不到（明明抵掉了卻說還沒修）→ 多看一眼
///
/// 所以規則是「只認完全同名」，而且對不到的一定要列出來。
const _grades = 'Application_GRD_GRD50_GRD5010_02__QUERY_BTN1_1151.html';
const _graduation = 'Application_ENR_ENRG0_ENRG010_01.html';

GraduationStatus _status(String rows) => parseGraduation('''
<html><body><form>
<table id="DataList"><tr><td>
  系訂專業必修
  <table id="DataList_ctl00_DataGrid_FIELD">
    <tr><th>修課學年期</th><th>原修課程名稱</th><th>選課別</th><th>學年別</th>
        <th>開課單位</th><th>成績</th><th>學分</th>
        <th>學期</th><th>必修課目</th><th>學分</th><th>審核結果</th></tr>
    $rows
  </table>
</td></tr></table>
</form></body></html>''');

/// 一列還沒修的必修要求。
String _need(String name) =>
    '<tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td>'
    '<td>一上</td><td>$name</td><td>3</td><td></td></tr>';

GradeReport _report(List<CourseGrade> courses) =>
    GradeReport(courses: courses);

CourseGrade _course(String name, String mark) => CourseGrade(
      term: '1151',
      name: name,
      mark: parseGradeMark(mark),
    );

void main() {
  group('**只認完全同名 —— 這是在真實資料上驗過的**', () {
    test('「程式設計實習」不可以拿去抵「程式設計」', () {
      // 這是最貴的那個錯。程式設計實習是另一門 1 學分的課，
      // 用「包含」去比就會對上，而畫面上會打一個勾說必修過了 ——
      // 使用者因此少修一門必修。
      final m = matchGraduation(
        _status(_need('程式設計')),
        _report([_course('程式設計實習', '抵')]),
      );

      final req = m.byRequirement.keys;
      expect(req, isEmpty, reason: '對上了就是會害人少修一門必修');
      expect(m.unmatched.single.name, '程式設計實習');
    });

    test('「程式設計」不可以拿去抵「程式設計(二)」', () {
      // 反方向的同一個坑：要求比課名長的時候。
      final m = matchGraduation(
        _status(_need('程式設計(二)')),
        _report([_course('程式設計', '抵')]),
      );
      expect(m.byRequirement, isEmpty);
    });

    test('完全同名就對得到', () {
      final status = _status(_need('作業系統'));
      final m = matchGraduation(status, _report([_course('作業系統', '抵')]));

      final r = status.groups.single.courses.single;
      expect(m[r]?.name, '作業系統');
      expect(m.of(r).done, isTrue);
      expect(m.of(r).byMatch, isTrue, reason: '學校還沒登錄，是我們比對到的');
      expect(m.unmatched, isEmpty);
    });

    test('要求前面的編號不算在名字裡', () {
      // 「28-資工系專題(一)」的編號是學校排版用的。
      final status = _status(_need('28-資工系專題(一)'));
      final m = matchGraduation(
          status, _report([_course('資工系專題(一)', '85')]));
      expect(m[status.groups.single.courses.single], isNotNull);
    });
  });

  group('什麼才算「修過了」', () {
    RequirementMatch match(String mark) {
      final status = _status(_need('演算法'));
      final m = matchGraduation(status, _report([_course('演算法', mark)]));
      return m.of(status.groups.single.courses.single);
    }

    test('抵免算過', () => expect(match('抵').done, isTrue));
    test('有分數算過', () => expect(match('85').done, isTrue));

    test('**不及格不算過**', () {
      // 對到了不等於完成。打一個勾說你修過被當掉的必修，
      // 跟前面那個「對錯課」一樣會害人少修。
      final m = match('*55');
      expect(m.done, isFalse);
      expect(m.course, isNotNull, reason: '還是要對到 —— 使用者要知道自己修過但當了');
    });

    test('期中退選不算過', () => expect(match('W').done, isFalse));

    test('成績未到是「修課中」，不是完成也不是沒修', () {
      final m = match('+');
      expect(m.done, isFalse);
      expect(m.inProgress, isTrue);
    });

    test('學校自己登錄的優先 —— 那是權威來源', () {
      final status = _status(
        '<tr><td>1141</td><td>演算法</td><td>必</td><td>1</td>'
        '<td>資工系</td><td>85</td><td>3</td>'
        '<td>一上</td><td>演算法</td><td>3</td><td></td></tr>',
      );
      final m = matchGraduation(status, _report([]));
      final r = status.groups.single.courses.single;
      expect(m.of(r).done, isTrue);
      expect(m.of(r).bySchool, isTrue);
      expect(m.of(r).byMatch, isFalse);
    });
  });

  group('一門課只能滿足一項要求', () {
    test('必修表上兩列同名，成績只有一門就只對得到一列', () {
      final status = _status(_need('微積分') + _need('微積分'));
      final m = matchGraduation(status, _report([_course('微積分', '抵')]));
      expect(m.byRequirement, hasLength(1));
    });

    test('成績有兩門就兩列都對得到', () {
      final status = _status(_need('英文(大一英文)') + _need('英文(大一英文)'));
      final m = matchGraduation(
        status,
        _report([_course('英文(大一英文)', '抵'), _course('英文(大一英文)', '抵')]),
      );
      expect(m.byRequirement, hasLength(2));
    });

    test('**重修過的課，對到的是過了的那一次**', () {
      // 先當掉再重修，成績裡是兩列。對到當掉那一列的話，
      // 畫面上會說這門必修還沒過。
      final status = _status(_need('微積分'));
      final m = matchGraduation(
        status,
        _report([_course('微積分', '*40'), _course('微積分', '75')]),
      );
      expect(m.of(status.groups.single.courses.single).course?.mark.score, '75');
    });
  });

  group('對不到的課一定要列出來', () {
    test('名稱對不起來的抵免要看得到', () {
      // 「體育」對不上「19-體育課程」—— 那是命名差異，不是沒修。
      // 使用者看得到這份清單才判斷得出來。
      final m = matchGraduation(
        _status(_need('19-體育課程')),
        _report([_course('體育', '抵')]),
      );
      expect(m.byRequirement, isEmpty);
      expect(m.unmatched.single.name, '體育');
    });
  });

  group('真實資料', () {
    late GraduationMatch m;
    late GraduationStatus status;

    setUp(() {
      status = parseGraduation(fixture(_graduation));
      m = matchGraduation(status, parseGrades(fixture(_grades)));
    });

    test('對到十門系訂專業必修和共同教育課程', () {
      // 完全同名的那些：計算機概論、程式設計、離散數學、微積分、作業系統、
      // 資料結構、演算法、計算機組織學、人工智慧概論、英文(大一英文)×2
      expect(m.byRequirement.length, greaterThanOrEqualTo(10));

      final names = m.byRequirement.values.map((c) => c.name).toSet();
      expect(names, contains('作業系統'));
      expect(names, contains('資料結構'));
      expect(names, contains('演算法'));
      expect(names, contains('計算機概論'));
    });

    test('**「程式設計實習」沒有被拿去抵任何必修**', () {
      // 真實資料裡就有這門課，而必修表上就有「程式設計」。
      final matched = m.byRequirement.values.map((c) => c.name).toList();
      expect(matched, isNot(contains('程式設計實習')));
      expect(matched, isNot(contains('計算機概論實習')));
      expect(m.unmatched.map((c) => c.name), contains('程式設計實習'));
    });

    test('體育／國文／博雅對不起來，而且列在對不到的清單裡', () {
      // 學校用「19-體育課程」「12-國文領域」「11-博雅課程」這種領域名稱。
      final left = m.unmatched.map((c) => c.name).toList();
      expect(left, contains('體育'));
      expect(left, contains('國文'));
      expect(left.where((n) => n.startsWith('博雅')), isNotEmpty);
    });

    test('本學期在修的課算「修課中」，不是完成', () {
      // 那 6 門都是 `+`（成績未到）。
      final inProgress = [
        for (final g in status.groups)
          for (final r in g.courses)
            if (m.of(r).inProgress) r.name,
      ];
      expect(inProgress, contains('計算機概論'));
      expect(inProgress, contains('程式設計'));
      for (final g in status.groups) {
        for (final r in g.courses) {
          expect(m.of(r).done && m.of(r).inProgress, isFalse,
              reason: '完成和修課中不能同時成立');
        }
      }
    });

    test('沒有任何一門課被用掉兩次', () {
      final used = m.byRequirement.values.toList();
      expect(used.length, used.toSet().length);
    });
  }, skip: skipUnlessAll([_grades, _graduation]));
}

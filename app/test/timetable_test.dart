import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/parsing/models.dart';
import 'package:ntou_app/src/parsing/timetable.dart';

void main() {
  group('parseTimeSlots', () {
    test('逗號分隔', () {
      expect(parseTimeSlots('一3,4'), [const TimeSlot(0, 3), const TimeSlot(0, 4)]);
    });

    test('範圍', () {
      expect(parseTimeSlots('(三)5-7'), [
        const TimeSlot(2, 5),
        const TimeSlot(2, 6),
        const TimeSlot(2, 7),
      ]);
    });

    test('多天', () {
      expect(parseTimeSlots('一3,4 五6'), [
        const TimeSlot(0, 3),
        const TimeSlot(0, 4),
        const TimeSlot(4, 6),
      ]);
    });

    test('「星期」「週」的寫法都認', () {
      expect(parseTimeSlots('星期二第3節'), [const TimeSlot(1, 3)]);
      expect(parseTimeSlots('週四 7'), [const TimeSlot(3, 7)]);
    });

    test('連在一起的數字**刻意不猜**', () {
      // 「一34」可以是第3、第4節，也可以是第34節（不存在，所以應該讀成 3 和 4）；
      // 但「一12」到底是第12節還是第1、2節，沒有任何線索可以判斷 ——
      // 海大的節次編號是 00–16，兩種讀法都合法。
      //
      // 猜錯的代價不對稱：課排到錯的格子，使用者看不出來，就這樣去錯的教室。
      // 所以分不出來時回空的，課仍然留在清單裡。
      expect(parseTimeSlots('一34'), isEmpty);
      expect(parseTimeSlots('一12'), isEmpty);
    });

    test('單一位數沒有歧義', () {
      expect(parseTimeSlots('一3'), [const TimeSlot(0, 3)]);
    });

    test('空字串、認不得的格式回空的，不丟例外', () {
      expect(parseTimeSlots(''), isEmpty);
      expect(parseTimeSlots('　'), isEmpty);
      expect(parseTimeSlots('另行公告'), isEmpty);
    });

    test('重複的時段只算一次', () {
      expect(parseTimeSlots('一3,3'), [const TimeSlot(0, 3)]);
    });
  });

  group('weekdayColumns', () {
    test('用表頭文字比對，不假設欄位順序', () {
      // 有些課表把週六日放前面、有些沒有週日、有些節次欄在最右邊。
      final cols = weekdayColumns(['節次', '一', '二', '三', '四', '五']);
      expect(cols, {1: 0, 2: 1, 3: 2, 4: 3, 5: 4});
    });

    test('「第一節」不能被當成星期一', () {
      // 含「一」但那是節次。含「節」的欄位一律排除。
      expect(weekdayColumns(['第一節', '週一', '週二']), {1: 0, 2: 1});
    });

    test('太長的表頭不算星期欄', () {
      expect(weekdayColumns(['一年級課程表']), isEmpty);
    });
  });

  group('parseTimetableCell', () {
    test('課名 / 老師 / 教室', () {
      final r = parseTimetableCell('計算機概論\n王小明\n電資305');
      expect(r.name, '計算機概論');
      expect(r.teacher, '王小明');
      expect(r.room, '電資305');
    });

    test('只有課名也不會壞', () {
      final r = parseTimetableCell('體育');
      expect(r.name, '體育');
      expect(r.teacher, '');
      expect(r.room, '');
    });

    test('空的格子回空字串，不丟例外', () {
      expect(parseTimetableCell('   ').name, '');
    });
  });

  group('parseTimetableGrid', () {
    test('連堂課（rowspan）兩節都要算進去', () {
      const html = '''
        <table>
          <tr><th>節次</th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th></tr>
          <tr><td>3</td><td rowspan="2">微積分<br>李老師<br>綜一01</td>
              <td></td><td></td><td></td><td></td></tr>
          <tr><td>4</td><td></td><td></td><td></td><td></td></tr>
        </table>
      ''';

      final courses = parseTimetableGrid(html);
      expect(courses.length, 1);
      expect(courses.single.name, '微積分');
      expect(courses.single.teacher, '李老師');
      expect(courses.single.room, '綜一01');
      // 這是整個 parser 存在的理由：不攤平 rowspan 的話這裡只會有 (0,3)
      expect(courses.single.slots, [const TimeSlot(0, 3), const TimeSlot(0, 4)]);
    });

    test('<br> 要當成換行，不然課名跟老師會黏成一串', () {
      const html = '''
        <table>
          <tr><th>節</th><th>一</th><th>二</th><th>三</th><th>四</th><th>五</th></tr>
          <tr><td>1</td><td>國文<br>陳老師</td><td></td><td></td><td></td><td></td></tr>
        </table>
      ''';
      expect(parseTimetableGrid(html).single.name, '國文');
      expect(parseTimetableGrid(html).single.teacher, '陳老師');
    });

    test('認不出四天以上的表格不當成課表', () {
      const html = '<table><tr><th>公告</th></tr><tr><td>停課</td></tr></table>';
      expect(parseTimetableGrid(html), isEmpty);
    });
  });

  group('parseCourseList', () {
    const html = '''
      <table id="DataGrid">
        <tr><td>序號</td><td>學期</td><td>課號</td><td>課名</td><td>授課老師</td>
            <td>學分</td><td>選別</td><td>年級班別</td><td>上課時間</td></tr>
        <tr><td>0001</td><td>1151</td><td>B57011RQ</td><td>計算機概論</td>
            <td>王小明</td><td>3</td><td>A</td><td>1年A班</td><td>一3,4</td></tr>
        <tr><td>0002</td><td>1151</td><td>B57012RQ</td><td>線性代數</td>
            <td>李老師</td><td>3</td><td>A</td><td>1年A班</td><td>另行公告</td></tr>
      </table>
    ''';

    test('用表頭文字對應欄位', () {
      final courses = parseCourseList(html);
      expect(courses.length, 2);

      final first = courses.first;
      expect(first.name, '計算機概論');
      expect(first.code, 'B57011RQ');
      expect(first.teacher, '王小明');
      expect(first.credits, 3);
      expect(first.selectionType, 'A');
      expect(first.classLabel, '1年A班');
      expect(first.slots, [const TimeSlot(0, 3), const TimeSlot(0, 4)]);
    });

    test('時間解析不出來的課還是要列出來', () {
      // 少一個時段是「格子上少一堂課」，把整堂課吞掉是「使用者不知道自己有這門課」。
      final second = parseCourseList(html)[1];
      expect(second.name, '線性代數');
      expect(second.slots, isEmpty);
    });

    test('原始欄位整列保留，UI 才能顯示認不得的欄位', () {
      expect(parseCourseList(html).first.raw['學期'], '1151');
    });

    test('表頭順序讀得出來', () {
      expect(courseListColumns(html).take(4), ['序號', '學期', '課號', '課名']);
    });

    test('沒有 DataGrid 時回空的，不丟例外', () {
      expect(parseCourseList('<html><body>查無符合資料!!</body></html>'), isEmpty);
    });
  });
}

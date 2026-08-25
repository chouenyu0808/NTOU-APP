import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:ntou_app/src/ais/exceptions.dart';
import 'package:ntou_app/src/ais/forms.dart';

void main() {
  group('formFields', () {
    test('撈出一般欄位、跳過送出鈕', () {
      final doc = html_parser.parse('''
        <form>
          <input type="hidden" name="__VIEWSTATE" value="abc" />
          <input type="text" name="Q_STNO" value="B10900000" />
          <input type="submit" name="QUERY_BTN1" value="選課清單" />
          <input type="button" name="QCLEAR_BTN1" value="還原" />
        </form>
      ''');
      final fields = formFields(doc);

      expect(fields['__VIEWSTATE'], 'abc');
      expect(fields['Q_STNO'], 'B10900000');
      // 送出鈕只在「你按的那一顆」才送。全部帶上的話伺服器不知道你按了哪個。
      expect(fields.containsKey('QUERY_BTN1'), isFalse);
      expect(fields.containsKey('QCLEAR_BTN1'), isFalse);
    });

    test('沒勾的 checkbox / radio 不送', () {
      final doc = html_parser.parse('''
        <form>
          <input type="checkbox" name="on" checked />
          <input type="checkbox" name="off" />
          <input type="radio" name="r1" value="a" checked />
          <input type="radio" name="r2" value="b" />
        </form>
      ''');
      final fields = formFields(doc);

      expect(fields.containsKey('on'), isTrue);
      expect(fields.containsKey('off'), isFalse);
      expect(fields['r1'], 'a');
      expect(fields.containsKey('r2'), isFalse);
    });

    test('select 取 selected，沒有就取第一個', () {
      final doc = html_parser.parse('''
        <form>
          <select name="Q_AYEAR">
            <option value="114">114</option>
            <option value="115" selected>115</option>
          </select>
          <select name="Q_SMS">
            <option value="1">1</option>
            <option value="2">2</option>
          </select>
        </form>
      ''');
      final fields = formFields(doc);

      expect(fields['Q_AYEAR'], '115');
      expect(fields['Q_SMS'], '1', reason: '沒有 selected 時瀏覽器送第一個');
    });

    test('沒有任何 option 的 select 完全不送', () {
      // 瀏覽器不會送這個欄位。送空字串的話 ASP.NET 的 event validation
      // 會判定「這個值不是我渲染出來的」而拋例外 —— 表面上只是一句
      // 通用的 403，完全看不出是哪個欄位害的。
      final doc = html_parser.parse('''
        <form><select name="Q_LECTR_TCH_CH"></select></form>
      ''');
      expect(formFields(doc).containsKey('Q_LECTR_TCH_CH'), isFalse);
    });
  });

  group('onclickSideEffects', () {
    test('doQuery 會順手設 QUERY_TYPE', () {
      final doc = html_parser.parse(
        '''<input name="QUERY_BTN1" onclick="return doQuery('1')" />''',
      );
      final button = doc.querySelector('input[name="QUERY_BTN1"]');

      // 不送 QUERY_TYPE 的話伺服器直接拋例外，只回一句
      // 「系統發生錯誤, 請通知系統管理人員」，看不出少了什麼。
      expect(onclickSideEffects(button), {'QUERY_TYPE': '1'});
    });

    test('沒有引數的 doQuery() 不設欄位', () {
      final doc = html_parser.parse(
        '''<input name="QUERY_BTN1" onclick="return doQuery()" />''',
      );
      expect(onclickSideEffects(doc.querySelector('input')), isEmpty);
    });

    test('button 是 null 時回空的', () {
      expect(onclickSideEffects(null), isEmpty);
    });
  });

  group('checkValues', () {
    final doc = html_parser.parse('''
      <form>
        <select name="Q_CLASS">
          <option value="00">00</option>
          <option value="03">03</option>
          <option value="05">05</option>
        </select>
        <input type="text" name="Q_FREE" />
      </form>
    ''');

    test('合法的值放行', () {
      expect(() => checkValues(doc, {'Q_CLASS': '03'}), returnsNormally);
    });

    test('不是選項的值在本機就擋下來', () {
      // 實際踩過：'05' 被當成數字轉成 '5'，伺服器回一個看不懂的 403。
      // 在這裡擋掉，錯誤訊息才有用。
      expect(
        () => checkValues(doc, {'Q_CLASS': '5'}),
        throwsA(isA<InvalidFieldValue>()),
      );
    });

    test('不是下拉的欄位不驗，交給伺服器', () {
      expect(() => checkValues(doc, {'Q_FREE': '任何值'}), returnsNormally);
    });
  });

  group('selectOptions', () {
    test('讀出選項與預設值', () {
      final doc = html_parser.parse('''
        <select name="Q_AYEAR">
          <option value="113">113</option>
          <option value="115" selected>115</option>
        </select>
      ''');

      expect(selectOptions(doc, 'Q_AYEAR').map((o) => o.value), ['113', '115']);
      expect(selectedOption(doc, 'Q_AYEAR'), '115');
    });

    test('找不到的下拉回空的', () {
      final doc = html_parser.parse('<div></div>');
      expect(selectOptions(doc, 'Q_AYEAR'), isEmpty);
      expect(selectedOption(doc, 'Q_AYEAR'), isNull);
    });
  });

  group('scrapeHiddenFields', () {
    test('抓 WebForms 的狀態欄位', () {
      final doc = html_parser.parse('''
        <form>
          <input type="hidden" name="__VIEWSTATE" value="v1" />
          <input type="hidden" name="__EVENTVALIDATION" value="e1" />
          <input type="hidden" name="Q_STNO" value="不是狀態欄位" />
        </form>
      ''');
      final hidden = scrapeHiddenFields(doc);

      expect(hidden['__VIEWSTATE'], 'v1');
      expect(hidden['__EVENTVALIDATION'], 'e1');
      expect(hidden.containsKey('Q_STNO'), isFalse);
    });
  });
}

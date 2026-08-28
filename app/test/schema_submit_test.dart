import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ais/form_schema.dart';
import 'package:ntou_app/src/menu/menu_catalog.dart';

import 'fake_ais.dart';

/// 送出去的 POST body 裡到底有什麼。
///
/// 這一組驗的是「跟瀏覽器一樣」——radio / checkbox / disabled 這幾種欄位，
/// 瀏覽器送什麼、不送什麼是有規則的，而不照規則的症狀都不是「欄位錯了」，
/// 是 ASP.NET 的 event validation 回一句通用的 403，看不出是誰害的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fn = AisFunction(
    title: '維護資料',
    path: 'Application/X/X10/X1010_.aspx',
    trail: ['測試', 'X', '維護資料'],
  );

  /// 一張什麼控制項都有的表單。
  ///
  /// 形狀照抄 `spike/fixtures/…ENR3030_01.html`：radio / checkbox 的 `CNAME`
  /// 在**包住整組的 span** 上，選項的字在 `<label for>` 裡，
  /// `disabled` 也是掛在 span 上而不是每一顆 input。
  const page = '<html><head><title>X1010_維護資料</title></head><body><form>'
      '<input type="hidden" name="__VIEWSTATE" value="vs">'
      // 單選
      '<span id="M_KIND" CNAME="類別" class="form-check">'
      '<input id="M_KIND_0" type="radio" name="M_KIND" value="0" checked="checked" />'
      '<label for="M_KIND_0">課號</label>'
      '<input id="M_KIND_1" type="radio" name="M_KIND" value="1" />'
      '<label for="M_KIND_1">課名</label>'
      '</span>'
      // 複選：0 預設打勾、1 沒有
      r'<span id="M_TAG" CNAME="身分" class="form-check">'
      r'<input id="M_TAG_0" type="checkbox" name="M_TAG$0" checked="checked" />'
      '<label for="M_TAG_0">一般生</label>'
      r'<input id="M_TAG_1" type="checkbox" name="M_TAG$1" />'
      '<label for="M_TAG_1">僑生</label>'
      '</span>'
      // 學校鎖住的一格
      '<span disabled="disabled">'
      '<input name="M_LOCKED" type="text" CNAME="學號" value="B11234567" />'
      '</span>'
      // 還不能上傳的檔案欄位
      '<input name="M_FILE" type="file" CNAME="附件" />'
      '<textarea name="M_MEMO" CNAME="備註" maxlength="500">舊的</textarea>'
      '<input type="submit" name="SAVE_BTN1" value="存檔" ml="CB_存檔">'
      '</form></body></html>';

  late ScriptedAis ais;

  setUp(() {
    ais = ScriptedAis();
  });

  /// 打開功能頁、（可選）改幾格、按存檔，回傳最後那一次 POST 的 body。
  Future<Map<String, String>> submit({
    Map<String, String> edits = const {},
  }) async {
    // session 要先用內建的預設回應建起來（那裡才有登入頁和驗證碼圖），
    // 腳本之後才換上 —— 一開始就攔掉所有請求的話連 beginLogin 都過不了。
    final repo = await loggedInRepository(ais);
    ais.reply = (_) => page;
    var view = await repo.openFunction(fn);
    view = view.copyWith(values: {...view.values, ...edits});
    await repo.runQuery(view, 'SAVE_BTN1');
    return ais.seen.last.form;
  }

  test('複選：勾起來的送 on，沒勾的完全不出現', () async {
    final form = await submit();

    expect(form[r'M_TAG$0'], 'on', reason: '頁面上預設打勾的那一個');
    expect(form.containsKey(r'M_TAG$1'), isFalse,
        reason: '沒勾的欄位瀏覽器根本不送，不是送空字串');
  });

  test('取消勾選要真的從 body 裡消失', () async {
    // 這是 `omit` 存在的理由。`submitForm` 是拿頁面現值當基底再蓋上新值 ——
    // 蓋得上去、蓋不掉。少了 omit，使用者在畫面上取消了勾選，
    // 送出去的 body 裡那一格還是打勾的。
    final form = await submit(edits: {'M_TAG': ''});

    expect(form.containsKey(r'M_TAG$0'), isFalse,
        reason: '畫面上取消了，body 裡卻還在 —— 存檔會把它存回去');
    expect(form.containsKey(r'M_TAG$1'), isFalse);
  });

  test('複選：勾第二個，兩個都送', () async {
    final form = await submit(
      edits: {'M_TAG': SchemaField.joinChecked([r'M_TAG$0', r'M_TAG$1'])},
    );

    expect(form[r'M_TAG$0'], 'on');
    expect(form[r'M_TAG$1'], 'on');
  });

  test('單選：送選中的那個值，一個欄位而不是好幾個', () async {
    final form = await submit(edits: {'M_KIND': '1'});

    expect(form['M_KIND'], '1');
  });

  test('學校鎖住的欄位不送 —— 瀏覽器不送 disabled 的東西', () async {
    // 就算 UI 不小心把值放進 values 也一樣要擋掉。
    final form = await submit(edits: {'M_LOCKED': 'B99999999'});

    expect(form['M_LOCKED'], isNot('B99999999'),
        reason: '這一格使用者不該改得動，更不該真的送出去');
  });

  test('檔案欄位永遠是空的 —— 使用者打進去的字不會被當成檔案送出', () async {
    // UI 那邊畫的是一格「不能用」的提示而不是文字框，所以正常情況打不進東西。
    // 這裡驗的是就算真的有值進到 values 也不會出去 —— 欄位本身留著（空值），
    // 跟瀏覽器上一個沒選檔案的 file input 一樣。
    final form = await submit(edits: {'M_FILE': '隨手打的字'});

    expect(form['M_FILE'], isEmpty);
  });

  test('textarea 送得出去 —— 以前這一格根本不存在', () async {
    final form = await submit(edits: {'M_MEMO': '新的內容'});

    expect(form['M_MEMO'], '新的內容');
  });
}

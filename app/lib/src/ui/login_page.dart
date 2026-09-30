import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'app_controller.dart';
import 'cached_timetable_page.dart';
import 'ntou_mark.dart';
import 'theme.dart';

/// 登入完成後回到原本要做的事；取消時保留原頁。
Future<bool> ensureSignedIn(
  BuildContext context,
  AppController controller,
) async {
  if (controller.phase == AppPhase.ready) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LoginPage(controller: controller)),
  );
  return controller.phase == AppPhase.ready;
}

/// 登入畫面。
///
/// 進到這一頁就開始跑登入流程（開登入頁 → 通過排隊關卡 → 抓驗證碼），
/// 那要三個請求、好幾秒。使用者在讀畫面、打學號的時候就讓它跑完，
/// 比等他按了按鈕才開始要快得多。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller, this.recognizeCaptcha});

  final AppController controller;

  /// 可注入辨識結果，以測試延遲、誤判與手動接管；正式使用裝置端 ML Kit。
  final Future<String> Function(Uint8List bytes)? recognizeCaptcha;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  final _captchaFocus = FocusNode();
  // 學號和密碼也要有 FocusNode —— 驗證碼回來時要看使用者是不是正在打它們，
  // 見 [_focusCaptcha]。
  final _accountFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _remember = false;
  bool _showPassword = false;
  bool _passwordRestored = false;
  bool _autoAttempted = false;
  bool _manualEdited = false;
  Uint8List? _recognizedCaptcha;
  Uint8List? _recognizingCaptcha;
  String? _recognitionStatus;

  AppController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _account.text = _c.username;
    _remember = _c.hasSavedPassword;
    _restorePassword();
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.startLogin());
    _c.addListener(_onControllerChanged);
  }

  Future<void> _restorePassword() async {
    final account = _account.text;
    final saved = await _c.savedPassword();
    // 儲存讀取可能比手動輸入慢，不覆蓋使用者已換的帳號或密碼。
    if (!mounted ||
        saved == null ||
        _account.text != account ||
        _password.text.isNotEmpty) {
      return;
    }
    setState(() {
      _password.text = saved;
      _passwordRestored = true;
    });
    _tryAutomaticLogin();
  }

  void _tryAutomaticLogin() {
    if (!mounted ||
        _autoAttempted ||
        _manualEdited ||
        !_passwordRestored ||
        !_remember ||
        !_c.hasSavedPassword ||
        _c.error != null ||
        _recognizedCaptcha == null ||
        !identical(_recognizedCaptcha, _c.captcha) ||
        !_canSubmit ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _autoAttempted = true;
    _submit();
  }

  void _onCredentialsEdited(String _) {
    setState(() => _manualEdited = true);
  }

  void _openCached() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CachedTimetablePage(controller: _c),
    ),
  );

  /// 錯誤卡自己有沒有給「看快取課表」那顆鈕。
  bool get _errorOffersCache =>
      _c.error != null && _Explained.of(_c.error!).showCached;

  Uint8List? _lastCaptcha;

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_c.phase == AppPhase.ready &&
        Navigator.of(context).canPop() &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
      return;
    }
    if (_c.phase == AppPhase.openingLogin) {
      _recognizingCaptcha = null;
      _recognitionStatus = null;
      _recognizedCaptcha = null;
      _captcha.clear();
      _captchaLength = 0;
    }
    if (_c.phase != AppPhase.awaitingCaptcha) {
      _lastCaptcha = null;
      return;
    }
    if (_c.captcha != null && _c.captcha != _lastCaptcha) {
      _lastCaptcha = _c.captcha;
      _autoRecognizeCaptcha(_c.captcha!);
      _focusCaptcha();
    }
  }

  /// 把游標移到驗證碼欄 —— **只有在使用者沒有正在打別的欄位的時候**。
  ///
  /// 驗證碼是三個請求、好幾秒之後才回來的，而那幾秒正好是使用者在打學號和
  /// 密碼的時候。原本這裡是每次 notify 都無條件 requestFocus，症狀是
  /// 密碼打到一半游標自己跳到驗證碼欄，後面幾個字打進錯的格子 ——
  /// 而密碼欄是遮起來的，使用者要到登入失敗才會發現。
  void _focusCaptcha() {
    if (_accountFocus.hasFocus || _passwordFocus.hasFocus) return;
    _captchaFocus.requestFocus();
  }

  /// 已記住帳密時最多自動送出一次；失敗後換圖也不重新取得自動送出資格。
  Future<void> _autoRecognizeCaptcha(Uint8List bytes) async {
    if (identical(_recognizingCaptcha, bytes)) return;
    setState(() {
      _recognizingCaptcha = bytes;
      _recognitionStatus = '正在辨識驗證碼…';
    });
    try {
      final rawText = await (widget.recognizeCaptcha ?? _recognizeOnDevice)(
        bytes,
      );
      // 只保留英文字母和數字（過濾掉空白、雜訊標點符號）
      final text = rawText.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

      // **不是剛好 4 碼就整個放棄，不要截斷之後再填。** 驗證碼一定是 4 碼，
      // 認出 6 碼代表這次本來就認錯了（116×54 的圖，雜訊線被讀成字元是常態），
      // 砍成 4 碼只是把一個錯的答案變得像對的。
      //
      // 這一行也是登入鈕能不能按的關鍵。`maxLength: 4` 只擋鍵盤打進來的字，
      // **擋不住程式直接設值** —— `_captcha.text = '6碼'` 之後欄位就是 6 碼。
      // 而 [_canSubmit] 要求長度剛好等於 4，[_CaptchaField] 又設了
      // `counterText: ''` 把「6/4」藏起來。三個湊在一起的症狀是：
      // 使用者看到驗證碼欄有字、以為填好了，登入鈕卻一直是暗的，
      // 而畫面上沒有任何一處說得出為什麼。
      if (!mounted) return;
      if (_c.phase != AppPhase.awaitingCaptcha ||
          !identical(bytes, _c.captcha)) {
        return;
      }
      // 只記錄字數，不記錄驗證碼、帳密或頁面內容。
      debugPrint('驗證碼辨識完成：${text.length} 碼');
      if (text.length != 4) {
        setState(() => _recognitionStatus = '這張驗證碼未能辨識，請手動輸入或重新辨識。');
        return;
      }

      // 使用者已經自己動手了就不要蓋掉他打的東西。
      if (_captcha.text.isNotEmpty) {
        setState(() => _recognitionStatus = null);
        return;
      }

      _captcha.text = text;
      _recognizedCaptcha = bytes;
      // `TextEditingController` 直接設值不會觸發 onChanged，`_captchaLength`
      // 要自己跟上 —— 不同步的話，使用者刪掉一個字再補回來會被當成
      // 「剛打完第 4 碼」而自動送出，等於繞回原本那個迴圈。
      _captchaLength = text.length;
      setState(() => _recognitionStatus = '已填入辨識結果，請確認是否正確。');
      _tryAutomaticLogin();
      _focusCaptcha();
    } catch (e) {
      // **只進 debug log，不給使用者看。** 這條路徑上的例外文字可能夾著
      // 頁面或檔案路徑的碎片，而這一頁其他每一處都刻意只說類型不說內容。
      // 對使用者來說「OCR 掛了」跟「沒認出來」要做的事一模一樣：自己打。
      debugPrint('OCR failed: ${e.runtimeType}');
      if (mounted && identical(bytes, _c.captcha)) {
        setState(() => _recognitionStatus = '辨識暫時無法使用，請手動輸入或重新辨識。');
      }
    } finally {
      if (mounted && identical(bytes, _recognizingCaptcha)) {
        setState(() => _recognizingCaptcha = null);
      }
    }
  }

  Future<String> _recognizeOnDevice(Uint8List bytes) async {
    final scaledBytes = await _scaleUpToMinSize(bytes, minSize: 64);
    final tempDir = await getTemporaryDirectory();
    final directory = await tempDir.createTemp('captcha-');
    final file = File('${directory.path}/image.png');
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await file.writeAsBytes(scaledBytes, flush: true);
      return (await recognizer.processImage(InputImage.fromFile(file))).text;
    } finally {
      await recognizer.close();
      await directory.delete(recursive: true);
    }
  }

  /// ML Kit 要求圖片最小 32x32，把驗證碼放大到至少 [minSize] 像素。
  /// 用 dart:ui 做，不需要額外套件。
  Future<Uint8List> _scaleUpToMinSize(
    Uint8List bytes, {
    int minSize = 64,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final src = frame.image;

    final w = src.width;
    final h = src.height;

    // 圖夠大就直接回傳原始 bytes
    if (w >= minSize && h >= minSize) {
      src.dispose();
      return bytes;
    }

    // 等比例放大：確保短邊 >= minSize
    final scale = minSize / (w < h ? w : h);
    final newW = (w * scale).ceil();
    final newH = (h * scale).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    src.dispose();

    final picture = recorder.endRecording();
    final resized = await picture.toImage(newW, newH);
    picture.dispose();
    final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
    resized.dispose();

    return byteData!.buffer.asUint8List();
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    // 使用者中途離開的話，學校那端的 session 還開著（開登入頁時就開了），
    // 會擋住他自己在瀏覽器登入。登入成功時 phase 是 ready，abandonLogin() 會跳過。
    _c.abandonLogin();
    _account.dispose();
    // 密碼欄的內容跟著這個 controller 一起被回收。
    _password.dispose();
    _captcha.dispose();
    _captchaFocus.dispose();
    _accountFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _busy =>
      _c.phase == AppPhase.openingLogin || _c.phase == AppPhase.loggingIn;

  bool get _canSubmit =>
      !_busy &&
      _c.phase == AppPhase.awaitingCaptcha &&
      _account.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _captcha.text.trim().length == 4;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    _autoAttempted = true;
    await _c.submitLogin(
      account: _account.text.trim(),
      password: _password.text,
      captchaText: _captcha.text.trim(),
      remember: _remember,
    );
    // 新圖在 openingLogin 時清空；此處再清會與下一輪辨識結果競速。
  }

  /// 驗證碼欄上一次的長度。
  ///
  /// 用來分辨「使用者剛打完第 4 碼」和「整格一次被填滿」——
  /// 見 [_onCaptchaChanged]。
  int _captchaLength = 0;

  void _onCaptchaChanged(String value) {
    _manualEdited = true;
    final was = _captchaLength;
    _captchaLength = value.length;
    setState(() {});

    // 打完第 4 碼直接送出，少按一次登入鈕。
    //
    // **只認「3 → 4」這一步。** 整格一次被填滿（貼上、自動填入、程式設值）時
    // 不自動送：那種情況使用者多半還想先看一眼，而驗證碼是一次性的 ——
    // 送錯一次就燒掉一張，而且學校的失敗是靜默的（重畫登入頁配新圖，不給訊息）。
    if (was == 3 && value.length == 4 && _canSubmit) _submit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('登入校務系統')),
      body: Material(
        color: scheme.surface,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              const _Wordmark(),
              const SizedBox(height: 24),

              if (_c.error != null) ...[
                _ErrorCard(
                  message: _c.error!,
                  // 帳號被自己在瀏覽器上佔住的時候，這條路要出現在**錯誤旁邊**，
                  // 不是在頁尾等他捲下去找。
                  onViewCached: _c.timetable == null ? null : _openCached,
                ),
                const SizedBox(height: 16),
              ],

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _account,
                        focusNode: _accountFocus,
                        decoration: const InputDecoration(
                          labelText: '學號',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        onChanged: _onCredentialsEdited,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: '密碼',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            tooltip: _showPassword ? '隱藏密碼' : '顯示密碼',
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: _onCredentialsEdited,
                      ),
                      const SizedBox(height: 14),
                      _CaptchaField(
                        controller: _c,
                        textController: _captcha,
                        focusNode: _captchaFocus,
                        onRefresh: _c.startLogin,
                        onChanged: _onCaptchaChanged,
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('記住密碼'),
                subtitle: const Text('下次開啟時自動登入；驗證碼辨識失敗可手動輸入'),
              ),

              const SizedBox(height: 12),
              FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('登入'),
              ),

              if (!_busy &&
                  _c.phase == AppPhase.awaitingCaptcha &&
                  _recognitionStatus != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(_recognitionStatus!, textAlign: TextAlign.center),
                ),
                if (_recognizingCaptcha == null && _captcha.text.isEmpty)
                  TextButton(
                    onPressed: () {
                      final bytes = _c.captcha;
                      if (bytes != null) _autoRecognizeCaptcha(bytes);
                    },
                    child: const Text('重新辨識'),
                  ),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _c.phase == AppPhase.openingLogin
                        ? '正在連接學校並取得驗證碼'
                        : _c.loginStatus,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              // 帳號在瀏覽器登著的時候 App 根本登不進去 —— 那時候這是唯一
              // 還看得到自己資料的路。只有真的有快取才顯示。
              // 錯誤卡上已經給過同一條路的時候就不要再給一次 ——
              // 同一頁上兩顆一模一樣的按鈕會讓人以為它們做的是不同的事。
              // 反過來，卡片沒給的時候（例如只是驗證碼打錯）這裡還是要有，
              // 不然帳號被佔住以外的失敗就沒路可走了。
              if (_c.timetable != null && !_errorOffersCache) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _openCached,
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('先看上次抓到的課表'),
                ),
              ],

              const SizedBox(height: 28),
              const _SingleSessionNotice(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      NtouMark(size: 42, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NTOU', style: Theme.of(context).textTheme.titleLarge),
            Text('國立臺灣海洋大學', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

/// 驗證碼圖 + 輸入框。
///
/// 圖是伺服器產的實體檔（`/Temp/Captcha/<每個 session 隨機>.png`），
/// 只能從頁面上抓、不能寫死。
///
/// 圖片在裝置端辨識，欄位保留手動修正；自動送出由登入頁統一限制次數。
class _CaptchaField extends StatelessWidget {
  const _CaptchaField({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.onRefresh,
    required this.onChanged,
    required this.onSubmitted,
  });

  final AppController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onRefresh;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = controller.captcha;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: textController,
            focusNode: focusNode,
            maxLength: 4,
            autocorrect: false,
            enableSuggestions: false,
            // 4 碼、**區分大小寫**。不要用 textCapitalization 幫使用者「修正」。
            textCapitalization: TextCapitalization.none,
            inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
            decoration: const InputDecoration(
              labelText: '驗證碼',
              helperText: '區分大小寫',
              prefixIcon: Icon(Icons.pin_outlined),
              counterText: '',
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: '點一下放大，長按換一張',
          child: InkWell(
            // 圖只有 116×54，四個字裡有一兩個看不清是常態。與其讓人一直換圖
            // （每換一張就是學校那端一次請求），不如先讓他放大看清楚。
            onTap: image == null ? onRefresh : () => _enlarge(context, image),
            onLongPress: onRefresh,
            borderRadius: BorderRadius.circular(NtouTheme.radiusMd),
            child: Ink(
              width: 116,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(NtouTheme.radiusMd),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: image != null
                  ? Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        image,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : controller.phase != AppPhase.openingLogin &&
                        controller.phase != AppPhase.loggingIn
                  ? const Center(
                      child: Icon(Icons.refresh, color: NtouTheme.seed),
                    )
                  : const Center(
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 放大看驗證碼。
  ///
  /// 底色固定白色 —— 學校給的圖是白底，深色模式下直接鋪在深色面板上
  /// 會看不出字的邊界。
  Future<void> _enlarge(BuildContext context, Uint8List image) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          content: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Image.memory(
              image,
              width: MediaQuery.sizeOf(ctx).width * 0.62,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRefresh();
              },
              child: const Text('換一張'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('看清楚了'),
            ),
          ],
        ),
      );
}

/// 一則登入失敗，翻成「你現在該做什麼」。
///
/// 學校給的是狀態描述，不是指示：「系統同時一次僅許可一個帳號登入」語法沒錯，
/// 但看到的人不會知道兇手是自己五分鐘前在電腦上開的選課系統。這裡對已知的
/// 幾種失敗給標題和下一步。
///
/// 對不上的照原文顯示，不硬套一個可能是錯的解釋 —— 學校哪天改了措辭、
/// 或出現沒對應到的新錯誤時，使用者看到的還是真的那句話。
class _Explained {
  const _Explained(this.title, this.body, {this.showCached = false});

  final String title;
  final String body;

  /// 要不要給「先看上次抓到的課表」那條路。
  final bool showCached;

  static _Explained of(String message) {
    if (message.contains('別的地方登入') || message.contains('僅許可一個帳號')) {
      return const _Explained(
        '這個帳號已經在別的地方登入了',
        '學校系統一次只允許一個地方登入。你在電腦上開著選課系統或成績查詢的'
            '時候，這裡就會被擋下來。\n\n'
            '先去那邊按登出，或等幾分鐘讓它自己逾時，再回來重試。',
        showCached: true,
      );
    }
    // 只認「打錯了」那一種（學校的字樣就是「驗證碼錯誤」，見 selectors.json
    // 的 failureMarkers）。`拿不到驗證碼圖片` 是抓圖失敗 —— 畫面上根本沒有圖，
    // 叫使用者重打一次是錯的指示。
    if (message.contains('驗證碼錯誤')) {
      return const _Explained('驗證碼不對', '圖已經換成新的一張了，重打一次就好。學號和密碼不用重打。');
    }
    if (message.contains('密碼') || message.contains('帳號')) {
      return const _Explained(
        '學號或密碼不對',
        '這是學校單一入口的密碼，跟校務系統是同一組。'
            '連錯幾次學校會鎖帳號，不確定的話先去網頁版試一次。',
      );
    }
    if (message.contains('逾時') || message.contains('重新登入')) {
      return const _Explained(
        '登入逾時了',
        '這一頁放太久，學校那邊的表單已經失效。重新填一次就好。',
        showCached: true,
      );
    }
    // 對不上的就照原文顯示，不要硬套一個可能是錯的解釋。
    return const _Explained('', '');
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onViewCached});

  final String message;

  /// 有快取課表時才給。`null` 代表沒有東西可看，那就不要給一個空的承諾。
  final VoidCallback? onViewCached;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = _Explained.of(message);
    final on = scheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(NtouTheme.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: on, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.title.isEmpty)
                  Text(message, style: TextStyle(color: on, height: 1.4))
                else ...[
                  Text(
                    e.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: on,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(e.body, style: TextStyle(color: on, height: 1.5)),
                ],
                if (e.showCached && onViewCached != null) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: onViewCached,
                    style: TextButton.styleFrom(
                      foregroundColor: on,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('先看上次抓到的課表'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 這不是免責聲明，是使用者真的會遇到而且會困惑的事。
class _SingleSessionNotice extends StatelessWidget {
  const _SingleSessionNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '學校系統一個帳號同時只能登入一個地方。'
            '你在電腦上開著選課系統的時候，這裡會登不進去。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'app_controller.dart';
import 'cached_timetable_page.dart';
import 'theme.dart';

/// 登入畫面。
///
/// 進到這一頁就開始跑登入流程（開登入頁 → 通過排隊關卡 → 抓驗證碼），
/// 那要三個請求、好幾秒。使用者在讀畫面、打學號的時候就讓它跑完，
/// 比等他按了按鈕才開始要快得多。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});

  final AppController controller;

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
    final saved = await _c.savedPassword();
    if (saved != null && mounted) _password.text = saved;
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

  /// 試著把驗證碼認出來，**填進欄位就停手**。
  ///
  /// 認出來之後不自動送出。這不是保守，是這條路徑上唯一站得住的做法：
  ///
  ///   - 驗證碼是**一次性**的。送出去那張圖就作廢，不管對錯。
  ///   - 學校的失敗是**靜默**的：重畫一次登入頁配一張新圖，不給任何訊息。
  ///   - 圖只有 116×54，四個字裡有一兩個看不清是常態，OCR 認錯很正常。
  ///
  /// 三件事湊在一起就是一個自己會轉的迴圈：認成 4 碼 → 自動送 → 靜默失敗 →
  /// [AppController.submitLogin] 自動換一張 → 又自動認、又自動送。存了密碼的話
  /// 開 App 就開始連環重試，使用者插不進手，也看不出來為什麼一直失敗。
  ///
  /// 所以這裡只負責填。要不要送是使用者按下去的那一下 ——
  /// 這跟 [_onCaptchaChanged] 只認「使用者親手打完第 4 碼」是同一條線。
  Future<void> _autoRecognizeCaptcha(Uint8List bytes) async {
    try {
      // ML Kit 要求圖片最小 32x32，先放大再送去辨識
      final scaledBytes = await _scaleUpToMinSize(bytes, minSize: 64);

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/captcha.png');
      await file.writeAsBytes(scaledBytes, flush: true);

      final inputImage = InputImage.fromFile(file);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final rawText = recognizedText.text;
      // 只保留英文字母和數字（過濾掉空白、雜訊標點符號）
      final text = rawText.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

      // 認不出來就當沒發生過。**不要跳訊息說「辨識失敗」** ——
      // 使用者本來就要自己打，那句話只是在報告一件他不需要知道的內部狀況。
      if (text.isEmpty || !mounted) return;
      if (_c.phase != AppPhase.awaitingCaptcha) return;

      // 使用者已經自己動手了就不要蓋掉他打的東西。
      if (_captcha.text.isNotEmpty) return;

      _captcha.text = text;
      // `TextEditingController` 直接設值不會觸發 onChanged，`_captchaLength`
      // 要自己跟上 —— 不同步的話，使用者刪掉一個字再補回來會被當成
      // 「剛打完第 4 碼」而自動送出，等於繞回原本那個迴圈。
      _captchaLength = text.length;
      setState(() {});
      _focusCaptcha();
    } catch (e) {
      // **只進 debug log，不給使用者看。** 這條路徑上的例外文字可能夾著
      // 頁面或檔案路徑的碎片，而這一頁其他每一處都刻意只說類型不說內容。
      // 對使用者來說「OCR 掛了」跟「沒認出來」要做的事一模一樣：自己打。
      debugPrint('OCR failed: ${e.runtimeType}');
    }
  }

  /// ML Kit 要求圖片最小 32x32，把驗證碼放大到至少 [minSize] 像素。
  /// 用 dart:ui 做，不需要額外套件。
  Future<Uint8List> _scaleUpToMinSize(Uint8List bytes, {int minSize = 64}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
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
    await _c.submitLogin(
      account: _account.text.trim(),
      password: _password.text,
      captchaText: _captcha.text.trim(),
      remember: _remember,
    );
    if (mounted) {
      _captcha.clear();
      // `clear()` 不會觸發 TextField 的 onChanged，長度要自己歸零，
      // 不然下一張驗證碼打第一碼就會被當成「剛打完第 4 碼」。
      _captchaLength = 0;
    }
  }

  /// 驗證碼欄上一次的長度。
  ///
  /// 用來分辨「使用者剛打完第 4 碼」和「整格一次被填滿」——
  /// 見 [_onCaptchaChanged]。
  int _captchaLength = 0;

  void _onCaptchaChanged(String value) {
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.18),
              scheme.surface,
              scheme.surface,
            ],
            stops: const [0, 0.42, 1],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            children: [
              const _Wordmark(),
              const SizedBox(height: 36),

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
                        onChanged: (_) => setState(() {}),
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
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                            tooltip: _showPassword ? '隱藏密碼' : '顯示密碼',
                          ),
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
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
                subtitle: Text(
                  '存在這支手機的安全儲存區，不會上傳到任何伺服器',
                  style: theme.textTheme.bodySmall,
                ),
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, NtouTheme.surf],
            ),
            borderRadius: BorderRadius.circular(NtouTheme.radiusPill),
          ),
          child: const Icon(Icons.sailing, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 18),
        Text(
          'NTOU',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: scheme.onSurface,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '國立臺灣海洋大學',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 驗證碼圖 + 輸入框。
///
/// 圖是伺服器產的實體檔（`/Temp/Captcha/<每個 session 隨機>.png`），
/// 只能從頁面上抓、不能寫死。
///
/// 這裡原本的註解寫「刻意不做 OCR」，但 `_autoRecognizeCaptcha` 已經在做了
/// （commit 1f6acb3，專案作者自己加的）。註解跟程式相反比沒有註解更糟，
/// 所以寫現況：圖抓回來之後會先送 ML Kit 辨識，**認到什麼就填什麼，不送出**。
///
/// 為什麼不自動送見 [_LoginPageState._autoRecognizeCaptcha] ——
/// 一句話版本：驗證碼是一次性的、學校的失敗是靜默的，兩件事加上會認錯的 OCR
/// 就是一個使用者插不進手的重試迴圈。輸入框任何時候都能手動編輯。
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
  Future<void> _enlarge(BuildContext context, Uint8List image) => showDialog<void>(
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
/// **原文一定留著。** 學校哪天改了措辭、或出現我們沒對應到的新錯誤，
/// 使用者看到的還是真的那句話 —— 翻譯蓋掉原文的話，回報問題的人會說
/// 「App 說我驗證碼錯了」，而學校其實說的是別的。
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
    if (message.contains('驗證碼')) {
      return const _Explained(
        '驗證碼不對',
        '圖已經換成新的一張了，重打一次就好。學號和密碼不用重打。',
      );
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
                  Text(
                    message,
                    style: TextStyle(color: on, height: 1.4),
                  )
                else ...[
                  Text(
                    e.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: on, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(e.body, style: TextStyle(color: on, height: 1.5)),
                  const SizedBox(height: 10),
                  // 學校的原文。壓小、但不藏起來 —— 見上面的說明。
                  Text(
                    '學校原本的訊息：$message',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: on.withValues(alpha: 0.7)),
                  ),
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
        Icon(Icons.info_outline,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
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

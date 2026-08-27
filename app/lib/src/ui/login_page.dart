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

  Uint8List? _lastCaptcha;

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_c.phase == AppPhase.awaitingCaptcha) {
      if (_c.captcha != null && _c.captcha != _lastCaptcha) {
        _lastCaptcha = _c.captcha;
        _autoRecognizeCaptcha(_c.captcha!);
      }
      _captchaFocus.requestFocus();
    } else {
      _lastCaptcha = null;
    }
  }

  Future<void> _autoRecognizeCaptcha(Uint8List bytes) async {
    // 顯示「辨識中」提示
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在自動辨識驗證碼…'),
          duration: Duration(seconds: 3),
        ),
      );
    }

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

      if (!mounted) return;
      // 顯示辨識結果（不管長度），方便診斷
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty
                ? '辨識失敗（圖太難辨識），請手動輸入'
                : text.length == 4
                    ? '自動辨識：$text，嘗試登入中…'
                    : '辨識到「$text」(${text.length}碼)，請確認後手動修改',
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      // 如果過濾後剛好是 4 碼，就填入並嘗試送出
      if (text.length == 4 && mounted && _c.phase == AppPhase.awaitingCaptcha) {
        _captcha.text = text;
        setState(() {});
        if (_canSubmit) {
          _submit();
        }
      } else if (text.isNotEmpty && text.length != 4 && mounted) {
        // 辨識到但長度不對，先填進去讓使用者修正
        _captcha.text = text;
        setState(() {});
        _captchaFocus.requestFocus();
      }
    } catch (e, st) {
      debugPrint('OCR failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OCR 錯誤：$e'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
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
                _ErrorCard(message: _c.error!),
                const SizedBox(height: 16),
              ],

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _account,
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
              if (_c.timetable != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CachedTimetablePage(controller: _c),
                    ),
                  ),
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
            borderRadius: BorderRadius.circular(22),
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
/// 只能從頁面上抓、不能寫死。**刻意不做 OCR** —— 讓使用者自己打，
/// 體驗差不了多少，也不會踩到繞過防護那條線。
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
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              width: 116,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, height: 1.4),
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

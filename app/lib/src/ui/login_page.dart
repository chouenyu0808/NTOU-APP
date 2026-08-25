import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_c.phase == AppPhase.awaitingCaptcha) _captchaFocus.requestFocus();
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
    if (mounted) _captcha.clear();
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
                        onChanged: (_) => setState(() {}),
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
          message: '點一下換一張',
          child: InkWell(
            onTap: onRefresh,
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
        borderRadius: BorderRadius.circular(14),
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

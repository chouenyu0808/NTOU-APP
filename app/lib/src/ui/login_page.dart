import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';

/// 登入畫面。
///
/// 驗證碼是**進到這一頁才去拿**的，不是開 App 就拿 —— 每抓一次驗證碼就等於
/// 在學校伺服器上開一個 session，沒事不要開。
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

  /// 已經關掉這一頁了。
  ///
  /// 登入成功之後 controller 還會再通知好幾次（查課表的進度），
  /// 而 `mounted` 在退場動畫跑完之前都還是 true ——
  /// 沒有這個旗標的話會 pop 第二次，把下面的課表頁一起關掉。
  bool _popped = false;

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_c.phase == AppPhase.awaitingCaptcha) _captchaFocus.requestFocus();
    if (_c.phase == AppPhase.ready && !_popped) {
      _popped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    // 使用者按返回鍵走掉的話，學校那端的 session 還開著（開登入頁時就開了），
    // 會擋住他自己在瀏覽器登入。登入成功而關閉這一頁時 phase 是 ready，
    // abandonLogin() 會自己跳過。
    unawaited(_c.abandonLogin());
    _account.dispose();
    // 密碼欄的內容跟著這個 controller 一起被回收。
    _password.dispose();
    _captcha.dispose();
    _captchaFocus.dispose();
    super.dispose();
  }

  bool get _busy =>
      _c.phase == AppPhase.openingLogin || _c.phase == AppPhase.loggingIn;

  Future<void> _submit() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) return;
    if (_captcha.text.trim().length != 4) return;
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

    return Scaffold(
      appBar: AppBar(title: const Text('登入教學務系統')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (_c.error != null) ...[
              _ErrorCard(message: _c.error!),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _account,
              decoration: const InputDecoration(
                labelText: '學號',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '密碼',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  tooltip: _showPassword ? '隱藏密碼' : '顯示密碼',
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 20),
            _CaptchaField(
              controller: _c,
              textController: _captcha,
              focusNode: _captchaFocus,
              onRefresh: _c.startLogin,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('記住密碼'),
              subtitle: Text(
                '存在這支手機的安全儲存區（Keychain / Keystore），'
                '不會上傳到任何伺服器。驗證碼每次還是要自己打。',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _c.phase != AppPhase.awaitingCaptcha
                  ? null
                  : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登入'),
            ),
            const SizedBox(height: 24),
            const _SingleSessionNotice(),
          ],
        ),
      ),
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
    required this.onSubmitted,
  });

  final AppController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onRefresh;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = controller.captcha;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              labelText: '驗證碼（區分大小寫）',
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onSubmitted: onSubmitted,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 120,
                height: 56,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: image != null
                    ? Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true)
                    : const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            ),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('換一張'),
            ),
          ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '學校系統一個帳號同時只能登入一個地方。'
              '你在電腦上開著選課系統的時候，這裡會登不進去 —— '
              '那時候 App 會顯示上次抓到的課表。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

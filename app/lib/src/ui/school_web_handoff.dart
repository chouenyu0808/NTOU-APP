import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_controller.dart';

/// 網頁不共用 App 的登入，先釋放學校 session，避免使用者被自己擋住。
class SchoolWebHandoff extends StatelessWidget {
  const SchoolWebHandoff({
    super.key,
    required this.controller,
    required this.functionTitle,
  });
  final AppController controller;
  final String functionTitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('到學校網頁完成'),
        onPressed: () => _open(context),
      ),
    ),
  );

  Future<void> _open(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('接著到學校網頁完成'),
        content: Text(
          '將結束 App 的校務登入，讓你可以在瀏覽器登入。課表與預排會保留。\n\n'
          '登入網頁後請開啟「$functionTitle」。這裡尚未送出的欄位與附件不會自動帶過去。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('留在這裡'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('開啟網頁'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.handleDetached();
    if (!context.mounted) return;
    final uri = Uri.parse(controller.repository.config.baseUrl);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* 下方提供複製入口。 */
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('無法開啟瀏覽器，請複製網址後開啟'),
          action: SnackBarAction(
            label: '複製網址',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: uri.toString())),
          ),
        ),
      );
    }
  }
}

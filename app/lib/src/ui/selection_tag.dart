import 'package:flutter/material.dart';

import 'theme.dart';

/// 必修 / 選修的標籤。
///
/// 必修用強調色 —— 那是「非修不可」，跟選修在畫面上要一眼分得開。
/// 認不得的代碼（設定檔沒對照的）也照樣顯示，只是用中性色：
/// 使用者看到「B」至少知道要自己查，看到猜錯的「選修」會照著排課。
class SelectionTag extends StatelessWidget {
  const SelectionTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final required = label.contains('必');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: required ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(NtouTheme.radiusXs),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: required ? scheme.onErrorContainer : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

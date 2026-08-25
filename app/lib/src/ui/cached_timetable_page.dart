import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'timetable_page.dart';

/// 沒登入時看上次抓到的課表。
///
/// 為什麼需要這條路：學校系統**一個帳號同時只能有一個 session**。
/// 使用者在電腦上開著選課系統的時候，App 是登不進去的 —— 而那正好是
/// 選課期間、最需要看課表的時候。硬性的登入關卡會把人鎖在自己的資料外面。
///
/// 所以登入頁上留了一個次要入口，只在真的有快取時才出現。
class CachedTimetablePage extends StatelessWidget {
  const CachedTimetablePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // 登入成功就自己退場，讓使用者回到正常的關卡流程
        if (controller.phase == AppPhase.ready) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
        }
        return TimetablePage(controller: controller, showLoginAction: false);
      },
    );
  }
}

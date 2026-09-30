import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 只存功能路徑，不存查詢結果或個人資料。
class RecentFunctions {
  static final changes = ValueNotifier<int>(0);
  static const _key = 'ui.recent_functions';
  static Future<List<String>> read() async =>
      (await SharedPreferences.getInstance()).getStringList(_key) ?? [];
  static Future<void> record(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_key) ?? [];
    await prefs.setStringList(
      _key,
      [path, ...paths.where((p) => p != path)].take(5).toList(),
    );
    changes.value++;
  }
}

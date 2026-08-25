import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../planner/plan_models.dart';

/// 預排課表的本機儲存。
///
/// 跟 TimetableCache 分開存：預排是使用者自己寫的，不是從學校抓的，
/// 邏輯不一樣，混在一起的話登出時清課表快取會順便把預排也清掉。
class PlanStore {
  PlanStore({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= _injected ?? await SharedPreferences.getInstance();

  static String _key(String year, String semester) => 'plan.$year.$semester';
  static const _kIndex = 'plan._index';

  Future<CoursePlan?> read(String year, String semester) async {
    final raw = (await _p).getString(_key(year, semester));
    if (raw == null) return null;
    try {
      return CoursePlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<void> write(CoursePlan plan) async {
    final prefs = await _p;
    await prefs.setString(_key(plan.year, plan.semester), jsonEncode(plan.toJson()));

    final idx = prefs.getStringList(_kIndex) ?? [];
    final tag = '${plan.year}|${plan.semester}';
    if (!idx.contains(tag)) {
      await prefs.setStringList(_kIndex, [...idx, tag]);
    }
  }

  Future<void> delete(String year, String semester) async {
    final prefs = await _p;
    await prefs.remove(_key(year, semester));
    final idx = prefs.getStringList(_kIndex) ?? [];
    await prefs.setStringList(
      _kIndex,
      idx.where((t) => t != '$year|$semester').toList(),
    );
  }
}

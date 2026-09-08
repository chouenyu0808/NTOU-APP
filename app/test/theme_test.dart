import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntou_app/src/ui/theme.dart';

void main() {
  group('NtouTheme.moduleColor', () {
    test('依序取色', () {
      expect(NtouTheme.moduleColor(0), NtouTheme.moduleColors[0]);
      expect(NtouTheme.moduleColor(1), NtouTheme.moduleColors[1]);
    });

    test('超過數量時繞回開頭 —— 模組再多也一定有顏色', () {
      final n = NtouTheme.moduleColors.length;
      expect(NtouTheme.moduleColor(n), NtouTheme.moduleColors[0]);
      expect(NtouTheme.moduleColor(n + 1), NtouTheme.moduleColors[1]);
    });

    test('模組色不重複', () {
      // 原本這裡寫的是「剛好 13 個，對得上現有的 13 個模組」。
      // 2026-09-08 學校一次上架 13 個新模組（13 → 26），那個數字就過期了。
      //
      // **重點從來不是數量，是「夠不夠、有沒有重複」** ——
      // `moduleColor` 是 `index % length`，色數少於模組數就會有兩個模組同色，
      // 而那正好毀掉這組顏色唯一的用途（一眼分得開、位置變成肌肉記憶）。
      //
      // 「色數 ≥ 模組數」那一條在 `module_list_page_test` 裡，
      // 它讀得到真實的 `menu_tree.json`。
      expect(
        NtouTheme.moduleColors.toSet().length,
        NtouTheme.moduleColors.length,
      );
    });
  });

  group('NtouTheme.of', () {
    test('用 Material 3，且亮/暗給出對應 brightness 的配色', () {
      final light = NtouTheme.of(Brightness.light);
      final dark = NtouTheme.of(Brightness.dark);
      expect(light.useMaterial3, isTrue);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
    });

    test('刻意避開 Material 預設的紫，用海洋藍當種子', () {
      // 深海藍 seed，不是那個「一看就知道還沒設計過」的預設紫。
      expect(NtouTheme.seed, const Color(0xFF00506B));
      final light = NtouTheme.of(Brightness.light);
      expect(light.colorScheme.primary, isNot(const Color(0xFF6750A4)));
    });
  });
}

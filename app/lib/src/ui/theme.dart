import 'package:flutter/material.dart';

/// 配色。
///
/// 海洋大學 —— 深海藍為主、青綠為輔。刻意不用 Material 預設那個紫色，
/// 那個誰都認得出來是「還沒設計過」。
class NtouTheme {
  const NtouTheme._();

  /// 深海藍。App bar、主要按鈕、選中狀態。
  static const Color seed = Color(0xFF00506B);
  static const Color teal = Color(0xFF00838F);
  static const Color surf = Color(0xFF26C6DA);

  static ThemeData of(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      secondary: teal,
      tertiary: surf,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // 表單欄位：填色 + 無邊框。學校的查詢頁動輒十個欄位，
      // 每個都畫一圈外框的話畫面全是線。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }

  /// 每個模組一個顏色。
  ///
  /// 純粹是為了讓 13 個模組在網格上一眼分得開 —— 顏色本身沒有語意，
  /// 但位置固定，用久了就變成肌肉記憶（「請假是紫色那個」）。
  /// 所以**不要重排**，加新模組往後接。
  static const List<Color> moduleColors = [
    Color(0xFF1E88E5), // 藍
    Color(0xFFF9A825), // 琥珀
    Color(0xFF00897B), // 藍綠
    Color(0xFF6D4C41), // 棕
    Color(0xFF43A047), // 綠
    Color(0xFF8E24AA), // 紫
    Color(0xFFE53935), // 紅
    Color(0xFF3949AB), // 靛
    Color(0xFF00ACC1), // 青
    Color(0xFFFB8C00), // 橙
    Color(0xFF7CB342), // 黃綠
    Color(0xFFD81B60), // 桃紅
    Color(0xFF546E7A), // 藍灰
  ];

  static Color moduleColor(int index) =>
      moduleColors[index % moduleColors.length];
}

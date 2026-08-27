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

      // 卡片同時用三種方式把邊界拿掉過：elevation 0、底色只比背景深一點點
      // （#F0F4F8 鋪在 #F6FAFE 上是 1.05:1）、又沒有邊框。三個裡至少要留一個，
      // 不然卡片跟背景是連在一起的，看不出哪裡是一張卡。
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        // 原本對所有 state 都回同一個顏色，選中跟沒選中的字一模一樣 ——
        // 只剩背後那顆藥丸在表示「你在這一頁」。
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant,
            )),
      ),

      // **中文要自己調行高。** Material 的預設行高是為拉丁字母調的，
      // 中文字面高、沒有 descender，照抄會擠成一團。
      //
      // 數字（節次、學分、課號、時間）用 tabularFigures：課表和學分表是
      // 一欄一欄對齊看的，比例數字會讓每一列的數字左右飄。
      textTheme: _textTheme(scheme),

      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // `outlineVariant` 本來就是設計成分隔線用的最淡色，再壓一半 alpha
      // 只有 1.28:1 —— 在手機上等於沒有。
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }

  /// 中文的行高與級距。
  ///
  /// 只調 height 和幾個級距，不換字體 —— 字體要打包進 App，那是另一件事。
  static TextTheme _textTheme(ColorScheme scheme) {
    const body = TextStyle(height: 1.6);
    const title = TextStyle(height: 1.4);
    const tabular = TextStyle(
      height: 1.4,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return TextTheme(
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: body,
      titleLarge: tabular.copyWith(fontWeight: FontWeight.w700),
      // 課名是清單的主角，原本卻用最小的標題級（14/w500）——
      // 跟旁邊的老師、學分幾乎一樣重。
      titleMedium: title.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: title.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      labelLarge: tabular,
      labelMedium: tabular,
      labelSmall: tabular,
      headlineSmall: tabular.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: title.copyWith(fontWeight: FontWeight.w700),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }

  /// 圓角。
  ///
  /// 原本散在各檔案裡有 6/8/10/12/14/15/16/22 八種，其中 10、14、15
  /// 彼此差不到 2px —— 那不是層次，是沒有統一過。收斂成五階。
  static const double radiusXs = 6; // 小標籤
  static const double radiusSm = 8; // 格子、色塊
  static const double radiusMd = 12; // 按鈕、輸入框、ListTile
  static const double radiusLg = 16; // 卡片
  static const double radiusPill = 22; // 藥丸

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

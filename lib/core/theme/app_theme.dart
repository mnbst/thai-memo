// =============================================================================
// app_theme.dart
// アプリ全体の ThemeData 構築。app.dart から切り出してある。
// スクリーンショット生成（tools/x_post）など、MyApp を起動しない経路からも
// 同じ見た目を再現できるようにするため。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_config.dart';
import '../../presentation/providers/settings_provider.dart';
import 'app_colors.dart';

TextTheme buildThaiTextTheme(ThaiFont font, TextTheme base) {
  TextTheme themed;
  switch (font) {
    case ThaiFont.notoSansThai:
      themed = GoogleFonts.notoSansThaiTextTheme(base);
    case ThaiFont.mitr:
      themed = GoogleFonts.mitrTextTheme(base);
    case ThaiFont.sarabun:
      themed = GoogleFonts.sarabunTextTheme(base);
    case ThaiFont.krub:
      themed = GoogleFonts.krubTextTheme(base);
  }
  return _scaleTextTheme(themed, 2.5);
}

TextTheme _scaleTextTheme(TextTheme base, double delta) {
  TextStyle scale(TextStyle? style) {
    if (style == null) return const TextStyle();
    final size = style.fontSize ?? 14.0;
    return style.copyWith(fontSize: size + delta);
  }

  return TextTheme(
    displayLarge: scale(base.displayLarge),
    displayMedium: scale(base.displayMedium),
    displaySmall: scale(base.displaySmall),
    headlineLarge: scale(base.headlineLarge),
    headlineMedium: scale(base.headlineMedium),
    headlineSmall: scale(base.headlineSmall),
    titleLarge: scale(base.titleLarge),
    titleMedium: scale(base.titleMedium),
    titleSmall: scale(base.titleSmall),
    bodyLarge: scale(base.bodyLarge),
    bodyMedium: scale(base.bodyMedium),
    bodySmall: scale(base.bodySmall),
    labelLarge: scale(base.labelLarge),
    labelMedium: scale(base.labelMedium),
    labelSmall: scale(base.labelSmall),
  );
}

ThemeData buildAppLightTheme(ThaiFont fontFamily) => buildAppTheme(
      fontFamily,
      AppColors.light,
      ThemeData.light().textTheme,
      AppColors.paper,
    );

ThemeData buildAppDarkTheme(ThaiFont fontFamily) => buildAppTheme(
      fontFamily,
      AppColors.dark,
      ThemeData.dark().textTheme,
      AppColors.paperDark,
    );

/// 明暗で違うのは ColorScheme と背景色だけ。形（角丸・高さ・罫線）は共通。
///
/// カードは影ではなく 1px の罫線で面を分ける。影を残すと、深藍の面と
/// 温白の背景のコントラストに影が重なって濁るため。
ThemeData buildAppTheme(
  ThaiFont fontFamily,
  ColorScheme scheme,
  TextTheme baseTextTheme,
  Color background,
) {
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    textTheme: buildThaiTextTheme(fontFamily, baseTextTheme),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      // 日本語は端末のシステムフォントにフォールバックする。google_fonts/ に
      // 同梱しているのは NotoSans であって NotoSansJP ではないので、
      // notoSansJp を指定すると実行時に読み込みへ失敗する。
      titleTextStyle: GoogleFonts.notoSans(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.04 * 17,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 74,
      elevation: 0,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.notoSans(
          fontSize: 14.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 2,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.primary,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        side: BorderSide(color: scheme.primary, width: 1.5),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        minimumSize: const Size(0, AppConfig.minTapTarget),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}

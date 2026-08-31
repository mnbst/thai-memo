import 'package:flutter/material.dart';

/// アプリ全体のカラートークン。
///
/// 深藍 × 金 × 朱。朱だけはアプリアイコンの赤をそのまま使い、
/// アイコンとアプリ内の連続性を担保する。
/// 彩度の高いアイコンの青（#012CE0）は本文面には持ち込まず、
/// 起動時のスプラッシュから深藍へ沈める遷移だけで繋ぐ。
abstract final class AppColors {
  /// アプリアイコンの青。スプラッシュの開始色にだけ使う。
  static const Color brandBlue = Color(0xFF012CE0);

  /// 主要面。カード・ボタン・選択中のタブ。
  static const Color indigo = Color(0xFF16243F);

  /// 学習単語・進捗など「伸びている」ことを示す差し色。
  static const Color gold = Color(0xFFC39A4E);

  /// 白い面に載せる金。[gold] は深藍の上で読ませる明るさなので、紙の上では
  /// 沈めないと本文と同じ重さで読めない。
  static const Color goldInk = Color(0xFFA8823C);

  /// 正解・肯定。
  static const Color jade = Color(0xFF2F7A63);

  /// 誤答・お気に入り・エラー。アプリアイコンの赤と同一。
  static const Color vermilion = Color(0xFFFB2621);

  /// 背景（温白の紙）。
  static const Color paper = Color(0xFFF6F2EA);

  /// 背景（ダーク）。
  static const Color paperDark = Color(0xFF0F1524);

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: indigo,
    onPrimary: Color(0xFFF4EFE4),
    primaryContainer: Color(0xFFDDE3EF),
    onPrimaryContainer: indigo,
    secondary: Color(0xFF4A5A7A),
    onSecondary: Color(0xFFF4EFE4),
    secondaryContainer: Color(0xFFEDEAE1),
    onSecondaryContainer: Color(0xFF3B4256),
    tertiary: gold,
    onTertiary: Color(0xFF2A2007),
    tertiaryContainer: Color(0xFFF2E7CF),
    onTertiaryContainer: Color(0xFF6B5220),
    error: vermilion,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFE1DE),
    onErrorContainer: Color(0xFF7A0D0A),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF17203A),
    onSurfaceVariant: Color(0xFF6E7286),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFBF8F2),
    surfaceContainer: paper,
    surfaceContainerHigh: Color(0xFFF1ECE1),
    surfaceContainerHighest: Color(0xFFEBE5D8),
    surfaceTint: indigo,
    outline: Color(0xFFC9C2B2),
    outlineVariant: Color(0xFFE2DACB),
    inverseSurface: indigo,
    onInverseSurface: Color(0xFFF4EFE4),
    inversePrimary: Color(0xFFA9BEE6),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  /// 深藍の面に載せる中身のための ColorScheme。
  ///
  /// 例文カードの再生ボタン・シークバー・バッジはテーマの色から描かれるので、
  /// カードを `Theme` でこれに差し替えれば、各ウィジェットを触らずに色が合う。
  static const ColorScheme onIndigo = ColorScheme(
    brightness: Brightness.dark,
    primary: gold,
    onPrimary: Color(0xFF2A2007),
    primaryContainer: Color(0x2EC39A4E),
    onPrimaryContainer: Color(0xFFE8D6AE),
    // IconButton.filledTonal（再生・マイク）の面。
    secondary: Color(0xFFB8C2D6),
    onSecondary: indigo,
    secondaryContainer: Color(0xFF2A3A5B),
    onSecondaryContainer: Color(0xFFF2EDE3),
    tertiary: gold,
    onTertiary: Color(0xFF2A2007),
    tertiaryContainer: Color(0xFF3A2F1A),
    onTertiaryContainer: Color(0xFFEBD5A6),
    error: Color(0xFFFF7A70),
    onError: Color(0xFF4A0806),
    errorContainer: Color(0xFF6E1512),
    onErrorContainer: Color(0xFFFFD9D5),
    surface: indigo,
    onSurface: Color(0xFFF2EDE3),
    onSurfaceVariant: Color(0xFFB8C2D6),
    surfaceContainerLowest: Color(0xFF101A2E),
    surfaceContainerLow: Color(0xFF13203A),
    surfaceContainer: indigo,
    surfaceContainerHigh: Color(0xFF1B2C4B),
    surfaceContainerHighest: Color(0xFF1F3355),
    surfaceTint: gold,
    outline: Color(0xFF5C6B87),
    outlineVariant: Color(0xFF33445F),
    inverseSurface: Color(0xFFF2EDE3),
    onInverseSurface: indigo,
    inversePrimary: indigo,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA9BEE6),
    onPrimary: Color(0xFF0F1D33),
    primaryContainer: Color(0xFF22314F),
    onPrimaryContainer: Color(0xFFD3DFF5),
    secondary: Color(0xFF9BA7BF),
    onSecondary: Color(0xFF1B2433),
    secondaryContainer: Color(0xFF202A3D),
    onSecondaryContainer: Color(0xFFD6DCE8),
    tertiary: Color(0xFFD3AD65),
    onTertiary: Color(0xFF2A2007),
    tertiaryContainer: Color(0xFF3A2F1A),
    onTertiaryContainer: Color(0xFFEBD5A6),
    error: Color(0xFFFF7A70),
    onError: Color(0xFF4A0806),
    errorContainer: Color(0xFF6E1512),
    onErrorContainer: Color(0xFFFFD9D5),
    surface: Color(0xFF141C2C),
    onSurface: Color(0xFFE7EAF2),
    onSurfaceVariant: Color(0xFFA0A6B8),
    surfaceContainerLowest: Color(0xFF0C1220),
    surfaceContainerLow: Color(0xFF121A29),
    surfaceContainer: Color(0xFF161F30),
    surfaceContainerHigh: Color(0xFF1B2537),
    surfaceContainerHighest: Color(0xFF212C40),
    surfaceTint: Color(0xFFA9BEE6),
    outline: Color(0xFF4B5670),
    outlineVariant: Color(0xFF2C3548),
    inverseSurface: Color(0xFFE7EAF2),
    onInverseSurface: indigo,
    inversePrimary: indigo,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

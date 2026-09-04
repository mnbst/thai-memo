import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_colors.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/analytics_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/subscription_provider.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'services/firebase_auth_service.dart';

TextTheme _buildThaiTextTheme(ThaiFont font, TextTheme base) {
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

/// Main application widget
class ThaiMemoApp extends ConsumerStatefulWidget {
  const ThaiMemoApp({super.key});

  @override
  ConsumerState<ThaiMemoApp> createState() => _ThaiMemoAppState();
}

class _ThaiMemoAppState extends ConsumerState<ThaiMemoApp>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Analytics の userId を認証状態に追従させる。
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(ref.read(analyticsServiceProvider).setUserId(user?.uid));
      // サインイン直後は uid が確定した時点で通知トークンを users/{uid} に登録する。
      // 毎日例文の取り込みは表示と順序を揃える必要があるため HomeScreen が持つ。
      if (user != null) {
        unawaited(
          ref.read(settingsControllerProvider.notifier).syncPushRegistration(),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(subscriptionControllerProvider.notifier).refreshTier();
    }
  }

  bool _anonSignInStarted = false;

  /// 未認証時に匿名サインインを一度だけ開始する。
  void _ensureAnonymousSignIn() {
    if (_anonSignInStarted) return;
    if (FirebaseAuth.instance.currentUser != null) return;
    _anonSignInStarted = true;
    unawaited(FirebaseAuthService.instance.signInAnonymously());
  }

  @override
  Widget build(BuildContext context) {
    // Watch theme mode and font family from settings
    final themeMode = ref.watch(themeModeProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    final appLanguage = ref.watch(appLanguageProvider);
    final analytics = ref.watch(analyticsServiceProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // 端末ロケールは見ない。言語はアプリ内設定（初期値はストア地域）だけで決める。
      locale: appLanguage.locale,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      onGenerateTitle: (context) => L10n.of(context).appTitle,
      // 通常の route 遷移は observer 側で screen_view を自動送信する。
      navigatorObservers: [analytics.observer],
      themeMode: themeMode,
      theme: _buildLightTheme(fontFamily),
      darkTheme: _buildDarkTheme(fontFamily),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            // 未認証なら匿名サインインを開始し、完了までローディング表示。
            // 匿名でも HomeScreen に進めるため、ログイン壁は出さない。
            _ensureAnonymousSignIn();
            return const _AuthLoadingScreen();
          }
          // 認証後にサブスクリプション状態をFirestoreから取得
          ref.read(subscriptionControllerProvider.notifier).initialize();
          return const SplashScreen(child: HomeScreen());
        },
      ),
    );
  }

  ThemeData _buildLightTheme(ThaiFont fontFamily) => _buildTheme(
        fontFamily,
        AppColors.light,
        ThemeData.light().textTheme,
        AppColors.paper,
      );

  ThemeData _buildDarkTheme(ThaiFont fontFamily) => _buildTheme(
        fontFamily,
        AppColors.dark,
        ThemeData.dark().textTheme,
        AppColors.paperDark,
      );

  /// 明暗で違うのは ColorScheme と背景色だけ。形（角丸・高さ・罫線）は共通。
  ///
  /// カードは影ではなく 1px の罫線で面を分ける。影を残すと、深藍の面と
  /// 温白の背景のコントラストに影が重なって濁るため。
  ThemeData _buildTheme(
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
      textTheme: _buildThaiTextTheme(fontFamily, baseTextTheme),
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
}

/// 起動時の匿名サインイン完了までの簡易ローディング画面。
/// 認証待ちの間もネイティブ起動画面と同じ絵を出し続ける。
/// ここで別の背景色やスピナーを挟むと、起動直後にちらついて見える。
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const SplashVisual();
  }
}

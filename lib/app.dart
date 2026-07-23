import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/config/app_config.dart';
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
    final analytics = ref.watch(analyticsServiceProvider);

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
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

  /// Build light theme
  ThemeData _buildLightTheme(ThaiFont fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E3A8A), // Royal Blue (Thai flag)
        brightness: Brightness.light,
      ),
      textTheme: _buildThaiTextTheme(fontFamily, ThemeData.light().textTheme),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// Build dark theme
  ThemeData _buildDarkTheme(ThaiFont fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E3A8A), // Royal Blue (Thai flag)
        brightness: Brightness.dark,
      ),
      textTheme: _buildThaiTextTheme(fontFamily, ThemeData.dark().textTheme),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.notoSans(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 4,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// 起動時の匿名サインイン完了までの簡易ローディング画面。
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/analytics_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/subscription_provider.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'services/firebase_auth_service.dart';

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
      theme: buildAppLightTheme(fontFamily),
      darkTheme: buildAppDarkTheme(fontFamily),
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

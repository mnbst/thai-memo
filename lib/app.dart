import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'presentation/providers/analytics_provider.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/remaining_quota_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/subscription_provider.dart';
import 'presentation/providers/tts_provider.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/widgets/tablet_width_limit.dart';
import 'services/firebase_auth_service.dart';
import 'services/anonymous_sign_in_coordinator.dart';

/// Main application widget
class ThaiMemoApp extends ConsumerStatefulWidget {
  const ThaiMemoApp({super.key});

  @override
  ConsumerState<ThaiMemoApp> createState() => _ThaiMemoAppState();
}

class _ThaiMemoAppState extends ConsumerState<ThaiMemoApp> {
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<void>? _thaiVoiceSubscription;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final AnonymousSignInCoordinator _anonymousSignIn;

  @override
  void initState() {
    super.initState();
    _anonymousSignIn = AnonymousSignInCoordinator(
      // アカウント削除後の端末データ掃除が終わるまで次のユーザーを作らない。
      canSignIn: () =>
          FirebaseAuth.instance.currentUser == null &&
          !ref.read(authControllerProvider).isLoading,
      signIn: () async {
        await FirebaseAuthService.instance.signInAnonymously();
      },
    );
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
    // users/{uid} はクォータ等がすでに監視している1本を共有する。
    // Subscription専用listenerを増やさず、同じ更新からtierも反映する。
    // 派生の userDocProvider を聞くと、別プロバイダの build 中に再計算されて
    // 通知が走り「build 中に他プロバイダを変更」になる。ストリーム本体を聞き、
    // 再購読時（build 中に出る loading）は飛ばして、届いたイベントだけ反映する。
    ref.listenManual(userDocSnapshotProvider, (_, next) {
      final uid = FirebaseAuthService.instance.currentUser?.uid;
      if (uid == null || next.isLoading || !next.hasValue) return;
      ref
          .read(subscriptionControllerProvider.notifier)
          .applyUserDocument(uid, next.value!.data);
    });
    _thaiVoiceSubscription = ref
        .read(ttsServiceProvider)
        .thaiVoiceMissing
        .listen((_) => _showThaiVoiceMissing());
  }

  /// 読み上げにタイ語の声が無い（Android）。どの画面で鳴らしても出せるよう、
  /// アプリ直下の ScaffoldMessenger から出す。
  void _showThaiVoiceMissing() {
    final messenger = _messengerKey.currentState;
    final context = _messengerKey.currentContext;
    if (messenger == null || context == null) return;
    final l10n = L10n.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.ttsThaiVoiceMissing),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.ttsThaiVoiceInstall,
          onPressed: () =>
              unawaited(ref.read(ttsServiceProvider).openVoiceInstaller()),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _anonymousSignIn.dispose();
    _authSubscription?.cancel();
    _thaiVoiceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider.select((state) => state.isLoading));
    // Watch theme mode and font family from settings
    final themeMode = ref.watch(themeModeProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    final appLanguage = ref.watch(appLanguageProvider);
    final analytics = ref.watch(analyticsServiceProvider);

    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
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
      builder: (context, child) => TabletWidthLimit(child: child!),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (user == null) {
            // 未認証なら匿名サインインを開始し、完了までローディング表示。
            // 匿名でも HomeScreen に進めるため、ログイン壁は出さない。
            _anonymousSignIn.ensureSignedIn();
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

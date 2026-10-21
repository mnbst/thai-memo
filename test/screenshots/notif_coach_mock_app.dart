// =============================================================================
// notif_coach_mock_app.dart
// 毎日例文通知の初回ダイアログ（NotificationCoachDialog）を、Firebase なしで
// シミュレーターに出して文言を確かめるモック。起動すると自動で開く。
//
//   flutter run -t test/screenshots/notif_coach_mock_app.dart
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/widgets/notification_coach_dialog.dart';

void main() => runApp(const _MockApp());

class _MockApp extends StatefulWidget {
  const _MockApp();

  @override
  State<_MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<_MockApp> {
  Locale _locale = const Locale('ja');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppLightTheme(ThaiFont.sarabun),
      locale: _locale,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      home: _Home(
        locale: _locale,
        onLocale: (l) => setState(() => _locale = l),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.locale, required this.onLocale});

  final Locale locale;
  final ValueChanged<Locale> onLocale;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => showNotificationCoachDialog(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('初回ダイアログ')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ja', label: Text('日本語')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {widget.locale.languageCode},
              onSelectionChanged: (v) => widget.onLocale(Locale(v.first)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showNotificationCoachDialog(context),
              child: const Text('ダイアログを開く'),
            ),
          ],
        ),
      ),
    );
  }
}

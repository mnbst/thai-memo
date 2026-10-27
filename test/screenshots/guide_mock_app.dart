// 使い方ガイド（GuideScreen）を Firebase なしでシミュレーターに出す一時モック。
//   flutter run -t test/screenshots/guide_mock_app.dart --dart-define=POS=0.8
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/screens/guide_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';

const _pos = String.fromEnvironment('POS', defaultValue: '0');
const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

class _FakeAnalytics implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() => runApp(ProviderScope(
      overrides: [analyticsServiceProvider.overrideWithValue(_FakeAnalytics())],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        locale: const Locale(_lang),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        home: const _Jump(child: GuideScreen()),
      ),
    ));

class _Jump extends StatefulWidget {
  const _Jump({required this.child});
  final Widget child;
  @override
  State<_Jump> createState() => _JumpState();
}

class _JumpState extends State<_Jump> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      ScrollableState? found;
      void visit(Element e) {
        if (found != null) return;
        if (e is StatefulElement && e.state is ScrollableState) {
          found = e.state as ScrollableState;
          return;
        }
        e.visitChildren(visit);
      }
      context.visitChildElements(visit);
      final p = found?.position;
      if (p == null) return;
      // 遅延リストは末尾の高さを後から確定するので、数回詰める。
      for (var i = 0; i < 5; i++) {
        Future.delayed(Duration(milliseconds: 300 * i), () {
          p.jumpTo(p.maxScrollExtent * double.parse(_pos));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

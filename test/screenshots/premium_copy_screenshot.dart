// =============================================================================
// premium_copy_screenshot.dart
// 有料版の説明（ペイウォール・ガイドのプラン表・体験終了ダイアログ・語彙100到達
// シート）を Firebase なしで PNG に書き出す。文言を変える前後の見比べ用。
// `_test.dart` ではないので通常の `flutter test` では走らない。
//
//   flutter test test/screenshots/premium_copy_screenshot.dart \
//     --dart-define=SCREEN=paywall   # paywall / plan / trial / vocab_cap
//     --dart-define=OUT=build/premium_copy/paywall.png \
//     --dart-define=H=896            # 論理高さ
//
// 設定画面の金色ヒントは settings_screenshot.dart（PLAN=free）で撮る。
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/paywall_screen.dart';
import 'package:thai_memo/presentation/widgets/plan_compare_table.dart';
import 'package:thai_memo/presentation/widgets/premium_trial_ended_dialog.dart';
import 'package:thai_memo/presentation/widgets/vocab_cap_sheet.dart';
import 'package:thai_memo/services/analytics_service.dart';

const double _width = 414;
final double _height =
    double.parse(const String.fromEnvironment('H', defaultValue: '896'));
const double _pixelRatio = 3;
const String _screen = String.fromEnvironment('SCREEN', defaultValue: 'paywall');
const String _out = String.fromEnvironment('OUT',
    defaultValue: 'build/premium_copy/$_screen.png');

const List<String> _fallbacks = ['NotoSans_regular', 'NotoSansJP'];

void main() {
  testWidgets('有料版の説明を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    tester.view.physicalSize = Size(_width * _pixelRatio, _height * _pixelRatio);
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(_out);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE ${file.path}');
  });
}

Widget _body() {
  switch (_screen) {
    case 'plan':
      return const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: PlanCompareTable(),
            ),
          ),
        ),
      );
    case 'trial':
      return const Scaffold(
        body: Center(child: PremiumTrialEndedDialog()),
      );
    case 'vocab_cap':
      return const Scaffold(
        body: SafeArea(child: VocabCapSheet()),
      );
    default:
      return const PaywallScreen(source: 'screenshot');
  }
}

Widget _host() {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
      userDocSnapshotProvider.overrideWith(
        (ref) =>
            Stream.value(const UserDocSnapshot(data: null, isFromCache: false)),
      ),
      subscriptionControllerProvider.overrideWith((ref) => _StubController()),
      // 体験終了ダイアログの語彙スコア行が出るよう、上限を超えた測定値にする。
      vocabStatsProvider.overrideWith(
          (ref) => Stream.value(VocabStats(estimatedVocab: 450))),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _themeWithFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      home: RepaintBoundary(key: const ValueKey('shot'), child: _body()),
    ),
  );
}

class _StubController extends SubscriptionController {
  _StubController()
      : super(
          analytics: _NoopAnalytics(),
          l10n: () => lookupL10n(const Locale('ja')),
        ) {
    state = SubscriptionState(
      product: _product('premium_monthly', 'プレミアム（月額）', '¥600', 600),
      yearlyProduct: _product('premium_annual', 'プレミアム（年額）', '¥4,800', 4800),
      lifetimeProduct:
          _product('premium_lifetime', 'プレミアム 買い切り', '¥5,800', 5800),
    );
  }

  static ProductDetails _product(
          String id, String title, String price, double rawPrice) =>
      ProductDetails(
        id: id,
        title: title,
        description: title,
        price: price,
        rawPrice: rawPrice,
        currencyCode: 'JPY',
      );
}

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  Future<void> logPaywallView({
    required String source,
    required bool productLoaded,
  }) async {}

  @override
  Future<void> logTapPaywall({required String source}) async {}
}

ThemeData _themeWithFallbacks(ThemeData theme) {
  TextStyle withFallback(TextStyle style) =>
      style.copyWith(fontFamilyFallback: _fallbacks);
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamilyFallback: _fallbacks),
    primaryTextTheme:
        theme.primaryTextTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: withFallback(
        theme.appBarTheme.titleTextStyle ?? const TextStyle(),
      ),
    ),
  );
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths,
      {bool firstOnly = false}) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      any = true;
      loader
          .addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      if (firstOnly) break;
    }
    if (any) await loader.load();
  }

  const weights = {
    'Regular': 'regular',
    'Medium': '500',
    'SemiBold': '600',
    'Bold': '700',
  };
  for (final entry in weights.entries) {
    await load(
        'Sarabun_${entry.value}', ['google_fonts/Sarabun-${entry.key}.ttf']);
    await load(
        'NotoSans_${entry.value}', ['google_fonts/NotoSans-${entry.key}.ttf']);
  }
  await load('MaterialIcons', _materialIconsCandidates(), firstOnly: true);
  await load('NotoSansJP', ['tools/x_post/fonts/NotoSansJP-Regular.otf']);
}

List<String> _materialIconsCandidates() {
  const relative = 'artifacts/material_fonts/MaterialIcons-Regular.otf';
  final paths = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) paths.add('$root/bin/cache/$relative');
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    paths.add('${dir.path}/$relative');
    dir = dir.parent;
  }
  return paths;
}

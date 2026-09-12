// =============================================================================
// paywall_review_screenshot.dart
// App Store Connect の審査用スクリーンショット（アプリ内課金の購入画面）を作る。
// 通常の `flutter test` では拾われない（_test.dart で終わらない）。
//
//   flutter test test/screenshots/paywall_review_screenshot.dart \
//     --dart-define=PAYWALL_SHOT_OUT=build/appstore
//
// 実機・シミュレータだとストアに商品が行き渡るまで買い切りボタンが出ない。
// ここでは商品をこちらで差し込んで描くので、価格も含めて確実に写る。
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
import 'package:thai_memo/presentation/screens/paywall_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';

/// iPhone 11 Pro Max の論理サイズと描画倍率（= 1242x2688）。
/// App Store Connect の審査用スクショはこの寸法をそのまま受け付ける。
const double _logicalWidth = 414;
const double _logicalHeight = 896;
const double _pixelRatio = 3;

const String _outDir =
    String.fromEnvironment('PAYWALL_SHOT_OUT', defaultValue: 'build/appstore');

const List<String> _fallbacks = ['NotoSans_regular', 'NotoSansJP'];

void main() {
  testWidgets('買い切りボタン入りのペイウォールを撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    // 自動更新の開示文は iOS でだけ出る。審査で見る側と同じ面にする。
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    tester.view.physicalSize =
        const Size(_logicalWidth * _pixelRatio, _logicalHeight * _pixelRatio);
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final bytes = await _capture(tester);
    final file = File('$_outDir/paywall_review.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('WROTE ${file.path} (${bytes.length} bytes)');
  });
}

Widget _host() {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
      // 体験トライアルの注記は出さない（購入の導線だけを写す）。
      // Firestore を触らせないためにも差し替える。
      userDocProvider.overrideWith((ref) => Stream.value(null)),
      subscriptionControllerProvider.overrideWith((ref) => _StubController()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _themeWithFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      home: RepaintBoundary(
        key: const ValueKey('paywall-shot'),
        child: const Scaffold(
          body: PaywallBottomSheet(source: 'appstore_review'),
        ),
      ),
    ),
  );
}

/// ストアから商品を引けた状態の SubscriptionController。
class _StubController extends SubscriptionController {
  _StubController()
      : super(
          analytics: _NoopAnalytics(),
          l10n: () => lookupL10n(const Locale('ja')),
        ) {
    state = SubscriptionState(
      product: _product(
        id: 'premium_monthly',
        title: 'プレミアム（月額）',
        price: '¥600',
        rawPrice: 600,
      ),
      lifetimeProduct: _product(
        id: 'premium_lifetime',
        title: 'プレミアム 買い切り',
        price: '¥1,800',
        rawPrice: 1800,
      ),
    );
  }

  static ProductDetails _product({
    required String id,
    required String title,
    required String price,
    required double rawPrice,
  }) {
    return ProductDetails(
      id: id,
      title: title,
      description: title,
      price: price,
      rawPrice: rawPrice,
      currencyCode: 'JPY',
    );
  }
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

/// 日本語グリフを持たないフォントで豆腐にならないよう、フォールバックを足す。
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
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
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

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('paywall-shot')),
  );
  final image = await boundary.toImage(pixelRatio: _pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
